#' Анализ новости через YandexGPT
#'
#' Отправляет текст в LLM для классификации, саммаризации и оценки важности.
#'
#' @param text Текст новости
#' @param folder_id ID каталога в Yandex Cloud
#' @param api_key API-ключ сервисного аккаунта
#' @return Список с полями category, summary, score (или Error при ошибке)
#' @export
classify_news_yandex <- function(text, folder_id, api_key) {
  
  # Проверка входных данных
  if (nchar(text) < 10) return(list(category = "Skip", summary = "Текст слишком короткий", score = 0))
  
  url <- "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"
  
  # Промпт: Классификация + Тизер + Оценка
  system_prompt <- "Ты — новостной редактор. Твоя задача:
  1. Классифицировать текст (дай короткий тег, максимум 2 слова). Если это не новость, верни 'Не новость'.
  2. Сделать тизер (короткое содержание, максимум 1 предложение).
  3. Оценить важность для IT (число 1-10).
  
  Верни ответ СТРОГО в формате JSON:
  {\"category\": \"...\", \"summary\": \"...\", \"score\": ...}"
  
  # Используем модель 'latest'
  model_uri <- paste0("gpt://", folder_id, "/yandexgpt/latest")
  
  body <- list(
    modelUri = model_uri,
    completionOptions = list(
      stream = FALSE,
      temperature = 0.3,
      maxTokens = 1000  # Исправлено: передаем число, а не строку
    ),
    messages = list(
      list(role = "system", text = system_prompt),
      list(role = "user", text = substr(text, 1, 4000)) # Обрезаем лишнее
    )
  )
  
  tryCatch({
    # Цепочка вызовов через httr2
    resp <- httr2::request(url) |>
      httr2::req_headers(
        "Authorization" = paste("Api-Key", api_key),
        "x-folder-id" = folder_id
      ) |>
      httr2::req_body_json(body) |>
      httr2::req_perform()
    
    parsed <- httr2::resp_body_json(resp)
    
    # Достаем текст ответа
    ai_text <- parsed$result$alternatives[[1]]$message$text
    
    # Чистим ответ от Markdown (если модель решила вернуть ```json)
    ai_text <- gsub("```json", "", ai_text)
    ai_text <- gsub("```", "", ai_text)
    
    # Парсим JSON
    return(jsonlite::fromJSON(ai_text))
    
  }, error = function(e) {
    message(paste("YandexGPT Error:", e$message))
    # Возвращаем безопасную заглушку, чтобы пайплайн не падал
    return(list(category = "Error", summary = "Ошибка API", score = 0))
  })
}