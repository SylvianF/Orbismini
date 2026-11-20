// Bouton « Orbiscan » de l'écran Scan : ouvre la page Orbiscan du PC du magasin (servie par
// Orbismini, /orbiscan/) au-dessus de l'écran, en laissant la barre du bas visible : un autre
// bouton de la barre (ou la croix en haut à gauche) referme Orbiscan.
(() => {
  'use strict';
  const button = document.getElementById('orbiscan-open');
  const nav = document.querySelector('.views');
  if (!button || !nav) return;
  let frame = null;

  function press(active) {
    nav.querySelectorAll('button').forEach(b =>
      b.setAttribute('aria-pressed', String(active ? b.dataset.view === 'scans' : b.dataset.view === document.body.dataset.view))
    );
  }
  function close() {
    if (!frame) return;
    frame.remove();
    frame = null;
    press(false);
  }
  function fit() {
    if (frame) frame.style.bottom = nav.offsetHeight + 'px';
  }

  button.addEventListener('click', () => {
    if (frame) return;
    frame = document.createElement('div');
    frame.id = 'orbiscan-frame';
    const page = document.createElement('iframe');
    page.src = '/orbiscan/';
    page.title = 'Orbiscan';
    page.allow = 'camera';
    const x = document.createElement('button');
    x.type = 'button';
    x.className = 'close';
    x.setAttribute('aria-label', 'Fermer Orbiscan');
    x.textContent = '✕';
    x.onclick = close;
    frame.append(page, x);
    document.body.append(frame);
    fit();
    press(true);
  });
  // Un onglet de la barre touché : on quitte Orbiscan.
  nav.addEventListener('click', e => e.target.closest('button[data-view]') && close(), true);
  window.addEventListener('resize', fit);
  window.addEventListener('keydown', e => e.key === 'Escape' && close());
})();
