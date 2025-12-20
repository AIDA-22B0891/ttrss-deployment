#' Очистка HTML текста
#'
#' Удаляет теги, скрипты, стили и лишние пробелы из текста новости.
#'
#' @param html_string Сырой HTML код (строка)
#' @return Чистый текст
#' @export
clean_html_text <- function(html_string) {
  # Проверка на пустоту
  if (is.null(html_string) || is.na(html_string) || html_string == "") {
    return("")
  }
  
  # 1. Парсим HTML
  # Оборачиваем в div, чтобы rvest корректно съел фрагмент, а не полную страницу
  html_node <- rvest::read_html(paste0("<div>", html_string, "</div>"))
  
  # 2. Удаляем мусор (скрипты и стили), который не является текстом новости
  # Это сэкономит токены для YandexGPT и уберет технический код
  xml2::xml_find_all(html_node, ".//script|.//style") |> xml2::xml_remove()
  
  # 3. Извлекаем умный текст
  # html_text2 превращает <br> и <p> в переносы строк
  txt <- rvest::html_text2(html_node)
  
  # 4. Схлопываем лишние пробелы (оставляем только одиночные)
  stringr::str_squish(txt)
}