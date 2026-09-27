// Runs before the first paint (render-blocking, a few hundred bytes): a page that will animate its menu bar starts
// on the crowded row, any other shows the sorted menu bar at once. hero.js takes over from here.
(function () {
  var root = document.documentElement;
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var frozen = /[?&]hero=/.test(window.location.search);
  root.setAttribute('data-motion', reduce || frozen ? 'still' : 'full');
  root.classList.add('js');
})();
