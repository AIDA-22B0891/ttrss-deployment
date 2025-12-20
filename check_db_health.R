# check_db_health.R
# Скрипт для быстрой проверки здоровья базы данных и настроек

suppressPackageStartupMessages({
  library(DBI)
  library(RPostgres)
  library(dplyr)
  library(NewsHarvestR) # Твой пакет
})

cat("\n========================================\n")
cat("🚀 ЗАПУСК ДИАГНОСТИКИ СИСТЕМЫ\n")
cat("========================================\n")

# --- ШАГ 1: Проверка окружения ---
cat("\n[1] Проверка переменных окружения (.env)...\n")
required_vars <- c("DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASS")
missing_vars <- c()

for (var in required_vars) {
  val <- Sys.getenv(var)
  if (val == "") {
    missing_vars <- c(missing_vars, var)
  } else {
    # Скрываем пароль звездочками для безопасности
    display_val <- if (var == "DB_PASS") "*****" else val
    cat(sprintf("  ✅ %s: %s\n", var, display_val))
  }
}

if (length(missing_vars) > 0) {
  cat(sprintf("  ❌ ОШИБКА: Не найдены переменные: %s\n", paste(missing_vars, collapse = ", ")))
  stop("Остановите скрипт и проверьте файл .env")
} else {
  cat("  ✨ Все переменные на месте.\n")
}

# --- ШАГ 2: Подключение к БД ---
cat("\n[2] Подключение к базе данных...\n")

con <- tryCatch({
  connect_to_db()
}, error = function(e) {
  cat("  ❌ ОШИБКА ПОДКЛЮЧЕНИЯ:\n")
  print(e)
  return(NULL)
})

if (!is.null(con)) {
  cat("  ✅ Успешное подключение к PostgreSQL!\n")
  
  # --- ШАГ 3: Проверка таблицы ---
  cat("\n[3] Проверка данных...\n")
  table_name <- "news_analysis"
  
  if (dbExistsTable(con, table_name)) {
    cat(sprintf("  ✅ Таблица '%s' найдена.\n", table_name))
    
    # Статистика
    count <- dbGetQuery(con, paste("SELECT COUNT(*) as n FROM", table_name))$n
    cat(sprintf("  📊 Всего записей: %s\n", count))
    
    if (count > 0) {
      # Проверка свежести
      last_date <- dbGetQuery(con, paste("SELECT MAX(published_at) as d FROM", table_name))$d
      cat(sprintf("  🕒 Последняя новость от: %s\n", last_date))
      
      # Проверка оценок
      avg_score <- dbGetQuery(con, paste("SELECT AVG(score) as s FROM", table_name))$s
      cat(sprintf("  🧠 Средняя оценка AI: %s\n", round(as.numeric(avg_score), 2)))
      
      # Показать примеры
      cat("\n  📝 Последние 3 новости:\n")
      recent <- dbGetQuery(con, paste("SELECT title, score, category FROM", table_name, "ORDER BY published_at DESC LIMIT 3"))
      print(recent)
    } else {
      cat("  ⚠️ Таблица пустая! Запустите сборщик новостей.\n")
    }
    
  } else {
    cat(sprintf("  ❌ ОШИБКА: Таблица '%s' не найдена!\n", table_name))
  }
  
  dbDisconnect(con)
  cat("\n  🔌 Соединение закрыто.\n")
}

cat("\n========================================\n")
cat("🏁 ДИАГНОСТИКА ЗАВЕРШЕНА\n")
cat("========================================\n")