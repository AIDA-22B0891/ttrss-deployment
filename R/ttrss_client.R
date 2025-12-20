#' Авторизация в TT-RSS
#'
#' Получает session_id для дальнейшей работы с API.
#'
#' @param base_url Адрес API (например, http://ip/api/)
#' @param user Логин
#' @param password Пароль
#' @return Строка с session_id
#' @export
ttrss_login <- function(base_url, user, password) {
  # Защита от пустых настроек
  if (is.null(base_url) || base_url == "") {
    stop("❌ Ошибка: TTRSS_URL пустой! Проверь .env файл")
  }
  
  body <- list(op = "login", user = user, password = password)
  
  tryCatch({
    # Используем httr2 для запроса
    resp <- httr2::request(base_url) |>
      httr2::req_body_json(body) |>
      httr2::req_perform()
    
    parsed <- httr2::resp_body_json(resp)
    
    # Проверяем статус внутри JSON (TT-RSS возвращает status != 0 при ошибке логина)
    if (!is.null(parsed$status) && parsed$status != 0) {
      err_msg <- if(!is.null(parsed$content$error)) parsed$content$error else "Unknown error"
      stop(paste("TT-RSS Login Error:", err_msg))
    }
    
    return(parsed$content$session_id)
    
  }, error = function(e) {
    stop(paste("Network or Login Error:", e$message))
  })
}

#' Получение непрочитанных новостей
#'
#' Скачивает заголовки и контент свежих статей.
#'
#' @param base_url Адрес API
#' @param sid Session ID
#' @param feed_id ID ленты (-4 = все ленты)
#' @param limit Количество статей (по умолчанию 5)
#' @return Data frame со статьями или NULL
#' @export
ttrss_get_unread <- function(base_url, sid, feed_id = -4, limit = 5) {
  body <- list(
    op = "getHeadlines",
    sid = sid,
    feed_id = feed_id,
    view_mode = "unread_first", # unread_first надежнее для сортировки
    show_content = TRUE,        # ВАЖНО: Запрашиваем текст статьи
    limit = limit,
    is_cat = FALSE
  )
  
  resp <- httr2::request(base_url) |>
    httr2::req_body_json(body) |>
    httr2::req_perform()
  
  parsed <- httr2::resp_body_json(resp)
  
  if (length(parsed$content) == 0) return(NULL)
  
  # Конвертация в таблицу
  # map_dfr собирает список списков в один датафрейм
  purrr::map_dfr(parsed$content, ~dplyr::tibble(
    id = as.integer(.x$id),
    title = .x$title,
    content = .x$content, # Теперь тут будет текст!
    link = .x$link,
    published = as.POSIXct(.x$updated, origin="1970-01-01")
  ))
}

#' Пометить новость как прочитанную
#'
#' Отправляет запрос updateArticle, чтобы убрать статус Unread.
#'
#' @param base_url Адрес API
#' @param sid Session ID
#' @param article_id ID новости (число или вектор чисел)
#' @return TRUE если успешно
#' @export
ttrss_mark_read <- function(base_url, sid, article_id) {
  # Превращаем ID в строку через запятую, если их несколько
  ids_str <- paste(as.character(article_id), collapse = ",")
  
  body <- list(
    op = "updateArticle",
    sid = sid,
    article_ids = ids_str,
    mode = 0,   # 0 = установить в false (убрать галочку Unread)
    field = 2   # 2 = поле "Unread"
  )
  
  httr2::request(base_url) |>
    httr2::req_body_json(body) |>
    httr2::req_perform()
  
  return(TRUE)
}