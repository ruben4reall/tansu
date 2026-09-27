// Writes the String Catalog from Strings.swift: every `String(localized: "…"` key, sorted, English source.
//   node scripts/sync-strings.mjs
// StringCatalogTests fails when the two disagree, so run this after adding or changing a string.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = new URL('../Packages/TansuKit/Sources/TansuUI/', import.meta.url);
const source = readFileSync(new URL('Design/Strings.swift', root), 'utf8');
const keys = new Set();
for (const match of source.matchAll(/String\(localized: "((?:[^"\\]|\\.)*)"/g)) {
  keys.add(match[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\'));
}
const strings = {};
for (const key of [...keys].sort()) strings[key] = {};
const catalog = { sourceLanguage: 'en', strings, version: '1.0' };
writeFileSync(fileURLToPath(new URL('Resources/Localizable.xcstrings', root)), JSON.stringify(catalog, null, 2) + '\n');
console.log(`${keys.size} strings`);
