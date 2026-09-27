// Frames of the hero's animation, to check it by eye: the page loads, the menu bar sorts itself, the drawer drops,
// and the scene is photographed at several moments of its first pass (js/hero.js holds the timeline).
// Output: site/.shots/frames/<size>-hero-<ms>.png (ignored by git; delete it when done).
// Usage: node tools/frames.mjs [--only desktop|phone]
import { mkdir, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { parseArgs } from 'node:util';
import { setTimeout as sleep } from 'node:timers/promises';
import { SIZES, launchChrome } from './cdp.mjs';
import { SITE_DIR, startServer } from './serve.mjs';

// Milliseconds after load: the crowd, the flights, the three drawers, the drop, the drawer open, closed, the reset.
const MOMENTS = [600, 1700, 1950, 2150, 2400, 2700, 3300, 3450, 3650, 4200, 7700, 9200, 10000, 11400];
const { values } = parseArgs({ options: { only: { type: 'string' } } });
const OUT = join(SITE_DIR, '.shots', 'frames');
await rm(OUT, { recursive: true, force: true });
await mkdir(OUT, { recursive: true });

const server = await startServer();
const chrome = await launchChrome();
try {
  for (const name of ['desktop', 'phone']) {
    if (values.only && values.only !== name) continue;
    const page = await chrome.newPage(SIZES[name]);
    await page.goto(server.url + '/');
    const start = Date.now();
    const rect = await page.evaluate(`(() => { const r = document.querySelector('.scene-wrap').getBoundingClientRect(); return { x: r.x, y: r.y + scrollY, width: r.width, height: r.height }; })()`);
    for (const ms of MOMENTS) {
      await sleep(Math.max(0, ms - (Date.now() - start)));
      const phase = await page.evaluate(`document.querySelector('[data-scene]').dataset.phase`);
      await page.screenshot(join(OUT, `${name}-hero-${String(ms).padStart(5, '0')}-${phase}.png`), { ...rect, scale: 1 });
    }
    if (page.problems.length) console.log(`${name}:`, page.problems);
    await page.close();
  }
} finally {
  await chrome.close();
  await server.close();
}
console.log('frames in site/.shots/frames');
