#' Главная функция запуска пайплайна
#'
#' Скачивает новости, прогоняет через AI и сохраняет в БД.
#'
#' @param items_count Сколько новостей обработать за один запуск (по умолчанию 5)
#' @return NULL (процедура выполняется с побочными эффектами)
#' @export
run_pipeline_db <- function(items_count = 5) {
  
  # 1. Читаем конфиги из окружения
  ttrss_url  <- Sys.getenv("TTRSS_URL")
  ttrss_user <- Sys.getenv("TTRSS_USER")
  ttrss_pass <- Sys.getenv("TTRSS_PASS")
  ya_folder  <- Sys.getenv("YA_FOLDER_ID")
  ya_key     <- Sys.getenv("YA_API_KEY")
  
  # Проверка настроек
  if (ttrss_url == "" || ya_key == "") {
    stop("❌ Ошибка: Переменные окружения (TTRSS_URL, YA_API_KEY) не заданы.")
  }
  
  # 2. Подготовка подключений
  message("📡 Подключаюсь к TT-RSS...")
  # Используем try, чтобы сбой сети не крашил весь процесс сразу
  sid <- try(ttrss_login(ttrss_url, ttrss_user, ttrss_pass), silent = TRUE)
  if (inherits(sid, "try-error")) {
    message("❌ Не удалось залогиниться в TT-RSS.")
    return(NULL)
  }
  
  message("🔌 Подключаюсь к Базе Данных...")
  con <- try(connect_to_db(), silent = TRUE)
  if (inherits(con, "try-error")) {
    message("❌ Не удалось подключиться к БД.")
    return(NULL)
  }
  
  # Гарантируем закрытие соединения при выходе из функции
  on.exit(DBI::dbDisconnect(con))
  
  # Создаем таблицу, если нет
  init_db_schema(con)
  
  # 3. Скачиваем новости
  message(paste("📥 Скачиваю", items_count, "непрочитанных новостей..."))
  news_items <- ttrss_get_unread(ttrss_url, sid, limit = items_count)
  
  if (is.null(news_items) || nrow(news_items) == 0) {
    message("ℹ️ Нет новых новостей. Отдыхаем.")
    return(NULL)
  }
  
  message(paste("Найдено новостей:", nrow(news_items)))
  
  # 4. Цикл обработки
  for (i in 1:nrow(news_items)) {
    item <- news_items[i, ]
    message(paste0("⚙️ [", i, "/", nrow(news_items), "] Обрабатываю ID ", item$id, ": ", item$title))
    
    tryCatch({
      # ШАГ 0: Чистим текст (важно для LLM и БД)
      clean_txt <- clean_html_text(item$content)
      
      # ШАГ 1: ИИ
      ai_res <- classify_news_yandex(clean_txt, ya_folder, ya_key)
      
      if (is.null(ai_res) || identical(ai_res$category, "Error")) {
        stop("Ошибка или пустой ответ от YandexGPT")
      }
      
      # ШАГ 2: БД (передаем очищенный текст и результат AI)
      save_article_to_db(con, item, ai_res, clean_txt)
      
      # ШАГ 3: Подтверждение (галочка "Прочитано" в TT-RSS)
      ttrss_mark_read(ttrss_url, sid, item$id)
      
      message("   ✅ Сохранено и помечено прочитанным.")
      
    }, error = function(e) {
      message(paste("   ❌ СБОЙ. Новость пропущена:", e$message))
    })
    
    # Небольшая пауза, чтобы не дудосить API
    Sys.sleep(1) 
  }
  
  message("🏁 Готово.")
}