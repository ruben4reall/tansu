// Ruben's own page counter (ruben-analytics): one anonymous page view, no cookie, no identifier, sent as a
// beacon after load so it never slows the page. Only the production site counts; a local copy or a preview sends
// nothing.
const ENDPOINT = 'https://ruben-analytics.vercel.app/api/hit';
export const PRODUCTION_HOST = 'gettansu.vercel.app';

export function startBeacon(doc = document, win = window) {
  if (win.location.hostname !== PRODUCTION_HOST) return false;
  const body = JSON.stringify({ site: 'tansu', path: win.location.pathname, ref: doc.referrer });
  try {
    if (!win.navigator.sendBeacon(ENDPOINT, body)) throw new Error('beacon');
  } catch {
    win.fetch(ENDPOINT, { method: 'POST', body, keepalive: true }).catch(() => {});
  }
  return true;
}
