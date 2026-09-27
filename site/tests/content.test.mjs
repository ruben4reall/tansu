// Static rules for everything in site/: the owner's copy rules, CSP-safe markup, links, pictures and files that
// exist, and a .vercelignore that keeps every tool out of production.
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, extname, join, relative, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { pngSize } from '../tools/png.mjs';

const SITE = fileURLToPath(new URL('..', import.meta.url));
const REPO_ROOT = resolve(SITE, '..');
const TEXT = new Set(['.html', '.css', '.js', '.mjs', '.svg', '.json', '.txt', '.xml', '.md', '.sh']);
const HOST = 'gettansu.vercel.app';
const REPO = 'https://github.com/ruben4reall/tansu';
const DOWNLOAD = `${REPO}/releases/latest/download/Tansu.dmg`;
const EM_DASH = String.fromCharCode(0x2014);
const APPLE_LOGO = String.fromCharCode(0xf8ff); // the private-use glyph Apple fonts draw as their logo
const PAGES = ['index.html', '404.html'];
// Smart Sort's drawers, in the app's order, each drawn with its own glyph (symbol d-<key> in index.html).
const KINDS = [
  ['Files & Cloud', 'files'], ['Security & VPN', 'security'], ['Messages', 'messages'], ['AI', 'ai'], ['Developer', 'developer'],
  ['Music & Video', 'media'], ['Displays & Devices', 'devices'], ['System', 'system'], ['Productivity', 'productivity'],
  ['Utilities', 'utilities'], ['Design', 'design'], ['Games', 'games'], ['Other', 'other'],
];

async function list(dir) {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (['.shots', 'node_modules', '.vercel'].includes(entry.name)) continue;
    const path = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await list(path)));
    else out.push(path);
  }
  return out;
}

const read = (path) => readFile(join(SITE, path), 'utf8');
const html = await read('index.html');
const visibleText = (page) => page.replace(/<head>[\s\S]*?<\/head>/, '').replace(/<!--[\s\S]*?-->/g, '').replace(/<[^>]+>/g, ' ')
  .replace(/&amp;/g, '&').replace(/&rsquo;/g, "'").replace(/&ldquo;|&rdquo;/g, '"').replace(/\s+/g, ' ');
const visible = visibleText(html);

test('no em dash anywhere in site/, tools and tests included, nor in the brand tokens', async () => {
  const files = [...(await list(SITE)), ...['brand/tokens/tokens.json', 'brand/tokens/tokens.css', 'brand/scripts/tokens/build.mjs'].map((f) => join(REPO_ROOT, f))];
  for (const file of files) {
    if (!TEXT.has(extname(file)) || !existsSync(file)) continue;
    assert.ok(!(await readFile(file, 'utf8')).includes(EM_DASH), `em dash in ${relative(REPO_ROOT, file)}`);
  }
});

test('markup is CSP-safe: no inline script, style or handler', async () => {
  for (const file of (await list(SITE)).filter((f) => f.endsWith('.html'))) {
    const text = await readFile(file, 'utf8');
    const name = relative(SITE, file);
    assert.doesNotMatch(text, /<script(?![^>]*\bsrc=)[^>]*>/i, `inline script in ${name}`);
    assert.doesNotMatch(text, /<style[\s>]/i, `<style> in ${name}`);
    assert.doesNotMatch(text, /\sstyle\s*=/i, `style attribute in ${name}`);
    assert.doesNotMatch(text, /\son[a-z]+\s*=/i, `inline handler in ${name}`);
    assert.doesNotMatch(text, /javascript:/i, `javascript: URL in ${name}`);
  }
});

test('the required words are on the page', () => {
  for (const words of [
    'Your menu bar, in drawers.',
    'A place for every icon.',
    'A tansu is a Japanese chest of drawers',
    'Made in Switzerland',
    'Tansu is not affiliated with Apple.',
    'Bartender, Ice, Thaw and Hidden Bar belong to their authors.',
    'brew install --cask ruben4reall/tap/tansu',
    'Free and open source', 'Version 1.0', 'macOS 26 and 27', 'One permission',
  ]) assert.ok(visible.includes(words), `missing: ${words}`);
  assert.ok(html.split(DOWNLOAD).length - 1 >= 3, 'the download link appears in the nav, the hero and the download section');
});

test('the voice: no exclamation mark in what visitors read', async () => {
  for (const page of PAGES) assert.doesNotMatch(visibleText(await read(page)), /!/, `exclamation mark in ${page}`);
});

test('no emoji on the pages: drawers show as icons', async () => {
  for (const page of PAGES) {
    const found = [...visibleText(await read(page)).matchAll(/\p{Extended_Pictographic}/gu)].map(([char]) => `${char} U+${char.codePointAt(0).toString(16)}`);
    assert.deepEqual(found, [], `emoji in ${page}`);
  }
});

test('emoji and letters are mentioned once, calmly, as an option', () => {
  assert.equal((visible.match(/\bemoji\b/gi) ?? []).length, 1);
  assert.match(visible, /A drawer can also show an emoji or a few letters, if you prefer\./);
  assert.match(visible, /one icon each/);
});

test('Smart Sort shows every kind of drawer, each with its own glyph', () => {
  const grid = html.match(/<ul class="kinds[^"]*"[^>]*>([\s\S]*?)<\/ul>/)[1];
  const kinds = [...grid.matchAll(/<use href="#d-([a-z]+)"\/><\/svg><\/span><b>([^<]+)<\/b>/g)].map(([, key, name]) => [name.replace('&amp;', '&'), key]);
  assert.deepEqual(kinds, KINDS);
  for (const [, key] of KINDS) assert.match(html, new RegExp(`<symbol id="d-${key}" viewBox="0 0 24 24">`));
});

test('the sections of the outline, in order, each reachable from its id', () => {
  const ids = [...html.matchAll(/<section[^>]*\bid="([^"]+)"/g)].map(([, id]) => id);
  assert.deepEqual(ids, ['top', 'how', 'smart-sort', 'drawers', 'automation', 'settings', 'engines', 'compare', 'privacy', 'open-source', 'faq', 'download']);
  const nav = html.match(/<div class="nav-links">([\s\S]*?)<\/div>/)[1];
  assert.deepEqual([...nav.matchAll(/href="#([^"]+)"/g)].map(([, id]) => id), ['how', 'smart-sort', 'engines', 'privacy', 'faq']);
});

test('every picture has alt text and dimensions', async () => {
  for (const page of PAGES) {
    for (const tag of (await read(page)).match(/<img\b[^>]*>/g) ?? []) {
      assert.match(tag, /\balt="/, tag);
      assert.match(tag, /\bwidth="\d+"/, tag);
      assert.match(tag, /\bheight="\d+"/, tag);
    }
  }
});

test('each capture is the size its markup says, and its @2x twin exactly twice that', async () => {
  for (const tag of html.match(/<img\b[^>]*>/g) ?? []) {
    const src = tag.match(/\bsrc="([^"]+)"/)[1];
    const width = Number(tag.match(/\bwidth="(\d+)"/)[1]);
    const height = Number(tag.match(/\bheight="(\d+)"/)[1]);
    if (!src.endsWith('.png')) continue;
    assert.deepEqual(pngSize(await readFile(join(SITE, src))), { width, height }, `${src} at 1x`);
    const twin = tag.match(/\bsrcset="([^"\s]+) 2x"/)?.[1];
    assert.ok(twin, `${src} has an @2x twin in srcset`);
    assert.deepEqual(pngSize(await readFile(join(SITE, twin))), { width: width * 2, height: height * 2 }, `${twin}`);
  }
});

test('links stay on the page or go to the project on GitHub', async () => {
  for (const page of PAGES) {
    for (const [, href] of (await read(page)).matchAll(/href="([^"]+)"/g)) {
      const ok = href.startsWith('#') || !/^[a-z]+:/i.test(href) || href === REPO || href.startsWith(`${REPO}/`) || href === `https://${HOST}/`;
      assert.ok(ok, `unexpected link in ${page}: ${href}`);
    }
  }
});

test('in-page links land on an element', () => {
  for (const [, id] of html.matchAll(/href="#([^"]+)"/g)) assert.match(html, new RegExp(`id="${id}"`), `no element with id="${id}"`);
  for (const [, id] of html.matchAll(/<use href="#([^"]+)"/g)) assert.match(html, new RegExp(`<symbol id="${id}"`), `no glyph ${id}`);
});

test('one production domain everywhere', async () => {
  const hosts = new Set();
  for (const file of [...PAGES, 'robots.txt', 'sitemap.xml', 'appcast.xml', 'js/beacon.js']) {
    for (const [, host] of (await read(file)).matchAll(/https:\/\/([a-z0-9.-]+\.vercel\.app)/g)) hosts.add(host);
  }
  hosts.delete('ruben-analytics.vercel.app');
  assert.deepEqual([...hosts], [HOST]);
  assert.match(html, new RegExp(`<link rel="canonical" href="https://${HOST}/">`));
});

test('no SF Pro file, no Apple logo, Inter as the only webfont', async () => {
  for (const file of await list(SITE)) {
    const name = relative(SITE, file);
    assert.doesNotMatch(name, /sf-?pro|sanfrancisco/i, name);
    if (/\.(woff2?|ttf|otf)$/.test(name)) assert.match(name, /^assets\/fonts\/inter-\d{3}\.woff2$/, name);
    if (TEXT.has(extname(file))) assert.ok(!(await readFile(file, 'utf8')).includes(APPLE_LOGO), `Apple logo character in ${name}`);
  }
  assert.ok(existsSync(join(SITE, 'assets/fonts/LICENSE-Inter.txt')), 'Inter ships with its license');
  const css = await read('css/site.css');
  assert.deepEqual([...css.matchAll(/font-family:\s*'([^']+)';/g)].map(([, family]) => family), ['Inter', 'Inter']);
  assert.match(css, /--font: var\(--tansu-font-sans\);/);
  assert.match(await read('css/tokens.css'), /--tansu-font-sans: -apple-system, BlinkMacSystemFont, "Inter", system-ui, sans-serif;/);
});

test('every file the pages and their styles reference exists', async () => {
  const refs = [];
  for (const page of PAGES) {
    const text = await read(page);
    refs.push(...[...text.matchAll(/(?:src|href)="([^"#:]+)"/g)].map(([, ref]) => ref).filter((ref) => ref !== '/'));
    for (const [, set] of text.matchAll(/srcset="([^"]+)"/g)) refs.push(...set.split(',').map((part) => part.trim().split(/\s+/)[0]));
  }
  for (const file of ['css/site.css', 'css/menubar.css']) {
    for (const [, ref] of (await read(file)).matchAll(/url\(['"]?([^'")]+)['"]?\)/g)) refs.push(join(dirname(file), ref));
  }
  for (const ref of refs) assert.ok(existsSync(resolve(SITE, ref.replace(/^\//, ''))), `missing file: ${ref}`);
});

test('tools, tests and notes never ship: .vercelignore covers everything that is not the site', async () => {
  const ignored = new Set((await read('.vercelignore')).split('\n').map((line) => line.trim()).filter(Boolean));
  for (const path of ['/tools/', '/tests/', '/.shots/', '/package.json', '/CAPTURES.md', '/.gitignore', '/artifact-check.html', '/artifact-check.css']) {
    assert.ok(ignored.has(path), `.vercelignore lacks ${path}`);
  }
  const served = new Set(['index.html', '404.html', 'favicon.ico', 'appcast.xml', 'robots.txt', 'sitemap.xml', 'vercel.json', '.vercelignore', 'css', 'js', 'assets']);
  for (const entry of await readdir(SITE, { withFileTypes: true })) {
    if (['.vercel', '.shots', '.DS_Store'].includes(entry.name) || served.has(entry.name)) continue;
    assert.ok(ignored.has(`/${entry.name}${entry.isDirectory() ? '/' : ''}`), `${entry.name} would be published: add it to .vercelignore`);
  }
});

test('CAPTURES.md lists every capture of the app on the page, and every one it lists exists', async () => {
  const notes = await read('CAPTURES.md');
  const listed = new Set([...notes.matchAll(/`(assets\/[a-z]+\/[a-z0-9-]+\.(?:png|svg))`/g)].map(([, path]) => path));
  const shown = new Set([...html.matchAll(/src="(assets\/app\/[^"]+)"/g)].map(([, path]) => path));
  for (const path of shown) assert.ok(listed.has(path), `CAPTURES.md does not list ${path}`);
  for (const path of listed) if (!path.endsWith('wordmark.svg')) assert.ok(existsSync(join(SITE, path)), `${path} is listed but missing`);
  for (const [, slot] of html.matchAll(/data-slot="([^"]+)"/g)) assert.ok(notes.includes(`data-slot="${slot}"`), `CAPTURES.md does not explain the slot ${slot}`);
});

test('the comparison is dated and says what it could not verify', () => {
  const table = html.match(/<table class="compare">[\s\S]*?<\/table>/)[0];
  assert.match(visible, /As of September 2026/);
  assert.match(table, /Not verified/);
  const header = [...table.match(/<thead>[\s\S]*?<\/thead>/)[0].matchAll(/<th\b/g)].length;
  assert.equal(header, 7);
  for (const row of table.match(/<tbody>[\s\S]*?<\/tbody>/)[0].match(/<tr>[\s\S]*?<\/tr>/g)) {
    assert.equal([...row.matchAll(/<t[hd]\b/g)].length, header, row.slice(0, 80));
  }
  const rows = [...table.matchAll(/<th scope="row">([^<]+)<\/th>/g)].map(([, name]) => name);
  assert.deepEqual(rows, ['Price', 'License', 'macOS 26 Tahoe', 'macOS 27 Golden Gate', 'Groups as one icon', 'Automatic sorting', 'Profiles', 'Triggers', 'Search', 'Space between icons', 'Menu bar shapes', 'Screen Recording']);
});

test('the FAQ answers eight to twelve questions', () => {
  const count = (html.match(/<summary>/g) ?? []).length;
  assert.ok(count >= 8 && count <= 12, `${count} questions`);
});

test('macOS 27 is called beta, with what it hides, wherever it is described', () => {
  assert.match(visible, /macOS 27 Golden Gate Beta/);
  assert.match(visible, /Focus and the camera and microphone indicators/);
  assert.match(visible, /Support for macOS 27 is in beta/);
});

test('the appcast is a valid, empty Sparkle feed', async () => {
  const feed = await read('appcast.xml');
  assert.match(feed, /^<\?xml version="1\.0" encoding="utf-8"\?>/);
  assert.match(feed, /<rss version="2\.0" xmlns:sparkle="http:\/\/www\.andymatuschak\.org\/xml-namespaces\/sparkle">/);
  assert.match(feed, /<channel>\s*<title>Tansu<\/title>\s*<link>https:\/\/gettansu\.vercel\.app\/<\/link>\s*<description>[^<]+<\/description>/);
  assert.doesNotMatch(feed, /<item>/);
});
