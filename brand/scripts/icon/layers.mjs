// Writes Tansu's app icon, an Icon Composer document (brand/Tansu.icon), from brand/tokens/tokens.json.
//   node brand/scripts/icon/layers.mjs [icon-dir]
// A small chest of three drawers in Liquid Glass on warm black: the top and bottom drawers frosted, the middle one
// pulled toward you and lit in honey, the way a drawer of Tansu opens under the menu bar. Icon Composer renders SVG
// without filters, so every soft effect is a gradient. Groups are listed from the front to the back. Run
// brand/scripts/export-icon.sh afterwards for the previews. Running it twice writes identical files.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const tokens = JSON.parse(readFileSync(fileURLToPath(new URL('../../tokens/tokens.json', import.meta.url)), 'utf8'));
const color = (group, name) => tokens.color[group][name].$value;
const NIGHT = color('dark', 'night'), LACQUER = color('dark', 'lacquer'), RICE = color('dark', 'rice');
const HONEY = color('dark', 'honey'), EMBER = color('dark', 'ember'), INK = color('light', 'ink');

const OUT = process.argv[2] || fileURLToPath(new URL('../../Tansu.icon', import.meta.url));
mkdirSync(join(OUT, 'Assets'), { recursive: true });

const svg = (defs, body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n<defs>\n${defs.join('\n')}\n</defs>\n${body.join('\n')}\n</svg>\n`;
const stop = (offset, c, opacity = 1) => `<stop offset="${offset}" stop-color="${c}" stop-opacity="${opacity}"/>`;
const vertical = (id, y1, y2, stops) =>
  `<linearGradient id="${id}" x1="0" y1="${y1}" x2="0" y2="${y2}" gradientUnits="userSpaceOnUse">${stops.join('')}</linearGradient>`;

// Geometry, on the 1024 canvas (the whole canvas is the icon's body).
const BODY = { x: 208, y: 200, w: 608, h: 624, r: 70 };
const DRAWER = { x: 232, w: 560, h: 168, r: 44 };
const TOP_Y = 232, BOTTOM_Y = 624;
const OPEN = { x: 180, y: 428, w: 664, h: 184, r: 50 };
const HANDLE = { w: 112, h: 22 };

const files = {
  'glow.svg': svg(
    [`<radialGradient id="g" cx="512" cy="520" r="470" gradientUnits="userSpaceOnUse">${stop(0, HONEY, 0.62)}${stop(0.45, EMBER, 0.2)}${stop(1, EMBER, 0)}</radialGradient>`],
    ['<rect width="1024" height="1024" fill="url(#g)"/>']),
  'body.svg': svg(
    [vertical('b', BODY.y, BODY.y + BODY.h, [stop(0, '#FFFFFF', 0.2), stop(1, '#FFFFFF', 0.08)])],
    [`<rect x="${BODY.x}" y="${BODY.y}" width="${BODY.w}" height="${BODY.h}" rx="${BODY.r}" fill="url(#b)"/>`]),
  'top.svg': svg(
    [vertical('f', TOP_Y, TOP_Y + DRAWER.h, [stop(0, '#FFFFFF', 0.94), stop(1, RICE, 0.82)])],
    [`<rect x="${DRAWER.x}" y="${TOP_Y}" width="${DRAWER.w}" height="${DRAWER.h}" rx="${DRAWER.r}" fill="url(#f)"/>`]),
  'bottom.svg': svg(
    [vertical('f', BOTTOM_Y, BOTTOM_Y + DRAWER.h, [stop(0, '#FFFFFF', 0.9), stop(1, RICE, 0.76)])],
    [`<rect x="${DRAWER.x}" y="${BOTTOM_Y}" width="${DRAWER.w}" height="${DRAWER.h}" rx="${DRAWER.r}" fill="url(#f)"/>`]),
  'handles.svg': svg([], [
    `<g fill="${INK}" fill-opacity="0.55">`,
    `<rect x="${512 - HANDLE.w / 2}" y="${TOP_Y + DRAWER.h / 2 - HANDLE.h / 2}" width="${HANDLE.w}" height="${HANDLE.h}" rx="${HANDLE.h / 2}"/>`,
    `<rect x="${512 - HANDLE.w / 2}" y="${BOTTOM_Y + DRAWER.h / 2 - HANDLE.h / 2}" width="${HANDLE.w}" height="${HANDLE.h}" rx="${HANDLE.h / 2}"/>`,
    '</g>']),
  'open.svg': svg(
    [vertical('h', OPEN.y, OPEN.y + OPEN.h, [stop(0, '#FFD98A'), stop(0.55, HONEY), stop(1, EMBER)])],
    [`<rect x="${OPEN.x}" y="${OPEN.y}" width="${OPEN.w}" height="${OPEN.h}" rx="${OPEN.r}" fill="url(#h)"/>`]),
  'open-details.svg': svg(
    [`<linearGradient id="l" x1="${OPEN.x}" y1="0" x2="${OPEN.x + OPEN.w}" y2="0" gradientUnits="userSpaceOnUse">${stop(0, '#FFF4D6', 0)}${stop(0.5, '#FFF4D6', 0.95)}${stop(1, '#FFF4D6', 0)}</linearGradient>`],
    [
      // The light along the open drawer's top edge, and its handle.
      `<rect x="${OPEN.x + 50}" y="${OPEN.y + 4}" width="${OPEN.w - 100}" height="10" rx="5" fill="url(#l)"/>`,
      `<rect x="${512 - 66}" y="${OPEN.y + OPEN.h / 2 - 13}" width="132" height="26" rx="13" fill="#5A3200" fill-opacity="0.5"/>`,
    ]),
};

const srgb = (hex) => {
  const v = hex.replace('#', '');
  const c = [0, 2, 4].map((i) => (parseInt(v.slice(i, i + 2), 16) / 255).toFixed(5));
  return `srgb:${c.join(',')},1.00000`;
};
const fill = { 'linear-gradient': [srgb(LACQUER), srgb(NIGHT)], orientation: { start: { x: 0.5, y: 0 }, stop: { x: 0.5, y: 1 } } };
const icon = {
  'fill-specializations': [{ value: fill }, { appearance: 'dark', value: fill }],
  groups: [
    { name: 'Open', specular: true, shadow: { kind: 'neutral', opacity: 0.55 }, translucency: { enabled: true, value: 0.15 },
      layers: [{ 'image-name': 'open-details.svg', name: 'details', glass: false }, { 'image-name': 'open.svg', name: 'open', glass: true }] },
    { name: 'Drawers', specular: true, shadow: { kind: 'neutral', opacity: 0.45 }, translucency: { enabled: true, value: 0.3 }, 'blur-material': 0.4,
      layers: [{ 'image-name': 'handles.svg', name: 'handles', glass: false }, { 'image-name': 'top.svg', name: 'top', glass: true }, { 'image-name': 'bottom.svg', name: 'bottom', glass: true }] },
    { name: 'Body', specular: true, shadow: { kind: 'neutral', opacity: 0.35 }, translucency: { enabled: true, value: 0.5 }, 'blur-material': 0.6,
      layers: [{ 'image-name': 'body.svg', name: 'body', glass: true }] },
    { name: 'Glow', specular: false, shadow: { kind: 'none', opacity: 0 }, 'hidden-specializations': [{ appearance: 'tinted', value: true }],
      layers: [{ 'image-name': 'glow.svg', name: 'glow', glass: false }] },
  ],
  'supported-platforms': { squares: ['macOS'] },
};

for (const [name, content] of Object.entries(files)) writeFileSync(join(OUT, 'Assets', name), content);
writeFileSync(join(OUT, 'icon.json'), JSON.stringify(icon, null, 2) + '\n');
console.log(`wrote ${OUT}`);
