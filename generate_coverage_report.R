#!/usr/bin/env Rscript

# Скрипт для генерации отчета о покрытии тестов

# Установка библиотек
installed_packages <- rownames(installed.packages())

if (!"covr" %in% installed_packages) {
  install.packages("covr", repos = "https://cran.rstudio.com/")
}

if (!"rsconnect" %in% installed_packages) {
  install.packages("rsconnect", repos = "https://cran.rstudio.com/")
}

library(covr)
library(rsconnect)

# Путь к директории с пакетом
package_path <- "."  # текущая директория

# Генерация отчета о покрытии
print("Генерация отчета о покрытии тестов...")

# Проверяем, что у нас есть тесты
test_dir <- file.path(package_path, "tests", "testthat")
if (!dir.exists(test_dir)) {
  stop("Директория с тестами не найдена: ", test_dir)
}

# Получаем список файлов с тестами
test_files <- list.files(test_dir, pattern = "*.R", full.names = TRUE)
if (length(test_files) == 0) {
  stop("Файлы с тестами не найдены в: ", test_dir)
}

print(paste("Найдено тестов:", length(test_files)))

# Запускаем тесты и измеряем покрытие
coverage_report <- package_coverage(
  path = package_path,
 type = "all"  # Покрытие для всех типов (функций, строк, ветвлений)
)

print("Отчет о покрытии:")
print(coverage_report)

# Сохраняем отчет в виде HTML
report_path <- "coverage_report"
save_for_server(coverage_report, report_path)

print(paste("HTML отчет сохранен в директорию:", report_path))

# Также можно получить покрытие по отдельным файлам
print("Покрытие по файлам:")
file_coverage <- as.data.frame(coverage_report)
for (i in 1:nrow(file_coverage)) {
  print(paste(
    basename(file_coverage$file[i]), 
    "- Покрытие:", 
    round(file_coverage$coverage[i], 2), "%"
  ))
}

# Проверяем порог покрытия
min_coverage_threshold <- 80 # Минимальный порог покрытия в процентах
actual_coverage <- round(coverage_report$coverage, 2)

if (actual_coverage >= min_coverage_threshold) {
  print(paste("✅ Покрытие тестами составляет", actual_coverage, "%, что выше минимального порога", min_coverage_threshold, "%"))
} else {
  print(paste("⚠️ Покрытие тестами составляет", actual_coverage, "%, что ниже минимального порога", min_coverage_threshold, "%"))
  print("Рекомендуется добавить больше тестов для повышения покрытия")
}

# Сохраняем результаты в JSON для последующего анализа
results <- list(
  total_coverage = actual_coverage,
  min_threshold = min_coverage_threshold,
  files_coverage = file_coverage,
  timestamp = Sys.time()
)

jsonlite::write_json(results, "coverage_results.json", auto_unbox = TRUE, pretty = TRUE)

print("Результаты покрытия сохранены в coverage_results.json")