// The page's entry point: each part starts on its own, and a failure in one never stops the others.
import { startBeacon } from './beacon.js';
import { startHero } from './hero.js';
import { startReveal } from './reveal.js';

for (const start of [startHero, startReveal]) {
  try {
    start();
  } catch (error) {
    console.error(error);
  }
}

window.addEventListener('load', () => {
  requestAnimationFrame(() => document.documentElement.classList.add('smooth-scroll'));
  try {
    startBeacon();
  } catch (error) {
    console.error(error);
  }
}, { once: true });
