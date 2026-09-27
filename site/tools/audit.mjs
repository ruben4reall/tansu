// Checks the website the way a visitor meets it, at four sizes, under the production headers of vercel.json:
// console errors, CSP violations, failed requests, pictures that did not load or do not match their markup,
// horizontal overflow, text that overflows its box, and the contrast of every text (4.5:1 at least). Then it checks
// that reduced motion shows the hero's final state, still. Screenshots of each hero state and of every section go
// to site/.shots/ (ignored by git; delete it when done).
// Usage: node tools/audit.mjs [--only desktop|laptop|tablet|phone] [--no-shots] [--path /page] [--wrapped] [--url <site>]
// --wrapped checks the page inside the skeleton a preview host puts around it (light colours on body, img max-width);
//   the skeleton's styles are a file of their own, since the CSP forbids inline styles.
// --url https://gettansu.vercel.app checks the published site instead of site/ served locally.
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { setTimeout as sleep } from 'node:timers/promises';
import { SIZES, launchChrome } from './cdp.mjs';
import { SITE_DIR, startServer } from './serve.mjs';

const SECTIONS = ['top', 'how', 'smart-sort', 'drawers', 'automation', 'settings', 'engines', 'compare', 'privacy', 'open-source', 'faq', 'download'];
const HERO_STATES = ['crowded', 'sorting', 'open'];

const { values } = parseArgs({ options: { only: { type: 'string' }, 'no-shots': { type: 'boolean' }, path: { type: 'string', default: '/' }, wrapped: { type: 'boolean' }, url: { type: 'string' } } });
const WRAPPED = join(SITE_DIR, 'artifact-check.html');
const WRAPPED_CSS = join(SITE_DIR, 'artifact-check.css');
if (values.wrapped) {
  const skeleton = '<!doctype html><html><head><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1"><link rel=stylesheet href="artifact-check.css"></head><body>\n';
  await writeFile(WRAPPED_CSS, ':root{color-scheme:light}body{margin:0;padding:0;font:14px -apple-system,sans-serif;background:#faf9f5;color:#141413}img{max-width:100%}\n');
  await writeFile(WRAPPED, skeleton + (await readFile(join(SITE_DIR, 'index.html'), 'utf8')) + '\n</body></html>');
  values.path = '/artifact-check.html';
}
const SHOTS = join(SITE_DIR, '.shots');
if (!values['no-shots']) { await rm(SHOTS, { recursive: true, force: true }); await mkdir(SHOTS, { recursive: true }); }

// Everything is shown before measuring: sections that ease in on scroll, the answers of the FAQ, lazy pictures.
const PREPARE = `(async () => {
  document.documentElement.classList.remove('reveal-on');
  document.querySelectorAll('.reveal').forEach((el) => el.classList.add('in'));
  document.querySelectorAll('details').forEach((d) => { d.open = true; });
  await Promise.all([...document.images].map((img) => { img.loading = 'eager'; return img.decode().catch(() => {}); }));
  return true;
})()`;
const RESTORE = `document.querySelectorAll('details').forEach((d) => { d.open = false; }); true`;

// Everything measured inside the page: returns a list of problems.
const INSPECT = `(() => {
  const out = [];
  const doc = document.documentElement;
  if (doc.scrollWidth > innerWidth + 1) out.push('page scrolls sideways: ' + doc.scrollWidth + ' > ' + innerWidth);
  for (const img of document.images) {
    const src = img.getAttribute('src');
    if (!img.complete || img.naturalWidth === 0) { out.push('picture did not load: ' + src); continue; }
    const w = Number(img.getAttribute('width')), h = Number(img.getAttribute('height'));
    if (w && h && (img.naturalWidth !== w || img.naturalHeight !== h)) out.push('picture is ' + img.naturalWidth + 'x' + img.naturalHeight + ' (at ' + devicePixelRatio + 'x), markup says ' + w + 'x' + h + ': ' + img.currentSrc.split('/').pop());
  }
  const wide = [];
  for (const el of document.querySelectorAll('body *')) {
    const r = el.getBoundingClientRect();
    if (r.width === 0 || getComputedStyle(el).position === 'fixed') continue;
    if (r.right > innerWidth + 1 && !el.closest('.table-scroll, .scene, .sprite')) wide.push(el.tagName.toLowerCase() + (el.className && typeof el.className === 'string' ? '.' + el.className.split(' ')[0] : '') + ' right=' + Math.round(r.right));
    if (['P', 'H1', 'H2', 'H3', 'H4', 'A', 'BUTTON', 'SPAN', 'LI', 'SUMMARY', 'B', 'TD', 'TH'].includes(el.tagName) && el.scrollWidth > el.clientWidth + 1 && getComputedStyle(el).overflow !== 'visible' && !el.closest('.visually-hidden')) out.push('text clipped: ' + el.tagName + ' ' + el.textContent.trim().slice(0, 40));
  }
  if (wide.length) out.push('past the right edge: ' + [...new Set(wide)].slice(0, 6).join(', '));
  // Contrast: each element holding text, against the first opaque background behind it. The drawn menu bar is left
  // out (its text sits on a picture of a desktop, checked by eye).
  const rgb = (c) => (c.match(/[0-9.]+/g) || []).map(Number);
  const lum = ([r, g, b]) => [r, g, b].map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; })
    .reduce((sum, v, i) => sum + v * [0.2126, 0.7152, 0.0722][i], 0);
  const low = new Set();
  let checked = 0;
  for (const el of document.querySelectorAll('body *')) {
    const text = [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim());
    if (!text || el.closest('.scene, .visually-hidden, .skip')) continue;
    const style = getComputedStyle(el);
    if (style.visibility === 'hidden' || style.display === 'none' || parseFloat(style.opacity) === 0) continue;
    if (style.webkitTextFillColor === 'rgba(0, 0, 0, 0)' || style.color === 'rgba(0, 0, 0, 0)') continue; // gradient text
    let bg = null;
    for (let node = el; node; node = node.parentElement) {
      const b = rgb(getComputedStyle(node).backgroundColor);
      if (b.length >= 3 && (b[3] === undefined || b[3] > 0.9)) { bg = b; break; }
    }
    bg = bg || [0, 0, 0];
    const [l1, l2] = [lum(rgb(style.color)), lum(bg)].sort((a, b) => b - a);
    const ratio = (l1 + 0.05) / (l2 + 0.05);
    checked += 1;
    if (ratio < 4.5) low.add(el.tagName.toLowerCase() + ' "' + el.textContent.trim().slice(0, 32) + '" ' + ratio.toFixed(1) + ':1');
  }
  if (low.size) out.push('low contrast: ' + [...low].slice(0, 8).join('; ') + (low.size > 8 ? ' and ' + (low.size - 8) + ' more' : ''));
  if (checked < 100 && document.querySelector('[data-scene]')) out.push('contrast checked on ' + checked + ' texts only');
  out.push(...window.__tansu.csp.map((c) => 'CSP: ' + c), ...window.__tansu.errors.map((e) => 'error: ' + e));
  return out;
})()`;

// With reduced motion the hero rests on its final state: the drawers shown, the cloud drawer open, nothing moving.
const STILL = `(() => {
  const out = [];
  const scene = document.querySelector('[data-scene]');
  if (document.documentElement.dataset.motion !== 'still') out.push('reduced motion: html is not marked still');
  if (scene.dataset.phase && scene.dataset.phase !== 'open') out.push('reduced motion: the hero is ' + scene.dataset.phase);
  const shot = getComputedStyle(scene.querySelector('.drawer-shot'));
  if (shot.opacity !== '1') out.push('reduced motion: the drawer panel is not shown');
  if ([...scene.querySelectorAll('.glyph')].some((g) => getComputedStyle(g).opacity !== '0')) out.push('reduced motion: icons still in the menu bar');
  if (document.getAnimations().some((a) => a.playState === 'running')) out.push('reduced motion: something still moves');
  if (!document.querySelector('[data-scene-toggle]').hidden) out.push('reduced motion: the pause button shows for nothing');
  return out;
})()`;

const server = await startServer();
const chrome = await launchChrome();
const base = values.url ?? server.url;
let failures = 0;
try {
  for (const [name, size] of Object.entries(SIZES)) {
    if (values.only && values.only !== name) continue;
    const page = await chrome.newPage(size);
    await page.goto(base + values.path);
    await sleep(1200);
    const phase = await page.evaluate(`document.querySelector('[data-scene]')?.dataset.phase ?? 'none'`);
    await page.evaluate(PREPARE);
    await sleep(300);
    const problems = [...(await page.evaluate(INSPECT)), ...page.problems];
    if (!values.wrapped && phase !== 'none' && !['crowded', 'sorting'].includes(phase)) problems.push(`the hero is ${phase} a second after load, not crowded or sorting`);
    for (const t of page.transfers()) if (t.status >= 400) problems.push(`HTTP ${t.status}: ${t.url}`);
    const bytes = page.transfers().reduce((sum, t) => sum + t.bytes, 0);
    console.log(`${name} ${size.width}x${size.height}: ${problems.length ? problems.length + ' problem(s)' : 'clean'}, ${Math.round(bytes / 1024)} KB transferred`);
    for (const p of problems) console.log('  - ' + p);
    failures += problems.length;
    if (!values['no-shots']) {
      await page.evaluate(RESTORE);
      for (const id of SECTIONS) {
        await page.evaluate(`document.getElementById('${id}').scrollIntoView({ block: 'start', behavior: 'instant' })`);
        await sleep(250);
        await page.screenshot(join(SHOTS, `${name}-${id}.png`));
      }
      await page.evaluate(`scrollTo(0, document.documentElement.scrollHeight)`);
      await sleep(250);
      await page.screenshot(join(SHOTS, `${name}-footer.png`));
    }
    await page.close();
    if (!values['no-shots'] && !values.wrapped) {
      for (const state of HERO_STATES) {
        const still = await chrome.newPage(size);
        await still.goto(`${base}/?hero=${state}`);
        await sleep(state === 'sorting' ? 2200 : 700);
        await still.screenshot(join(SHOTS, `${name}-hero-${state}.png`));
        await still.close();
      }
    }
  }
  if (!values.wrapped && (!values.only || values.only === 'desktop')) {
    const page = await chrome.newPage({ ...SIZES.desktop, reducedMotion: true });
    await page.goto(base + '/');
    await sleep(1500);
    const problems = [...(await page.evaluate(STILL)), ...page.problems];
    console.log(`reduced motion: ${problems.length ? problems.length + ' problem(s)' : 'clean, the final state still'}`);
    for (const p of problems) console.log('  - ' + p);
    failures += problems.length;
    if (!values['no-shots']) await page.screenshot(join(SHOTS, 'desktop-reduced-motion.png'));
    await page.close();
  }
} finally {
  await chrome.close();
  await server.close();
  if (values.wrapped) {
    await rm(WRAPPED, { force: true });
    await rm(WRAPPED_CSS, { force: true });
  }
}
process.exitCode = failures ? 1 : 0;
