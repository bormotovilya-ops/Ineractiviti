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

### Заявки с лендинга (`index.html`, слайд «Заявка»)

В SQL Editor выполните **`tech/supabase-landing-project-requests.sql`**: таблица `landing_project_requests` и политика `INSERT` для роли `anon`. Без этого отправка формы вернёт ошибку.

### Панель администратора платформы (`app.html`)

Выполните **`tech/supabase-platform-admin.sql`**: таблицы `platform_admins` и `platform_settings`, политика `SELECT` на `landing_project_requests` для пользователей из `platform_admins`.

Первого администратора добавьте в SQL Editor (подставьте UUID из **Authentication → Users**):

```sql
insert into public.platform_admins (user_id) values ('ВАШ_UUID');
```

После этого в кабинете появится раздел «Платформа»: заявки с формы `#form` и глобальные заметки в `platform_settings`.
