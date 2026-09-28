// The page counter speaks only from the production site, and says only which page was seen.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { PRODUCTION_HOST, startBeacon } from '../js/beacon.js';

function fakeWindow(hostname, { accept = true } = {}) {
  const sent = [];
  return {
    sent,
    location: { hostname, pathname: '/' },
    navigator: { sendBeacon: (url, body) => { sent.push({ url, body, via: 'beacon' }); return accept; } },
    fetch: (url, init) => { sent.push({ url, body: init.body, via: 'fetch' }); return Promise.resolve(); },
  };
}

test('one anonymous view from gettiroir.vercel.app, counted as tiroir', () => {
  assert.equal(PRODUCTION_HOST, 'gettiroir.vercel.app');
  const win = fakeWindow(PRODUCTION_HOST);
  assert.equal(startBeacon({ referrer: 'https://example.com/' }, win), true);
  assert.equal(win.sent.length, 1);
  assert.equal(win.sent[0].url, 'https://ruben-analytics.vercel.app/api/hit');
  assert.deepEqual(JSON.parse(win.sent[0].body), { site: 'tiroir', path: '/', ref: 'https://example.com/' });
});

test('nothing from a local copy, a preview deployment or another site', () => {
  for (const host of ['localhost', '127.0.0.1', '', 'tiroir-git-main-ruben.vercel.app', 'getpli.vercel.app', 'gettiroir.vercel.app.example.com']) {
    const win = fakeWindow(host);
    assert.equal(startBeacon({ referrer: '' }, win), false, host);
    assert.deepEqual(win.sent, [], host);
  }
});

test('falls back to a keepalive fetch when the browser refuses the beacon', () => {
  const win = fakeWindow(PRODUCTION_HOST, { accept: false });
  startBeacon({ referrer: '' }, win);
  assert.deepEqual(win.sent.map((s) => s.via), ['beacon', 'fetch']);
});
