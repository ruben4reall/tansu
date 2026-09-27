// Draws the placeholder pictures the page needs until the real ones exist: the captures of the app (CAPTURES.md
// says what each real one must show), the favicon, the Apple touch icon and the social picture. Every placeholder
// carries the PNG text "tansu-placeholder" (tools/png.mjs), so the release test can tell it from a real picture.
// A file that exists and is not a placeholder is never overwritten.
// Usage: node tools/placeholders.mjs   (needs Google Chrome; set CHROME_PATH to use another)
import { existsSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { launchChrome } from './cdp.mjs';
import { icoPng, isPlaceholder, markPlaceholder, pngSize, pngToIco } from './png.mjs';
import { SITE_DIR } from './serve.mjs';

// ---------- Shapes, in the neutral warm greys of the app's dark windows

const C = {
  window: '#1A1713', sidebar: '#211D18', card: '#231F1A', well: '#2A251F', tile: '#3A342C', tile2: '#332E27',
  strong: '#5A5249', line: '#4A433B', faint: '#3A342D', light: '#D9D1C4', mid: '#8A8176', edge: 'rgba(245,241,234,0.13)',
};
const rect = (x, y, w, h, r, fill, extra = '') => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}" ${extra}/>`;
const svg = (w, h, body, defs = '') => `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><defs>${defs}</defs>${body}</svg>`;
const glass = `<linearGradient id="glass" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2B2621" stop-opacity="0.97"/><stop offset="1" stop-color="#1D1A16" stop-opacity="0.97"/></linearGradient>`;
const windowGrad = `<linearGradient id="win" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1D1A16"/><stop offset="1" stop-color="#161310"/></linearGradient>`;
const frame = (w, h, r, fill) => rect(0.5, 0.5, w - 1, h - 1, r, fill, `stroke="${C.edge}"`);

/** A grid of app tiles with a name under each, as in a drawer. */
function tiles(x0, y0, count, { cols = 5, cell = 64, row = 74, size = 36 } = {}) {
  let out = '';
  for (let i = 0; i < count; i += 1) {
    const cx = x0 + cell / 2 + (i % cols) * cell;
    const y = y0 + Math.floor(i / cols) * row;
    out += rect(cx - size / 2, y, size, size, size / 4, i % 3 === 1 ? C.tile2 : C.tile);
    out += rect(cx - 19, y + size + 10, 38, 6, 3, C.line);
  }
  return out;
}

function sidebar(h, selected) {
  let out = `<path d="M14.5 0.5H200V${h - 0.5}H14.5A14 14 0 0 1 0.5 ${h - 14.5}V14.5A14 14 0 0 1 14.5 0.5Z" fill="${C.sidebar}"/>`;
  out += rect(20, 20, 10, 10, 5, C.faint) + rect(36, 20, 10, 10, 5, C.faint) + rect(52, 20, 10, 10, 5, C.faint);
  const widths = [74, 64, 96, 72, 84, 66, 58];
  widths.forEach((w, i) => {
    const y = 64 + i * 38;
    if (i === selected) out += rect(10, y - 9, 180, 34, 8, C.tile);
    out += rect(22, y, 16, 16, 5, i === selected ? C.mid : C.line) + rect(48, y + 4, w, 8, 4, i === selected ? C.light : C.strong);
  });
  return out;
}

const DRAW = {
  // The Files & Cloud drawer's panel: a title, seven icons in two rows.
  drawerFiles: (w, h) => svg(w, h, frame(w, h, 16, 'url(#glass)') + rect(20, 18, 84, 9, 4.5, C.strong) + rect(292, 18, 48, 9, 4.5, C.faint) + tiles(20, 44, 7), glass),

  // The welcome's Smart Sort step: a heading, the menu bar preview, three drawers, the choice and the buttons.
  welcomeSort: (w, h) => {
    let body = frame(w, h, 16, 'url(#win)');
    body += rect(250, 42, 140, 12, 6, C.strong) + rect(190, 66, 260, 8, 4, C.faint);
    body += rect(40, 96, 560, 40, 10, C.well, `stroke="${C.edge}"`);
    body += rect(540, 112, 44, 8, 4, C.mid);
    for (const x of [512, 490, 468]) body += rect(x, 110, 12, 12, 3, C.line);
    for (const cx of [440, 414, 388]) body += `<circle cx="${cx}" cy="116" r="9" fill="${C.mid}"/>`;
    [[40, 5], [232, 3], [424, 4]].forEach(([x, n]) => {
      body += rect(x, 160, 176, 196, 14, C.card, `stroke="${C.edge}"`);
      body += `<circle cx="${x + 26}" cy="${188}" r="10" fill="${C.line}"/>` + rect(x + 44, 184, 80, 8, 4, C.strong);
      body += tiles(x + 13, 214, n, { cols: 3, cell: 50, row: 66, size: 34 });
    });
    body += rect(170, 380, 300, 32, 9, C.well) + rect(173, 383, 98, 26, 7, C.line) + rect(274, 389, 1, 14, 0, C.faint) + rect(372, 389, 1, 14, 0, C.faint);
    body += rect(210, 428, 220, 7, 3.5, C.faint);
    body += rect(150, 486, 150, 36, 18, 'none', `stroke="${C.line}" stroke-width="1.5"`) + rect(320, 486, 170, 36, 18, C.light, 'fill-opacity="0.85"');
    return svg(w, h, body, windowGrad);
  },

  // A drawer up close with the menu of one icon open.
  drawerCloseup: (w, h) => {
    let body = rect(16.5, 16.5, 379, 225, 16, 'url(#glass)', `stroke="${C.edge}"`);
    body += rect(36, 34, 96, 9, 4.5, C.strong) + tiles(36, 60, 7, { cols: 5, cell: 68, row: 78, size: 38 });
    body += rect(96, 136, 48, 48, 12, 'none', `stroke="${C.mid}" stroke-width="2"`);
    body += rect(236, 152, 206, 168, 12, '#2C2722', `stroke="${C.edge}"`);
    [[176, 104], [208, 134], [240, 58], [284, 118]].forEach(([y, wd]) => { body += rect(254, y, wd, 8, 4, C.light, 'fill-opacity="0.8"'); });
    body += `<path d="M420 176l5 4-5 4" fill="none" stroke="${C.mid}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>`;
    body += rect(250, 264, 178, 1, 0, C.faint);
    return svg(w, h, body, glass);
  },

  // The search field with two letters typed and three results.
  search: (w, h) => {
    let body = frame(w, h, 18, 'url(#glass)');
    body += `<circle cx="34" cy="32" r="8" fill="none" stroke="${C.mid}" stroke-width="2.2"/><path d="M40 38l6 6" stroke="${C.mid}" stroke-width="2.2" stroke-linecap="round"/>`;
    body += rect(60, 25, 26, 14, 3, C.light) + rect(90, 22, 2, 20, 1, C.light);
    body += rect(0.5, 64, w - 1, 1, 0, C.faint);
    [78, 140, 202].forEach((y, i) => {
      if (i === 0) body += rect(10, y, w - 20, 56, 10, C.tile);
      body += rect(26, y + 10, 36, 36, 9, i === 0 ? C.strong : C.tile) + rect(76, y + 16, [150, 120, 170][i], 9, 4.5, C.light, 'fill-opacity="0.85"') + rect(76, y + 33, 90, 7, 3.5, C.line);
      body += `<circle cx="${w - 44}" cy="${y + 28}" r="8" fill="${C.mid}"/>` + rect(w - 128, y + 24, 70, 8, 4, C.strong);
    });
    return svg(w, h, body, glass);
  },

  // Settings, Layout: the menu bar at its real size with the notch, the gauge, a card per drawer.
  settingsLayout: (w, h) => {
    let body = frame(w, h, 14, 'url(#win)') + sidebar(h, 0);
    body += rect(224, 36, 120, 14, 7, C.strong) + rect(224, 60, 300, 8, 4, C.faint);
    body += rect(224, 88, 572, 44, 10, C.well, `stroke="${C.edge}"`);
    body += `<path d="M430 88.5h120v22a10 10 0 0 1-10 10H440a10 10 0 0 1-10-10Z" fill="#0A0908"/>`;
    for (const x of [240, 276, 318, 358]) body += rect(x, 106, 26, 8, 4, C.line);
    for (const x of [574, 598, 622, 646, 670, 694]) body += rect(x, 104, 12, 12, 3, C.mid);
    body += rect(726, 106, 54, 8, 4, C.light, 'fill-opacity="0.8"');
    body += rect(224, 150, 170, 8, 4, C.strong) + rect(680, 150, 116, 8, 4, C.faint);
    body += rect(224, 168, 572, 10, 5, C.well) + rect(224, 168, 360, 10, 5, C.mid);
    [[224, 198, 5], [512, 198, 4], [224, 392, 3], [512, 392, 2]].forEach(([x, y, n]) => {
      body += rect(x, y, 284, 178, 14, C.card, `stroke="${C.edge}"`);
      body += `<circle cx="${x + 26}" cy="${y + 28}" r="10" fill="${C.line}"/>` + rect(x + 44, y + 24, 90, 8, 4, C.strong) + rect(x + 222, y + 24, 40, 8, 4, C.faint);
      body += tiles(x + 12, y + 60, n, { cols: 5, cell: 52, row: 70, size: 32 });
    });
    return svg(w, h, body, windowGrad);
  },

  // Settings, Appearance: a live preview of the tinted menu bar and its controls.
  settingsAppearance: (w, h) => {
    const preview = `<linearGradient id="pv" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4A3020"/><stop offset="1" stop-color="#1C130D"/></linearGradient>`;
    let body = frame(w, h, 14, 'url(#win)') + sidebar(h, 2);
    body += rect(224, 36, 150, 14, 7, C.strong);
    body += rect(224, 66, 572, 160, 14, 'url(#pv)', `stroke="${C.edge}"`);
    body += `<path d="M224.5 80a14 14 0 0 1 14-14h543a14 14 0 0 1 14 14v18H224.5Z" fill="#6B4A2A" fill-opacity="0.75"/>`;
    for (const x of [600, 624, 648, 672, 696]) body += rect(x, 76, 12, 12, 3, C.light, 'fill-opacity="0.8"');
    body += rect(726, 78, 54, 8, 4, C.light, 'fill-opacity="0.9"');
    [258, 318, 378, 438, 498].forEach((y, i) => {
      body += rect(224, y, [130, 90, 110, 120, 100][i], 9, 4.5, C.light, 'fill-opacity="0.75"');
      if (i === 0) body += rect(560, y - 11, 236, 30, 9, C.well) + rect(638, y - 8, 76, 24, 7, C.line);
      if (i === 1 || i === 2) body += rect(560, y + 2, 236, 6, 3, C.well) + rect(560, y + 2, i === 1 ? 150 : 90, 6, 3, C.mid) + `<circle cx="${i === 1 ? 710 : 650}" cy="${y + 5}" r="10" fill="${C.light}"/>`;
      if (i >= 3) body += rect(748, y - 8, 48, 26, 13, i === 3 ? C.mid : C.well) + `<circle cx="${i === 3 ? 783 : 761}" cy="${y + 5}" r="10" fill="${C.light}"/>`;
      if (i < 4) body += rect(224, y + 34, 572, 1, 0, C.faint);
    });
    return svg(w, h, body, windowGrad + preview);
  },

  // Honey on night: a lit drawer under the bar. The real icon replaces these.
  favicon: () => svg(32, 32, rect(0, 0, 32, 32, 7, '#0C0B0A') + rect(6, 7.5, 20, 4, 2, '#F5F1EA', 'fill-opacity="0.4"') + rect(6, 14.5, 20, 11.5, 3, '#FFB938') + rect(13, 19.2, 6, 2.2, 1.1, '#0C0B0A')),
  touchIcon: () => svg(180, 180, rect(0, 0, 180, 180, 0, '#0C0B0A') + rect(38, 46, 104, 18, 9, '#F5F1EA', 'fill-opacity="0.32"') + rect(38, 80, 104, 58, 15, 'url(#glow)') + rect(73, 104, 34, 10, 5, '#0C0B0A'),
    `<linearGradient id="glow" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFB938"/><stop offset="1" stop-color="#FF8A1F"/></linearGradient>`),
};

// The social picture: Inter only (the page's webfont), the page's own glyphs, never an emoji or SF Pro in a picture.
async function ogHtml() {
  const font = async (weight) => (await readFile(join(SITE_DIR, `assets/fonts/inter-${weight}.woff2`))).toString('base64');
  // The three drawers of the hero, drawn as the page draws them (index.html, symbols d-files, d-security, d-messages).
  const glyph = (d, x) => `<svg x="${x}" y="25" width="36" height="36" viewBox="0 0 24 24" color="#F5F1EA">${d}</svg>`;
  const cloud = '<g fill="currentColor"><path d="M6 19.5h11.2a4.6 4.6 0 0 0 1-9.1 6.3 6.3 0 0 0-12.3.7A4.3 4.3 0 0 0 6 19.5Z"/></g>';
  const lock = '<g fill="currentColor"><path fill-rule="evenodd" d="M7.4 10.2h9.2a2.4 2.4 0 0 1 2.4 2.4v5.5a2.4 2.4 0 0 1-2.4 2.4H7.4A2.4 2.4 0 0 1 5 18.1v-5.5a2.4 2.4 0 0 1 2.4-2.4ZM11.1 14.1a.9.9 0 0 1 1.8 0v2.3a.9.9 0 0 1-1.8 0Z"/></g><path d="M8.3 10.2V8a3.7 3.7 0 0 1 7.4 0v2.2" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"/>';
  const chat = '<g fill="currentColor"><path d="M11 3h7a3 3 0 0 1 3 3v4a3 3 0 0 1-2.2 2.9l.9 2.6-3.1-2.5h-.1V8.5A1.5 1.5 0 0 0 15 7H8V6a3 3 0 0 1 3-3Z"/><path d="M6 8.5h6.5a3 3 0 0 1 3 3V15a3 3 0 0 1-3 3H9l-3.5 2.8v-2.9A3 3 0 0 1 3 15v-3.5a3 3 0 0 1 3-3Z"/></g>';
  const bar = `<svg width="520" height="300" viewBox="0 0 520 300">
    <rect x="0.5" y="0.5" width="519" height="86" rx="18" fill="#1A140F" fill-opacity="0.72" stroke="rgba(245,241,234,0.14)"/>
    <rect x="96" y="17" width="54" height="52" rx="12" fill="#F5F1EA" fill-opacity="0.18"/>
    ${glyph(cloud, 105)}${glyph(lock, 171)}${glyph(chat, 237)}
    <text x="492" y="54" text-anchor="end" font-family="I" font-weight="600" font-size="26" fill="#F5F1EA">10:08</text>
    <rect x="30" y="104" width="190" height="160" rx="20" fill="#221D17" fill-opacity="0.94" stroke="rgba(245,241,234,0.14)"/>
    ${[0, 1, 2].map((i) => `<rect x="${52 + i * 56}" y="130" width="42" height="42" rx="11" fill="#3A342C"/><rect x="${53 + i * 56}" y="184" width="40" height="7" rx="3.5" fill="#4A433B"/>`).join('')}
    ${[0, 1].map((i) => `<rect x="${52 + i * 56}" y="206" width="42" height="42" rx="11" fill="#3A342C"/>`).join('')}
  </svg>`;
  return `<!doctype html><html><head><meta charset="utf-8"><style>
    @font-face { font-family: I; src: url(data:font/woff2;base64,${await font(400)}) format('woff2'); font-weight: 400; }
    @font-face { font-family: I; src: url(data:font/woff2;base64,${await font(600)}) format('woff2'); font-weight: 600; }
    html, body { margin: 0; }
    .og { position: relative; width: 1280px; height: 640px; overflow: hidden; color: #F5F1EA; font-family: I;
      background: radial-gradient(60% 70% at 88% 18%, rgba(255,185,56,0.34), rgba(255,185,56,0) 70%),
        radial-gradient(50% 60% at 70% 110%, rgba(255,138,31,0.28), rgba(255,138,31,0) 70%), #0C0B0A; }
    .copy { position: absolute; left: 96px; top: 190px; }
    .name { font-size: 132px; font-weight: 600; letter-spacing: -2px; line-height: 1; }
    .tag { margin-top: 26px; color: #9D968B; font-size: 46px; letter-spacing: -0.5px; }
    .fine { margin-top: 26px; color: #908980; font-size: 26px; }
    .art { position: absolute; right: 80px; top: 150px; }
  </style></head><body><div class="og"><div class="copy"><div class="name">Tansu</div><div class="tag">Your menu bar, in drawers.</div><div class="fine">Free and open source, for macOS 26 and 27</div></div><div class="art">${bar}</div></div></body></html>`;
}

const JOBS = [
  { path: 'assets/app/drawer-files', w: 360, h: 200, draw: DRAW.drawerFiles, retina: true },
  { path: 'assets/app/welcome-sort', w: 640, h: 560, draw: DRAW.welcomeSort, retina: true },
  { path: 'assets/app/drawer-closeup', w: 520, h: 340, draw: DRAW.drawerCloseup, retina: true },
  { path: 'assets/app/search', w: 600, h: 280, draw: DRAW.search, retina: true },
  { path: 'assets/app/settings-layout', w: 820, h: 600, draw: DRAW.settingsLayout, retina: true },
  { path: 'assets/app/settings-appearance', w: 820, h: 600, draw: DRAW.settingsAppearance, retina: true },
  { path: 'assets/brand/favicon-32', w: 32, h: 32, draw: DRAW.favicon },
  { path: 'assets/brand/apple-touch-icon', w: 180, h: 180, draw: DRAW.touchIcon },
  { path: 'assets/brand/og', w: 1280, h: 640, html: ogHtml },
];

async function render(page, html, w, h) {
  await page.goto(`data:text/html;base64,${Buffer.from(html).toString('base64')}`);
  await page.evaluate('document.fonts.ready.then(() => true)');
  return page.screenshot(null, { x: 0, y: 0, width: w, height: h, scale: 1 });
}

const chrome = await launchChrome();
const report = [];
try {
  const pages = {
    1: await chrome.newPage({ width: 1280, height: 700, deviceScaleFactor: 1, transparent: true }),
    2: await chrome.newPage({ width: 1280, height: 700, deviceScaleFactor: 2, transparent: true }),
  };
  for (const job of JOBS) {
    const html = job.html ? await job.html() : `<!doctype html><html><head><style>html,body{margin:0}svg{display:block}</style></head><body>${job.draw(job.w, job.h)}</body></html>`;
    for (const scale of job.retina ? [1, 2] : [1]) {
      const file = join(SITE_DIR, `${job.path}${scale === 2 ? '@2x' : ''}.png`);
      const name = file.slice(SITE_DIR.length + 1);
      if (existsSync(file) && !isPlaceholder(await readFile(file))) {
        report.push(`kept ${name}: a real picture`);
        continue;
      }
      const png = markPlaceholder(await render(pages[scale], html, job.w, job.h));
      const { width, height } = pngSize(png);
      if (width !== job.w * scale || height !== job.h * scale) throw new Error(`${name}: ${width}x${height}, expected ${job.w * scale}x${job.h * scale}`);
      await mkdir(dirname(file), { recursive: true });
      await writeFile(file, png);
      report.push(`drew ${name} (${width}x${height}, ${Math.round(png.length / 1024)} KB)`);
    }
  }
  // favicon.ico at the root, for the browsers, readers and crawlers that ask for it whatever the page says.
  const ico = join(SITE_DIR, 'favicon.ico');
  if (existsSync(ico) && !isPlaceholder(icoPng(await readFile(ico)))) report.push('kept favicon.ico: a real icon');
  else {
    await writeFile(ico, pngToIco(await readFile(join(SITE_DIR, 'assets/brand/favicon-32.png'))));
    report.push('drew favicon.ico (from assets/brand/favicon-32.png)');
  }
} finally {
  await chrome.close();
}
console.log(report.join('\n'));
