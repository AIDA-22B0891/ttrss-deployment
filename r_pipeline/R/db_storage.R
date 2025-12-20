library(DBI)
library(RPostgres)
library(dplyr)

#' Подключение к БД
connect_db <- function() {
  con <- dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("DB_HOST"),
    port = Sys.getenv("DB_PORT"),
    dbname = Sys.getenv("DB_NAME"),
    user = Sys.getenv("DB_USER"),
    password = Sys.getenv("DB_PASS")
  )
  return(con)
}

#' Инициализация таблицы (запускаем 1 раз)
init_db_table <- function(con) {
  # Проверяем, есть ли таблица news_analysis
  if (!dbExistsTable(con, "news_analysis")) {
    
    # Создаем таблицу SQL-запросом
    query <- "
      CREATE TABLE news_analysis (
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
    dbExecute(con, query)
    print("✅ Таблица 'news_analysis' успешно создана!")
  } else {
    print("ℹ️ Таблица уже существует, пропускаем создание.")
  }
}

#' Сохранение результатов
save_news_result <- function(con, news_row, ai_result) {
  
  # Подготовка данных (защита от NULL)
  cat_val <- ifelse(is.null(ai_result$category), "Unknown", ai_result$category)
  sum_val <- ifelse(is.null(ai_result$summary), "", ai_result$summary)
  score_val <- ifelse(is.null(ai_result$score), 0, as.integer(ai_result$score))
  
  # Запрос на вставку
  query <- "
    INSERT INTO news_analysis (news_id, title, link, published_at, category, summary, score)
    VALUES ($1, $2, $3, $4, $5, $6, $7)
    ON CONFLICT (news_id) DO NOTHING;
  "
  
  # Выполняем
  dbExecute(con, query, list(
    as.character(news_row$id),
    news_row$title,
    news_row$link,
    as.POSIXct(news_row$updated, origin="1970-01-01"), 
    cat_val,
    sum_val,
    score_val
  ))
}