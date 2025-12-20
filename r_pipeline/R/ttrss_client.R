library(httr2)
library(jsonlite)
library(dplyr)
library(purrr)

ttrss_login <- function(base_url, user, password) {
  # Защита от пустых настроек
  if (base_url == "") stop("❌ Ошибка: TTRSS_URL пустой! Проверь .env файл")
  
  body <- list(op = "login", user = user, password = password)
  
  tryCatch({
    resp <- request(base_url) %>%
      req_body_json(body) %>%
      req_perform()
    
    parsed <- resp %>% resp_body_json()
    
    if (parsed$status != 0) {
      stop(paste("TT-RSS Login Error:", parsed$content$error))
    }
    return(parsed$content$session_id)
    
  }, error = function(e) {
    stop(paste("Network Error:", e$message))
  })
}

ttrss_get_unread <- function(base_url, session_id, feed_id = -4, limit = 5) {
  body <- list(
    op = "getHeadlines",
    sid = session_id,
    feed_id = feed_id,
    view_mode = "unread",
    show_content = TRUE, 
    limit = limit
  )
  
  resp <- request(base_url) %>%
    req_body_json(body) %>%
    req_perform()
  
  parsed <- resp %>% resp_body_json()
  
  if (length(parsed$content) == 0) return(NULL)
  
  # Простая конвертация в таблицу
  news_df <- map_dfr(parsed$content, ~data.frame(
    id = as.character(.x$id),
    title = .x$title,
    content = .x$content, # Берем контент!
    link = .x$link,
    updated = .x$updated,
    stringsAsFactors = FALSE
  ))
  
  return(news_df)
}
#' Пометить новость как прочитанную
#' @param sid Session ID
#' @param article_id ID новости (число или строка)
ttrss_mark_read <- function(base_url, sid, article_id) {
  
  body <- list(
    op = "updateArticle",
    sid = sid,
    article_ids = as.character(article_id),
    mode = 0,   # 0 = установить в false (то есть убрать галочку Unread)
    field = 2   # 2 = поле "Unread" (Непрочитано)
  )
  
  # Отправляем запрос
  req <- request(base_url) %>%
    req_body_json(body) %>%
    req_perform()
  
  # Можно проверить статус, но обычно если 200 OK, то все хорошо
  return(TRUE)
}