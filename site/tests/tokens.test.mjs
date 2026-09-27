// The site's tokens are the brand's: css/tokens.css is pinned to brand/tokens/tokens.json, through the brand's
// build script and tools/sync-brand.mjs.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { readTokens, renderTokensCss, resolveValue, springEasing } from '../../brand/scripts/tokens/build.mjs';
import { declaredTokens, renderSiteTokens } from '../tools/sync-brand.mjs';

const tokens = readTokens();
const brandCss = await readFile(new URL('../../brand/tokens/tokens.css', import.meta.url), 'utf8');
const siteCss = await readFile(new URL('../css/tokens.css', import.meta.url), 'utf8');

// The palette of the brief, which the app's Theme.swift also holds.
const BRIEF = {
  night: '#0C0B0A', lacquer: '#17150F', rice: '#F5F1EA', ash: '#9D968B', honey: '#FFB938', ember: '#FF8A1F',
  paper: '#FAF8F4', ink: '#1C1A17', graphite: '#6E6A63', 'deep-honey': '#8F5600', hairline: '#DAD5CC',
};

const palette = () => Object.fromEntries(['dark', 'light'].flatMap((group) => Object.entries(tokens.color[group])
  .filter(([name]) => !name.startsWith('$')).map(([name, token]) => [name, token.$value])));

test('tokens.json holds the palette of the brief, and nothing else', () => {
  assert.deepEqual(palette(), BRIEF);
});

test('brand/tokens/tokens.css is built from tokens.json', () => {
  assert.equal(brandCss, renderTokensCss(tokens), 'run: node brand/scripts/tokens/build.mjs');
});

test('css/tokens.css is the brand file, copied', () => {
  assert.equal(siteCss, renderSiteTokens(brandCss), 'run: node tools/sync-brand.mjs');
});

test('every color of tokens.json reaches the site with its value', () => {
  const declared = declaredTokens(siteCss);
  for (const [name, value] of Object.entries(palette())) assert.equal(declared[`--tansu-${name}`], value, name);
  const glow = tokens.gradient.glow.$value.map((stop) => resolveValue(tokens, stop.color));
  assert.deepEqual(glow, [BRIEF.honey, BRIEF.ember]);
  assert.deepEqual([declared['--tansu-glow-1'], declared['--tansu-glow-2']], glow);
});

test('the drawer spring is the app\'s, settles, and barely overshoots', () => {
  assert.deepEqual(tokens.motion.spring.drawer.$value, { response: 0.32, dampingFraction: 0.86 });
  const { easing, seconds } = springEasing(tokens.motion.spring.drawer.$value);
  const points = easing.slice('linear('.length, -1).split(', ').map(Number);
  assert.equal(points[0], 0);
  assert.equal(points.at(-1), 1);
  assert.ok(Math.max(...points) < 1.01, 'overshoot under 1 %');
  assert.ok(seconds > 0.3 && seconds < 0.6, `${seconds}s`);
  assert.equal(declaredTokens(siteCss)['--tansu-spring-drawer'], easing);
});

test('text colors keep at least 4.5:1 on the backgrounds they are meant for', () => {
  const luminance = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4))
    .reduce((sum, v, i) => sum + v * [0.2126, 0.7152, 0.0722][i], 0);
  const ratio = (a, b) => {
    const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
    return (hi + 0.05) / (lo + 0.05);
  };
  for (const [text, background] of [
    ['rice', 'night'], ['rice', 'lacquer'], ['ash', 'night'], ['ash', 'lacquer'], ['honey', 'night'], ['honey', 'lacquer'],
    ['ink', 'paper'], ['graphite', 'paper'], ['deep-honey', 'paper'],
  ]) assert.ok(ratio(BRIEF[text], BRIEF[background]) >= 4.5, `${text} on ${background}: ${ratio(BRIEF[text], BRIEF[background]).toFixed(2)}:1`);
});
