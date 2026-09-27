// Before publishing: no placeholder picture and no empty number may be left. Skipped in everyday runs; run it with
//   TANSU_RELEASE=1 node --test tests/*.test.mjs
import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { join, relative } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { icoPng, isPlaceholder } from '../tools/png.mjs';

const SITE = fileURLToPath(new URL('..', import.meta.url));
const skip = process.env.TANSU_RELEASE === '1' ? false : 'set TANSU_RELEASE=1 to check before publishing';

async function pngs(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await pngs(path)));
    else if (entry.name.endsWith('.png')) out.push(path);
  }
  return out;
}

test('every picture is real: no placeholder is left', { skip }, async () => {
  const left = [];
  for (const file of await pngs(join(SITE, 'assets'))) if (isPlaceholder(await readFile(file))) left.push(relative(SITE, file));
  if (isPlaceholder(icoPng(await readFile(join(SITE, 'favicon.ico'))))) left.push('favicon.ico');
  assert.deepEqual(left, [], 'placeholders still in place (see CAPTURES.md)');
});

test('every measured number is filled in', { skip }, async () => {
  const html = await readFile(join(SITE, 'index.html'), 'utf8');
  for (const [, slot, value] of html.matchAll(/data-slot="([^"]+)">([^<]*)</g)) assert.match(value, /^\d/, `${slot} is still "${value}"`);
});
