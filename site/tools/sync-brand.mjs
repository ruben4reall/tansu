// Brings the brand's tokens into the site, the Pli way: brand/tokens/tokens.css (built from tokens.json by
// brand/scripts/tokens/build.mjs) is copied to css/tokens.css under a one-line header.
// Usage: node tools/sync-brand.mjs [--check] [--from <repo root>]   (default: the repository holding this site)
// --check exits 1 when css/tokens.css no longer matches the brand's file.
import { readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

export const SITE_DIR = resolve(fileURLToPath(new URL('..', import.meta.url)));
export const HEADER = '/* Copied from brand/tokens/tokens.css by tools/sync-brand.mjs. Do not edit: change brand/tokens/tokens.json and run both scripts. */\n\n';

/** css/tokens.css for the brand's tokens.css. */
export function renderSiteTokens(brandCss) {
  return HEADER + brandCss.trimEnd() + '\n';
}

/** Custom properties a CSS file declares, name to value. */
export function declaredTokens(css) {
  const out = {};
  for (const match of css.matchAll(/(--[\w-]+)\s*:\s*([^;}]+)/g)) out[match[1]] = match[2].trim();
  return out;
}

export async function syncBrand(repoRoot, { check = false } = {}) {
  const brandCss = await readFile(join(repoRoot, 'brand/tokens/tokens.css'), 'utf8');
  const target = join(SITE_DIR, 'css/tokens.css');
  const wanted = renderSiteTokens(brandCss);
  if (check) {
    const current = await readFile(target, 'utf8').catch(() => '');
    return current === wanted ? 'css/tokens.css matches brand/tokens/tokens.css' : null;
  }
  await writeFile(target, wanted);
  return `css/tokens.css: copied from ${join(repoRoot, 'brand/tokens/tokens.css')}`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: { check: { type: 'boolean' }, from: { type: 'string', default: resolve(SITE_DIR, '..') } } });
  const report = await syncBrand(resolve(values.from), { check: values.check });
  if (report === null) {
    console.error('css/tokens.css is out of date: run node tools/sync-brand.mjs');
    process.exit(1);
  }
  console.log(report);
}
