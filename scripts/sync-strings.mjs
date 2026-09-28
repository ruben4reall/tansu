// Writes the String Catalog from Design/Strings*.swift: every `String(localized: "…"` key, sorted, English source.
// Translations already in the catalog are kept for every key that still exists.
//   node scripts/sync-strings.mjs
// StringCatalogTests fails when the two disagree, so run this after adding or changing a string.
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = new URL('../Packages/TiroirKit/Sources/TiroirUI/', import.meta.url);
const design = new URL('Design/', root);
const catalogURL = new URL('Resources/Localizable.xcstrings', root);

const keys = new Set();
for (const name of readdirSync(design).filter((file) => /^Strings.*\.swift$/.test(file)).sort()) {
  const source = readFileSync(new URL(name, design), 'utf8');
  for (const match of source.matchAll(/String\(localized: "((?:[^"\\]|\\.)*)"/g)) {
    keys.add(match[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\'));
  }
}

const previous = existsSync(catalogURL) ? JSON.parse(readFileSync(catalogURL, 'utf8')).strings ?? {} : {};
const strings = {};
for (const key of [...keys].sort()) strings[key] = previous[key] ?? {};
const catalog = { sourceLanguage: 'en', strings, version: '1.0' };
writeFileSync(fileURLToPath(catalogURL), JSON.stringify(catalog, null, 2) + '\n');
console.log(`${keys.size} strings`);
