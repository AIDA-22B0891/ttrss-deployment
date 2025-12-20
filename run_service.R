# run_service.R
# Этот скрипт будет запускать Docker
devtools::load_all() # Или library(NewsHarvestR) если пакет установлен

while(TRUE) {
  run_pipeline_job()
  Sys.sleep(3600) # Сон 1 час
}