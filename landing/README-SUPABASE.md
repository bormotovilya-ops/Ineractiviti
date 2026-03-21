# Supabase URL и anon key

**Важно:** `SUPABASE_URL` должен **посимвольно** совпадать с **Project URL** в Supabase (**Settings → API**). Опечатка в ref (например `…dlf…` вместо `…df…`, `…hhng…` вместо `…hhnq…`) даёт чужой проект и **404** в Storage.

Источник правды — **`landing/.env`** (файл в `.gitignore`):

```env
SUPABASE_URL=https://ВАШ_REF.supabase.co
SUPABASE_ANON_KEY=eyJhbGci...   # JWT anon из Project Settings → API
```

После изменения `.env` обновите фронт:

```bash
node landing/scripts/sync-supabase-config.mjs
```

Скрипт перезаписывает:

- **`supabase-config.js`** — `export` для страниц с `import` (`app.html`, `scorm-player.html`, `index.html`)
- **`supabase-runtime.js`** — `window.__IA_SUPABASE_*` для **`cookie-consent.js`** (подключается **перед** `cookie-consent.js` на лендингах)

Шаблон без секретов: **`landing/.env.example`**.

### Storage (SCORM): 404 / `storage.download` не проходит

Выполните в SQL Editor: **`tech/supabase-storage-scorm-read.sql`** — политики `SELECT` на `storage.objects` для bucket `course-scorm` и `scorm` (роли `authenticated` и `anon`).

Убедитесь, что **Project URL** в `.env` совпадает с Dashboard (ошибка в ref → другой проект и пустой Storage).
