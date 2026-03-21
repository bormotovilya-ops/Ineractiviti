/**
 * Читает landing/.env (SUPABASE_URL, SUPABASE_ANON_KEY) и перезаписывает:
 *   landing/supabase-config.js   — import для type="module"
 *   landing/supabase-runtime.js  — window.__IA_* для cookie-consent.js
 *
 * Запуск из корня репозитория:
 *   node landing/scripts/sync-supabase-config.mjs
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const landingDir = path.join(__dirname, '..');
const envPath = path.join(landingDir, '.env');

function parseEnv(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const eq = t.indexOf('=');
    if (eq <= 0) continue;
    const k = t.slice(0, eq).trim();
    let v = t.slice(eq + 1).trim();
    if (
      (v.startsWith('"') && v.endsWith('"')) ||
      (v.startsWith("'") && v.endsWith("'"))
    ) {
      v = v.slice(1, -1);
    }
    out[k] = v;
  }
  return out;
}

if (!fs.existsSync(envPath)) {
  console.error('Не найден', envPath, '— скопируйте landing/.env.example → landing/.env');
  process.exit(1);
}

const env = parseEnv(fs.readFileSync(envPath, 'utf8'));
const url = env.SUPABASE_URL;
const key = env.SUPABASE_ANON_KEY;

if (!url || !key) {
  console.error('В landing/.env задайте SUPABASE_URL и SUPABASE_ANON_KEY (см. .env.example)');
  process.exit(1);
}

const esc = (s) => JSON.stringify(s);

const configJs = `/* Автогенерация: node landing/scripts/sync-supabase-config.mjs */
export const SUPABASE_URL = ${esc(url)};
export const SUPABASE_ANON_KEY = ${esc(key)};
`;

const runtimeJs = `/* Автогенерация: node landing/scripts/sync-supabase-config.mjs */
(function (w) {
  w.__IA_SUPABASE_URL = ${esc(url)};
  w.__IA_SUPABASE_ANON_KEY = ${esc(key)};
})(typeof globalThis !== 'undefined' ? globalThis : window);
`;

fs.writeFileSync(path.join(landingDir, 'supabase-config.js'), configJs, 'utf8');
fs.writeFileSync(path.join(landingDir, 'supabase-runtime.js'), runtimeJs, 'utf8');
console.log('Обновлены: landing/supabase-config.js, landing/supabase-runtime.js');
