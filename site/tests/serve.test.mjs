// The local server applies vercel.json like production, so the CSP is live during every check; and vercel.json
// itself keeps Pli's strict rules.
import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { headersFor, loadHeaderRules, sourceToRegExp, startServer } from '../tools/serve.mjs';

let server;
before(async () => { server = await startServer(); });
after(async () => { await server.close(); });

test('vercel source patterns become anchored expressions', () => {
  assert.ok(sourceToRegExp('/(.*)').test('/anything/at/all'));
  assert.ok(sourceToRegExp('/assets/(.*)').test('/assets/app/drawer-files.png'));
  assert.ok(!sourceToRegExp('/assets/(.*)').test('/css/site.css'));
  assert.ok(!sourceToRegExp('/a.b').test('/aXb'));
});

test('every path gets the strict CSP; assets also get their cache rule', async () => {
  const rules = await loadHeaderRules();
  const csp = headersFor('/', rules)['Content-Security-Policy'];
  assert.match(csp, /default-src 'none';/);
  assert.match(csp, /script-src 'self';/);
  assert.match(csp, /style-src 'self';/);
  assert.doesNotMatch(csp, /unsafe-inline|unsafe-eval/);
  assert.match(csp, /connect-src 'self' https:\/\/ruben-analytics\.vercel\.app;/);
  assert.match(csp, /frame-ancestors 'none'/);
  assert.match(headersFor('/assets/app/drawer-files.png', rules)['Cache-Control'], /max-age=86400/);
});

test('the appcast is never served from a cache without asking', async () => {
  const rules = await loadHeaderRules();
  assert.equal(headersFor('/appcast.xml', rules)['Cache-Control'], 'public, max-age=0, must-revalidate');
});

test('the security headers of every page', async () => {
  const page = headersFor('/', await loadHeaderRules());
  assert.match(page['Strict-Transport-Security'], /max-age=63072000/);
  assert.equal(page['X-Content-Type-Options'], 'nosniff');
  assert.equal(page['X-Frame-Options'], 'DENY');
  assert.equal(page['Cross-Origin-Opener-Policy'], 'same-origin');
  assert.equal(page['Cross-Origin-Resource-Policy'], 'same-origin');
  assert.match(page['Permissions-Policy'], /camera=\(\), microphone=\(\)/);
});

test('the server serves the page with its headers, clean URLs and a real 404', async () => {
  const home = await fetch(`${server.url}/`);
  assert.equal(home.status, 200);
  assert.match(home.headers.get('content-type'), /text\/html/);
  assert.match(home.headers.get('content-security-policy'), /default-src 'none'/);
  const clean = await fetch(`${server.url}/404`);
  assert.equal(clean.status, 200);
  const missing = await fetch(`${server.url}/nope`);
  assert.equal(missing.status, 404);
  assert.match(await missing.text(), /Page not found/);
  const text = await fetch(`${server.url}/robots.txt`);
  assert.match(text.headers.get('content-type'), /text\/plain/);
  const feed = await fetch(`${server.url}/appcast.xml`);
  assert.match(feed.headers.get('content-type'), /application\/xml/);
});

test('paths never escape the site folder', async () => {
  const response = await fetch(`${server.url}/%2e%2e/%2e%2e/etc/passwd`);
  assert.equal(response.status, 404);
});
