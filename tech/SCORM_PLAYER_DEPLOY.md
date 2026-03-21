# Запуск SCORM и LMS API (один origin)

Контент SCORM в iframe вызывает `window.parent.API` (SCORM 1.2). Родительская страница и **все** файлы SCO в iframe должны быть **одного origin** (одинаковый хост, схема, порт), иначе браузер не даст доступа к `parent.API`.

Сессия Supabase Auth хранится **per-origin**. Если кабинет открыт на `https://ваш-сайт.ru`, а плеер на `https://xxx.supabase.co/storage/...`, **JWT не передаётся** — пользователь окажется «не залогинен» в плеере.

## Рабочие варианты

### A) Прокси контента на ваш домен (рекомендуется для продакшена)

1. Настройте reverse-proxy: `https://ваш-сайт.ru/scorm-files/*` → Supabase Storage (bucket с распакованным пакетом).
2. Деплойте `app.html` и `scorm-player.html` на **тот же** `ваш-сайт.ru`.
3. В плеере формируйте URL iframe на **ваш** прокси-путь, а не на `supabase.co/storage/...` (потребуется доработка `storagePublicObjectUrl` в `scorm-player.html` под ваш префикс).

Тогда и сессия, и LMS API на одном origin.

### B) Всё на хосте Supabase (один origin для плеера + пакетов)

1. Публичный bucket `ia-lms`: загрузите **`scorm-player.html`** и рядом с ним **`supabase-config.js`** (из папки `landing/` после `node landing/scripts/sync-supabase-config.mjs` — плеер импортирует ключ из этого файла).
2. Пакеты уже в `course-scorm` на том же `*.supabase.co`.
3. В `app.html`: `SCORM_PLAYER_USE_SUPABASE_STORAGE = true`, верный `SCORM_PLAYER_BUCKET`.
4. Кабинет (`app.html`, `index.html`) тоже должен открываться **с того же** `https://PROJECT.supabase.co/storage/v1/object/public/...`, чтобы сессия совпадала с плеером. Параметр `cabinet` в ссылке запуска ведёт на вашу копию `index.html#form` на этом же хосте.

### C) Локально (`SCORM_PLAYER_USE_SUPABASE_STORAGE = false`)

Плеер рядом с `app.html` — **вход работает**, но iframe с `supabase.co/storage/...` остаётся **другим origin** → LMS API, как правило, **не работает**, пока не поднят прокси (см. вариант A).

## Политики Storage

Нужен **public read** (или политики на чтение) для bucket с распакованным SCORM и при необходимости для bucket с плеером.
