# check_data_quality.R
# Скрипт для проверки качества данных (Data Quality Assurance)

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
  library(dplyr)
  library(NewsHarvestR)
})

cat("\n========================================\n")
cat("🕵️  ЗАПУСК АНАЛИЗА КАЧЕСТВА ДАННЫХ\n")
cat("========================================\n")

# 1. Подключение
con <- tryCatch({
  connect_to_db()
}, error = function(e) {
  stop("❌ Не удалось подключиться к БД. Проверьте .env")
})

table_name <- "news_analysis"

# Функция для красивого вывода
report <- function(title, status, detail = "") {
  icon <- if (status == "OK") "✅" else if (status == "WARN") "⚠️ " else "❌"
  cat(sprintf("%s %s\n", icon, title))
  if (detail != "") cat(sprintf("      -> %s\n", detail))
}

# --- ПРОВЕРКА 1: ДУБЛИКАТЫ ---
cat("\n[1] Поиск дубликатов...\n")
dupes <- dbGetQuery(con, paste("
  SELECT link, COUNT(*) as cnt 
  FROM", table_name, "
  GROUP BY link 
  HAVING COUNT(*) > 1
"))

if (nrow(dupes) == 0) {
  report("Дубликатов по ссылкам нет", "OK")
} else {
  report("Найдены дубликаты!", "WARN", paste("Количество ссылок с повторами:", nrow(dupes)))
  cat("      (Рекомендуется запустить очистку базы)\n")
}

# --- ПРОВЕРКА 2: ДАТЫ ИЗ БУДУЩЕГО ---
cat("\n[2] Проверка временных аномалий...\n")
future_news <- dbGetQuery(con, paste("
  SELECT COUNT(*) as cnt 
  FROM", table_name, "
  WHERE published_at > NOW() + INTERVAL '1 day'
"))$cnt

if (future_news == 0) {
  report("Новостей из будущего нет", "OK")
} else {
  report("Найдены новости из будущего", "FAIL", paste("Количество:", future_news))
}

# --- ПРОВЕРКА 3: ПРОПУЩЕННЫЕ ОЦЕНКИ (NULL) ---
cat("\n[3] Проверка полноты данных (NULL)...\n")
null_scores <- dbGetQuery(con, paste("
  SELECT COUNT(*) as cnt 
  FROM", table_name, "
  WHERE score IS NULL
"))$cnt

total_rows <- dbGetQuery(con, paste("SELECT COUNT(*) as cnt FROM", table_name))$cnt
pct_null <- round((null_scores / total_rows) * 100, 1)

if (null_scores == 0) {
  report("Все новости имеют оценку (Score)", "OK")
} else if (pct_null < 10) {
  report("Есть новости без оценки", "OK", paste0("Всего ", null_scores, " (", pct_null, "% от базы) — это нормально."))
} else {
  report("Много новостей без оценки!", "WARN", paste0("Пропущено ", pct_null, "% записей. LLM не успевает?"))
}

# --- ПРОВЕРКА 4: ВАЛИДНОСТЬ ОЦЕНОК (0-10) ---
cat("\n[4] Проверка диапазона оценок...\n")
weird_scores <- dbGetQuery(con, paste("
  SELECT COUNT(*) as cnt 
  FROM", table_name, "
  WHERE score < 0 OR score > 10
"))$cnt

if (weird_scores == 0) {
  report("Все оценки в диапазоне 0-10", "OK")
} else {
  report("Найдены некорректные оценки", "FAIL", paste("Количество:", weird_scores))
}

# --- ПРОВЕРКА 5: РАСПРЕДЕЛЕНИЕ КАТЕГОРИЙ ---
cat("\n[5] Топ-5 Категорий...\n")
cats <- dbGetQuery(con, paste("
  SELECT category, COUNT(*) as cnt 
  FROM", table_name, "
  GROUP BY category 
  ORDER BY cnt DESC 
  LIMIT 5
"))
print(cats)

dbDisconnect(con)
cat("\n========================================\n")
cat("🏁 АНАЛИЗ ЗАВЕРШЕН\n")
cat("========================================\n")