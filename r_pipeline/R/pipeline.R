library(dplyr)
library(purrr)

source("R/ttrss_client.R")
source("R/llm_client.R")
source("R/db_storage.R")

#' Главная функция запуска пайплайна
#' @param items_count Сколько новостей обработать (по умолчанию 5)
run_pipeline_db <- function(items_count = 5) {
  
  # 1. Читаем конфиги
  readRenviron(".env")
  
  ttrss_url  <- Sys.getenv("TTRSS_URL")
  ya_folder  <- Sys.getenv("YA_FOLDER_ID")
  ya_key     <- Sys.getenv("YA_API_KEY")
  
  if (ttrss_url == "" || ya_key == "") stop("❌ Ошибка: Проверь .env файл!")
  
  # 2. Подготовка
  print("📡 Подключаюсь к TT-RSS...")
  sid <- ttrss_login(ttrss_url, Sys.getenv("TTRSS_USER"), Sys.getenv("TTRSS_PASS"))
  
  print("🔌 Подключаюсь к Базе Данных...")
  con <- connect_db()
  init_db_table(con)
  
  # 3. Скачиваем нужное количество новостей
  print(paste("📥 Скачиваю", items_count, "непрочитанных новостей..."))
  news_items <- ttrss_get_unread(ttrss_url, sid, limit = items_count)
  
  if (is.null(news_items) || nrow(news_items) == 0) {
    print("ℹ️ Нет новых новостей. Отдыхаем.")
    dbDisconnect(con)
    return(NULL)
  }
  
  print(paste("Найдено новостей:", nrow(news_items)))
  
  # 4. Цикл обработки
  for (i in 1:nrow(news_items)) {
    item <- news_items[i, ]
    print(paste0("⚙️ [", i, "/", nrow(news_items), "] Обрабатываю ID ", item$id, ": ", item$title))
    
    tryCatch({
      # ШАГ 1: ИИ
      ai_res <- classify_news_yandex(item$content, ya_folder, ya_key)
      if (ai_res$category == "Error") stop("Ошибка генерации YandexGPT")
      
      # ШАГ 2: БД
      save_news_result(con, item, ai_res)
      
      # ШАГ 3: Подтверждение (галочка "Прочитано")
      ttrss_mark_read(ttrss_url, sid, item$id)
      
      print("   ✅ Сохранено и помечено прочитанным.")
      
    }, error = function(e) {
      print(paste("   ❌ СБОЙ. Новость пропущена:", e$message))
    })
    
    # Небольшая пауза
    Sys.sleep(1) 
  }
  
  dbDisconnect(con)
  print("🏁 Готово.")
}