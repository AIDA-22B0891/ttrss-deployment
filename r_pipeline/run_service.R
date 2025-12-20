# run_service.R
# Этот скрипт будет запускать Docker

# Загружаем все необходимые библиотеки
library(dplyr)
library(purrr)
library(DBI)
library(RPostgres)
library(httr2)
library(jsonlite)

# Загружаем наши скрипты
source("R/ttrss_client.R")
source("R/llm_client.R")
source("R/db_storage.R")
source("R/pipeline.R")

while(TRUE) {
  # Запускаем основной пайплайн
  run_pipeline_db(items_count = 5)
  Sys.sleep(3600) # Сон 1 час
}