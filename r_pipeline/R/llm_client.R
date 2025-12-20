library(httr2)
library(jsonlite)
library(dplyr)
library(purrr)

#' Анализ новости через YandexGPT
#' @param text Текст новости
#' @param folder_id ID каталога
#' @param api_key API-ключ
classify_news_yandex <- function(text, folder_id, api_key) {
  
  url <- "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"
  
  # Промпт собран из твоих инструкций:
  # 1. Классификация (тег макс 2 слова)
  # 2. Суммаризация (тизер макс 1 предложение)
  system_prompt <- "Ты — новостной редактор. Твоя задача:
  1. Классифицировать текст (дай короткий тег, максимум 2 слова). Если это не новость, верни 'Не новость'.
  2. Сделать тизер (короткое содержание, максимум 1 предложение).
  3. Оценить важность для IT (число 1-10).
  
  Верни ответ СТРОГО в формате JSON:
  {\"category\": \"...\", \"summary\": \"...\", \"score\": ...}"
  
  # Используем модель 'latest', она умнее, чем 'lite/rc'
  model_uri <- paste0("gpt://", folder_id, "/yandexgpt/latest")
  
  body <- list(
    modelUri = model_uri,
    completionOptions = list(
      stream = FALSE,
      temperature = 0.3,
      maxTokens = "1000"
    ),
    messages = list(
      list(role = "system", text = system_prompt),
      list(role = "user", text = substr(text, 1, 4000))
    )
  )
  
  tryCatch({
    resp <- request(url) %>%
      req_headers(
        "Authorization" = paste("Api-Key", api_key),
        "x-folder-id" = folder_id
      ) %>%
      req_body_json(body) %>%
      req_perform()
    
    parsed <- resp %>% resp_body_json()
    ai_text <- parsed$result$alternatives[[1]]$message$text
    
    # Чистим ответ от Markdown
    ai_text <- gsub("```json", "", ai_text)
    ai_text <- gsub("```", "", ai_text)
    
    return(fromJSON(ai_text))
    
  }, error = function(e) {
    warning(paste("YandexGPT Error:", e$message))
    return(list(category = "Error", summary = "Ошибка API", score = 0))
  })
}