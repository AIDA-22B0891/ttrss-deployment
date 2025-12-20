#' Подключение к БД
#'
#' Создает соединение с PostgreSQL, используя переменные из .env
#' @return Объект соединения DBI
#' @export
connect_to_db <- function() {
  # Проверяем, что переменные загружены
  if (Sys.getenv("DB_HOST") == "") {
    stop("❌ Ошибка: DB_HOST не задан. Проверь .env файл.")
  }

  DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("DB_HOST"),
    port = Sys.getenv("DB_PORT"),
    dbname = Sys.getenv("DB_NAME"),
    user = Sys.getenv("DB_USER"),
    password = Sys.getenv("DB_PASS")
  )
}

#' Инициализация таблицы
#'
#' Создает таблицу news_analysis, если она не существует.
#' @param con Соединение с БД
#' @export
init_db_schema <- function(con) {
  # Проверяем, есть ли таблица news_analysis
  if (!DBI::dbExistsTable(con, "news_analysis")) {
    
    # Создаем таблицу SQL-запросом
    # Обрати внимание: я добавил IF NOT EXISTS в сам SQL для надежности
    query <- "
      CREATE TABLE IF NOT EXISTS news_analysis (
        id SERIAL PRIMARY KEY,
        news_id TEXT UNIQUE,      -- ID из TT-RSS
        title TEXT,               -- Заголовок
        link TEXT,                -- Ссылка
        published_at TIMESTAMP,   -- Дата публикации
        category TEXT,            -- От ИИ
        summary TEXT,             -- От ИИ
        score INTEGER,            -- От ИИ
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      );
    "
    DBI::dbExecute(con, query)
    message("✅ Таблица 'news_analysis' успешно создана!")
  } else {
    message("ℹ️ Таблица уже существует, пропускаем создание.")
  }
}

#' Сохранение результатов
#'
#' Сохраняет новость и результат работы ИИ в базу.
#' 
#' @param con Соединение с БД
#' @param news_row Строка с данными новости (из TT-RSS)
#' @param ai_result Список с результатами от YandexGPT (category, summary, score)
#' @param clean_text Очищенный текст новости (принимаем, даже если не пишем в эту таблицу)
#' @export
save_article_to_db <- function(con, news_row, ai_result, clean_text) {
  
  # Подготовка данных (защита от NULL и пустых значений)
  cat_val <- if (!is.null(ai_result$category)) ai_result$category else "Unknown"
  sum_val <- if (!is.null(ai_result$summary)) ai_result$summary else ""
  score_val <- if (!is.null(ai_result$score)) as.integer(ai_result$score) else 0
  
  # Запрос на вставку
  query <- "
    INSERT INTO news_analysis (news_id, title, link, published_at, category, summary, score)
    VALUES ($1, $2, $3, $4, $5, $6, $7)
    ON CONFLICT (news_id) DO NOTHING;
  "
  
  # Выполняем безопасную вставку (защита от SQL-инъекций через параметры)
  DBI::dbExecute(con, query, list(
    as.character(news_row$id),
    news_row$title,
    news_row$link,
    as.POSIXct(news_row$published, origin="1970-01-01"), 
    cat_val,
    sum_val,
    score_val
  ))
}
