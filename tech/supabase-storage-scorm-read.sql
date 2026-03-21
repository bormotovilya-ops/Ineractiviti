-- Политики Storage: чтение SCORM для authenticated (нужно для storage.download() и createSignedUrl в плеере)
-- и для anon (публичный доступ по ключу).
-- Выполните в Supabase SQL Editor, если в консоли плеера:
--   [SCORM] storage.download не прошёл...
-- или index.html отдаёт 400/403 при том, что файл в bucket есть.
--
-- Дополнительно в Dashboard → Storage → bucket course-scorm (и scorm):
-- включите "Public bucket", если нужны прямые URL /storage/v1/object/public/... без подписи.

-- Включите RLS на объектах (обычно уже включён)
-- alter table storage.objects enable row level security;

-- ---------- course-scorm ----------
drop policy if exists "course_scorm_authenticated_select" on storage.objects;
create policy "course_scorm_authenticated_select"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'course-scorm');

drop policy if exists "course_scorm_anon_select" on storage.objects;
create policy "course_scorm_anon_select"
  on storage.objects
  for select
  to anon
  using (bucket_id = 'course-scorm');

-- ---------- scorm (второй bucket из uploadCourseScormPackage) ----------
drop policy if exists "scorm_bucket_authenticated_select" on storage.objects;
create policy "scorm_bucket_authenticated_select"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'scorm');

drop policy if exists "scorm_bucket_anon_select" on storage.objects;
create policy "scorm_bucket_anon_select"
  on storage.objects
  for select
  to anon
  using (bucket_id = 'scorm');

-- Примечание: если политики уже есть в Dashboard, возможны дубликаты по смыслу —
-- удалите старые или переименуйте эти. Публичные политики нужны для прямого открытия
-- /object/public/... без JWT; authenticated — для вызова Storage API с сессией.
