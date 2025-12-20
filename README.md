# Развёртывание и настройка TT-RSS (Tiny Tiny RSS)
Проект по развёртыванию полнофункциональной системы агрегации RSS-лент с использованием TT-RSS, Docker, PostgreSQL и Nginx.

# Цель проекта
Создать рабочую среду для централизованного сбора новостных материалов с поддержкой автоматической загрузки RSS-источников и доступа через API.

# Выполненные задачи

## 1.1. Развернуть TT-RSS в Docker

1) Создана Docker-инфраструктура с использованием docker-compose.yml
2) Использован официальный образ wangqiru/ttrss:latest
3) Наcтроены volumes для сохранения данных и иконок лент
4) Реализован автоматический перезапуск контейнеров
5) Настроить конфигурацию Nginx для входа через браузер

### Развернутые контейнеры TT-RSS на удаленном сервере Ubuntu:

![Развернутые контейнеры TT-RSS на удаленном сервере Ubuntu](images/docker.png)

### Добавленная конфигурация ttrsss для Nginx:

![Добавленная конфигурация ttrsss для Nginx](images/nginx.png)

### Данная конфигурация в виде кода:

```
server {
    listen 80;
    server_name $SERVER_IP;

    # Основное приложение
    location / {
        proxy_pass http://127.0.0.1:8280;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
    }

    # API
    location /api/ {
        proxy_pass http://127.0.0.1:8280/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
```

Данный файл конфигурации можно найти по имени nginx-config

## 1.2. Развернуть базу данных PostgreSQL

1) Развернута PostgreSQL 13 в контейнере
2) Настроены пользователь, пароль и база данных для TT-RSS
3) Реализовано постоянное хранение данных через Docker volumes
4) Настроена сеть для связи между контейнерами

Полную схему можно посмотреть в репозитории database-schema/full_schema.sql
   
## 1.3. Настроить автоматическое обновление новостей

1) Использован встроенный в образ TT-RSS механизм обновления
2) Настроен ttrss_updater для регулярной загрузки новостей
3) Проверена работоспособность автоматического обновления лент

### Настроенные ttrss-updater:

![Настроенные ttrss-updater](images/systemd.png)

### Код для ttrss-updater.timer:

```
[Unit]
Description=Update TT-RSS feeds every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Persistent=true
b
[Install]
WantedBy=timers.target
```

### Код для ttrss-updater.service:

```
[Unit]
Description=TT-RSS Updater
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/docker exec ttrss_app php /var/www/update.php --daemon
User=root
```

Данные файлы конфигруации можно найти в репозитории ttrss-update/ttrss-update.service и ttrss-update/ttrss-update.timer соотвественно

## 1.4. Добавить и настроить RSS-источники

1) Добавлены следующие рабочие RSS-источники: Habr — все публикации: https://habr.com/ru/rss/all/all/
2) Подтверждена регулярная загрузка новостей из всех источников

### Интерфейс TT-RSS в браузере:

![Интерфейс TT-RSS в браузере](images/ttrss.png)

## 1.5. Проверить API-доступ

Успешно протестированы все ключевые методы API:

1) login: Получение токена сессии
2) getFeeds: Получение списка RSS-лент
3) getHeadlines: Получение заголовков статей
4) getArticle: Получение полного текста статьи
5) search: Поиск по статьям

### Пример получения токена:

```
curl -X POST http://194.87.118.106/api/ \
  -H "Content-Type: application/json" \
  -d '{"op": "login", "user": "admin", "password": "password"}'
```

### Получение списка лент (с токеном, полученным в предыдущем примере):

```
curl -X POST http://194.87.118.106/api/ \
  -H "Content-Type: application/json" \
  -d '{"op": "getFeeds", "sid": "ваш_токен", "cat_id": -3}'
```

На данном этапе настройка и тестирование связностей с Docker завершается
---

## MCP server (TT-RSS API wrapper)

В репозитории есть MCP-сервер, который предоставляет доступ к TT-RSS JSON API через Model Context Protocol (MCP).

### Что умеет

MCP поднимает 3 tool’а:

* `get_active_functions` — список доступных функций MCP и текущие дефолты конфигурации
* `get_login` — логин в TT-RSS API (op=`login`) и получение `sid` (TT-RSS session id)
* `search` — поиск по статьям (использует TT-RSS API, обычно через `getHeadlines` + `search=...`)

### Важно: два разных session id

В системе есть **два независимых идентификатора сессии**:

1. **MCP session id** (заголовок `mcp-session-id`)
   Возвращается в HTTP-ответе MCP на запрос `initialize`. Его нужно передавать в заголовке `Mcp-Session-Id` для дальнейших MCP-вызовов (`tools/list`, `tools/call`).

2. **TT-RSS sid** (поле `content.session_id` в ответе `op=login`)
   Используется внутри TT-RSS API и передаётся **в теле JSON** как `"sid": "..."` для `getFeeds/getHeadlines/...`.

Не путать. Ошибка вида `Bad Request: No valid session ID provided` почти всегда означает, что в `Mcp-Session-Id` передали не MCP session id.

---

## Запуск через docker-compose

MCP запускается отдельным контейнером и ходит в TT-RSS API внутри docker-сети.

Запуск:

```bash
docker compose up -d --build
docker compose ps
docker compose logs --tail 100 mcp
```

Endpoint MCP:

* `http://<HOST>:9100/mcp`

---

## Проверка работоспособности MCP (curl)

### 1) initialize (получить MCP session id)

```bash
curl -i -N \
  -X POST http://127.0.0.1:9100/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc":"2.0",
    "id":1,
    "method":"initialize",
    "params":{
      "protocolVersion":"2025-06-18",
      "capabilities":{},
      "clientInfo":{"name":"curl","version":"0"}
    }
  }'
```

В ответе будет заголовок:

```
mcp-session-id: <SESSION_ID>
```

### 2) tools/list (нужно передать MCP session id)

```bash
curl -i -N \
  -X POST http://127.0.0.1:9100/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: <SESSION_ID>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

Ожидается список tools (`get_active_functions`, `get_login`, `search`).

### 3) tools/call (пример: get_active_functions)

```bash
curl -s -N \
  -X POST http://127.0.0.1:9100/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: <SESSION_ID>" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_active_functions","arguments":{}}}'
```

### 3) tools/call (пример: search)
```bash
root@6207783-qt34447:/opt/ttrss# curl -s -N \
  -X POST http://127.0.0.1:9100/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: 5010f5ef7e854181889cb4743d71751e" \
  -d '{
    "jsonrpc":"2.0",
    "id":10,
    "method":"tools/call",
    "params":{
      "name":"search",
      "arguments":{"query":"habr","limit":5}
    }
  }'
```

---

## Типовые проблемы

### 1) `Invalid Host header` / `421 Misdirected Request`

Причина: защита MCP от DNS rebinding режет запросы с “неразрешённым” `Host`.
Решение: добавить публичный IP/домен в `MCP_ALLOWED_HOSTS` и `MCP_ALLOWED_ORIGINS` (см. docker-compose пример выше).

### 2) `406 Not Acceptable: Client must accept text/event-stream`

Причина: запрос к `/mcp` без корректного `Accept`.
Решение: для POST использовать `Accept: application/json, text/event-stream` (см. примеры выше).

### 3) `Bad Request: No valid session ID provided`

Причина: не передали или неправильно передали **MCP session id** в заголовке `Mcp-Session-Id`.
Решение: сначала выполнить `initialize`, взять `mcp-session-id` из заголовка и подставить его в следующие запросы.

---

Также закрепляю удобный способ получения ttrss session_id
```bash
SID=$(curl -s -X POST http://194.87.118.106/api/ \
  -H "Content-Type: application/json" \
  -d '{"op":"login","user":"admin","password":"password"}' | \
  python3 -c 'import sys,json; print(json.load(sys.stdin)["content"]["session_id"])')

echo "$SID"
```
---

