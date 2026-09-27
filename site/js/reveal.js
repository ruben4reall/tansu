// Sections ease in as they scroll into view. What is already on screen is marked shown before the effect turns on,
// so nothing blinks; with reduced motion, or without IntersectionObserver, everything simply shows.
export function startReveal(doc = document, win = window) {
  const items = [...doc.querySelectorAll('.reveal')];
  if (!items.length || !('IntersectionObserver' in win)) return;
  if (win.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const onScreen = (el) => {
    const box = el.getBoundingClientRect();
    return box.top < win.innerHeight && box.bottom > 0;
  };
  const later = items.filter((el) => {
    if (!onScreen(el)) return true;
    el.classList.add('in');
    return false;
  });
  doc.documentElement.classList.add('reveal-on');
  const observer = new win.IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('in');
      observer.unobserve(entry.target);
    }
  }, { rootMargin: '0px 0px -8% 0px' });
  later.forEach((el) => observer.observe(el));
}
