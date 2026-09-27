// The hero: a crowded menu bar sorts itself into three drawers, then the cloud drawer drops open. The sort plays once
// the scene is on screen, then loops calmly with pauses. It stops off screen, in a hidden tab and with the pause
// button, and rests on the final state (the drawer open) under reduced motion or without script.
// ?hero=crowded|sorting|open|sorted freezes one state, for the audit's pictures.

export const PHASES = Object.freeze(['crowded', 'sorting', 'open', 'sorted']);

/** One pass of the loop: each state, how long it holds before the next, and whether it fades in (reset). */
export const LOOP = Object.freeze([
  { phase: 'sorting', hold: 1900 },
  { phase: 'open', hold: 4200 },
  { phase: 'sorted', hold: 1800 },
  { phase: 'crowded', hold: 2600, reset: true },
]);
export const FIRST_WAIT = 1400; // the crowd, on screen, before the first sort
export const RESUME_WAIT = 1200; // a beat before the loop goes on after a pause
export const RESET_MS = 900; // the cross-fade back to the crowd

/** The state ?hero= asks for, or null. */
export function frozenPhase(search) {
  const value = new URLSearchParams(search).get('hero');
  return PHASES.includes(value) ? value : null;
}

/** The index in LOOP after `step` (-1 is the first crowd, before the loop starts). */
export function nextStep(step) {
  return (step + 1) % LOOP.length;
}

export function startHero(doc = document, win = window) {
  const scene = doc.querySelector('[data-scene]');
  if (!scene) return null;
  const button = doc.querySelector('[data-scene-toggle]');
  const frozen = frozenPhase(win.location.search);
  if (frozen) {
    scene.dataset.phase = frozen;
    return { frozen };
  }
  const reduce = win.matchMedia('(prefers-reduced-motion: reduce)');

  let step = -1;
  let timer = 0;
  let running = false;
  let visible = !('IntersectionObserver' in win);
  let userPaused = false;

  const canRun = () => running && visible && !doc.hidden && !userPaused;

  function stop() {
    win.clearTimeout(timer);
    timer = 0;
  }

  function schedule(ms) {
    stop();
    timer = win.setTimeout(advance, ms);
  }

  function advance() {
    timer = 0;
    step = nextStep(step);
    const { phase, hold, reset } = LOOP[step];
    if (reset) {
      scene.setAttribute('data-reset', '');
      win.setTimeout(() => scene.removeAttribute('data-reset'), RESET_MS);
    }
    scene.dataset.phase = phase;
    if (canRun()) schedule(hold);
  }

  function resume() {
    if (!canRun() || timer) return;
    schedule(step < 0 ? FIRST_WAIT : RESUME_WAIT);
  }

  function still() {
    running = false;
    stop();
    scene.removeAttribute('data-reset');
    scene.removeAttribute('data-paused');
    scene.dataset.phase = 'open';
    if (button) button.hidden = true;
  }

  function animate() {
    running = true;
    step = -1;
    scene.dataset.phase = 'crowded';
    if (button) button.hidden = false;
    resume();
  }

  if (button) {
    button.addEventListener('click', () => {
      userPaused = !userPaused;
      button.dataset.paused = String(userPaused);
      button.setAttribute('aria-label', userPaused ? 'Play the animation' : 'Pause the animation');
      scene.toggleAttribute('data-paused', userPaused);
      if (userPaused) stop();
      else resume();
    });
  }

  if ('IntersectionObserver' in win) {
    new win.IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      if (visible) resume();
      else stop();
    }, { threshold: 0.35 }).observe(scene);
  }
  doc.addEventListener('visibilitychange', () => (doc.hidden ? stop() : resume()));
  reduce.addEventListener?.('change', () => (reduce.matches ? still() : animate()));

  if (reduce.matches) still();
  else animate();
  return { get phase() { return scene.dataset.phase; } };
}
