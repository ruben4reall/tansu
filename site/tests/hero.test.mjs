// The hero's timeline: the states it walks through, how calm the loop is, and a stylesheet that knows every state.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { FIRST_WAIT, LOOP, PHASES, RESET_MS, frozenPhase, nextStep } from '../js/hero.js';

const css = await readFile(new URL('../css/menubar.css', import.meta.url), 'utf8');

test('?hero= freezes a known state, and only a known one', () => {
  for (const phase of PHASES) assert.equal(frozenPhase(`?hero=${phase}`), phase);
  assert.equal(frozenPhase('?hero=dance'), null);
  assert.equal(frozenPhase(''), null);
  assert.equal(frozenPhase('?utm_source=x&hero=open'), 'open');
});

test('the loop sorts, opens the drawer, closes it, then fades back to the crowd', () => {
  assert.deepEqual(LOOP.map((s) => s.phase), ['sorting', 'open', 'sorted', 'crowded']);
  assert.deepEqual(LOOP.map((s) => Boolean(s.reset)), [false, false, false, true]);
  const walk = [];
  for (let step = -1, i = 0; i < 6; i += 1) walk.push(LOOP[(step = nextStep(step))].phase);
  assert.deepEqual(walk, ['sorting', 'open', 'sorted', 'crowded', 'sorting', 'open']);
});

test('the loop is calm: the drawer stays open a while, and each pass takes its time', () => {
  const hold = Object.fromEntries(LOOP.map((s) => [s.phase, s.hold]));
  assert.ok(hold.open >= 3000, 'the drawer stays open three seconds or more');
  assert.ok(LOOP.reduce((sum, s) => sum + s.hold, 0) >= 9000, 'a pass lasts nine seconds or more');
  assert.ok(FIRST_WAIT >= 1000, 'the crowd shows for a second before the first sort');
  assert.ok(RESET_MS < hold.crowded, 'the cross-fade ends before the next sort');
});

test('the stylesheet styles every state the script sets', () => {
  for (const phase of PHASES) assert.match(css, new RegExp(`\\[data-phase="${phase}"\\]`), phase);
  assert.match(css, /\[data-reset\]/);
  assert.match(css, /\[data-paused\]/);
  // Without data-phase the scene shows the final state; a page that will animate starts on the crowd.
  assert.match(css, /html\[data-motion="full"\] \.scene:not\(\[data-phase\]\) \.glyph/);
});

test('the sort sends each of the ten icons to one of the three drawers', () => {
  const slots = { 172: 'd0', 202: 'd1', 232: 'd2' };
  const glyphs = [...css.matchAll(/\.i(\d) \{ --r: (\d+); --to: (\d+); --i: (\d); \}/g)];
  assert.equal(glyphs.length, 10);
  for (const [, index, , to, order] of glyphs) {
    assert.equal(index, order);
    assert.ok(slots[to], `.i${index} goes to a drawer`);
  }
  for (const [r, drawer] of Object.entries(slots)) assert.match(css, new RegExp(`\\.${drawer} \\{ --r: ${r};`));
});
