#' @export
clean_html_text <- function(html_string) {
  require(rvest)
  require(stringr)
  
  if (is.null(html_string) || is.na(html_string) || html_string == "") return("")
  
  # Оборачиваем в div, чтобы парсер понял структуру, и извлекаем текст
  # html_text2() сохраняет структуру абзацев лучше, чем html_text()
  txt <- read_html(paste0("<div>", html_string, "</div>")) |>
    html_text2()
  
  # Убираем лишние пробелы (оставляем только одиночные)
  str_squish(txt)
}