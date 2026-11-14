// Bouton « Orbiscan » de la barre du bas : ouvre la page Orbiscan du PC du magasin en plein
// écran (servie par Orbismini, /orbiscan/), avec seulement une croix en haut à gauche pour quitter.
(() => {
  'use strict';
  const button = document.getElementById('orbiscan-open');
  if (!button) return;
  let frame = null;
  function close() {
    frame?.remove();
    frame = null;
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
  });
  window.addEventListener('keydown', e => e.key === 'Escape' && close());
})();
