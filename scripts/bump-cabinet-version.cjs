/**
 * Обновляет версию кабинета (landing/app-version.json).
 * Использование: node scripts/bump-cabinet-version.cjs minor
 *              node scripts/bump-cabinet-version.cjs major
 *
 * minor — мелкие изменения (второй разряд: 0.2 → 0.3)
 * major — крупные (первый разряд: 0.3 → 1.0, второй сбрасывается в 0)
 */
const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, '..', 'landing', 'app-version.json');
const mode = (process.argv[2] || 'minor').toLowerCase();

let data;
try {
  data = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (e) {
  console.error('Не удалось прочитать', file, e.message);
  process.exit(1);
}

let major = Number(data.major);
let minor = Number(data.minor);
if (!Number.isFinite(major)) major = 0;
if (!Number.isFinite(minor)) minor = 0;

if (mode === 'major') {
  major += 1;
  minor = 0;
} else if (mode === 'minor') {
  minor += 1;
} else {
  console.error('Укажите режим: minor или major');
  process.exit(1);
}

const next = { major, minor };
fs.writeFileSync(file, JSON.stringify(next, null, 2) + '\n', 'utf8');
console.log(`landing/app-version.json → ${major}.${minor}`);
