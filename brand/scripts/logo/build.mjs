// Writes Tiroir's wordmark from geometry: brand/wordmark/tiroir-wordmark-ink.svg (on light) and -rice.svg (on dark).
//   node brand/scripts/logo/build.mjs
// Lowercase monoline letters with round ends, drawn as center lines with one stroke width, on an x-height of 100
// units. The crossbar of the t is honey: the handle of a drawer, the brand's one accent. Running it twice writes
// identical files.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const tokens = JSON.parse(readFileSync(fileURLToPath(new URL('../../tokens/tokens.json', import.meta.url)), 'utf8'));
const color = (group, name) => tokens.color[group][name].$value;
const INK = color('light', 'ink'), RICE = color('dark', 'rice'), HONEY = color('dark', 'honey'), DEEP = color('light', 'deep-honey');

const STROKE = 22;            // stroke width; the letters span from -11 to 111 around the x-height box
const R = 39;                 // radius of every bowl's center line
const GAP = 30;               // space between two letters' outer edges

// Each letter: its center-line paths relative to its own left edge (outer), and its outer width.
const half = STROKE / 2;
const letters = {
  t: {
    width: 64,
    paths: (x) => [`M${x + 20},-38V64C${x + 20},90 ${x + 32},100 ${x + 53},100`],
    handle: (x) => `M${x + half},0H${x + 64 - half}`,
  },
  a: {
    width: 2 * R + STROKE,
    paths: (x) => {
      const cx = x + half + R;
      return [`M${cx + R},50A${R},${R} 0 1,1 ${cx + R},49.99`, `M${cx + R},${half}V100`];
    },
  },
  n: {
    width: 2 * R + STROKE,
    paths: (x) => {
      const left = x + half, right = x + half + 2 * R;
      return [`M${left},100V${half}`, `M${left},${50}A${R},${R} 0 0,1 ${right},${50}V100`];
    },
  },
  s: {
    width: 76,
    paths: (x) => [
      `M${x + 68},26C${x + 62},15 ${x + 51},${half} ${x + 38},${half}` +
      `C${x + 22},${half} ${x + 11},19 ${x + 11},31C${x + 11},45 ${x + 24},49 ${x + 39},52` +
      `C${x + 54},55 ${x + 65},60 ${x + 65},73C${x + 65},86 ${x + 53},${100 - half} ${x + 38},${100 - half}` +
      `C${x + 24},${100 - half} ${x + 13},85 ${x + 8},74`,
    ],
  },
  i: {
    width: STROKE,
    // The stem, and a round dot above it: a stroke so short that its round caps make the dot.
    paths: (x) => [`M${x + half},100V${half}`, `M${x + half},-30V-30.01`],
  },
  r: {
    width: STROKE + R + 10,
    // Its flag leaves room under it: the next letter comes closer.
    kern: -12,
    paths: (x) => {
      const left = x + half;
      return [`M${left},100V${half}`, `M${left},50A${R},${R} 0 0,1 ${left + R},${half}H${left + R + 10}`];
    },
  },
  o: {
    width: 2 * R + STROKE,
    paths: (x) => {
      const cx = x + half + R;
      return [`M${cx + R},50A${R},${R} 0 1,1 ${cx + R},49.99`];
    },
  },
  u: {
    width: 2 * R + STROKE,
    paths: (x) => {
      const left = x + half, right = x + half + 2 * R;
      return [`M${left},${half}V${50}A${R},${R} 0 0,0 ${right},${50}`, `M${right},${half}V100`];
    },
  },
};

function wordmark(textColor, accent) {
  let x = 0;
  const strokes = [];
  let handle = '';
  for (const char of 'tiroir') {
    const letter = letters[char];
    strokes.push(...letter.paths(x));
    if (letter.handle) handle = letter.handle(x);
    x += letter.width + GAP + (letter.kern ?? 0);
  }
  const width = x - GAP;
  const top = -38 - half, bottom = 100 + half;
  const view = `${-2} ${top - 2} ${width + 4} ${bottom - top + 4}`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${view}" width="${width + 4}" height="${bottom - top + 4}" role="img" aria-label="Tiroir">\n` +
    `<g fill="none" stroke-width="${STROKE}" stroke-linecap="round" stroke-linejoin="round">\n` +
    `<path stroke="${textColor}" d="${strokes.join('')}"/>\n` +
    `<path stroke="${accent}" d="${handle}"/>\n` +
    `</g>\n</svg>\n`;
}

const out = fileURLToPath(new URL('../../wordmark/', import.meta.url));
mkdirSync(out, { recursive: true });
writeFileSync(`${out}tiroir-wordmark-ink.svg`, wordmark(INK, DEEP));
writeFileSync(`${out}tiroir-wordmark-rice.svg`, wordmark(RICE, HONEY));
console.log('wrote the wordmarks');
