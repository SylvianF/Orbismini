// Annonce d'une nouvelle version d'Orbismini, sans recharger une saisie en cours.
// Seulement quand la version en ligne (VERSION de sw.js) diffère de celle de la page affichée
// (?v= de ce fichier) : pas d'annonce quand la page est déjà la dernière, quoi que fasse la copie
// de secours gardée sur le téléphone. Vérifié à l'ouverture et à chaque retour dans l'application.
(() => {
  'use strict';
  if (!('serviceWorker' in navigator)) return;
  const shown = new URL(document.currentScript?.src || location.href).searchParams.get('v') || '';
  let notified = false,
    registration = null;
  async function online() {
    try {
      const r = await fetch('sw.js', { cache: 'no-store' });
      return (/const VERSION = '([^']+)'/.exec(await r.text()) || [])[1] || '';
    } catch {
      return ''; // hors ligne : rien à annoncer
    }
  }
  async function check() {
    if (notified || !shown) return;
    const version = await online();
    if (notified || !version || version === shown) return;
    notified = true;
    const box = document.createElement('div');
    box.className = 'app-update';
    box.setAttribute('role', 'status');
    const label = document.createElement('span');
    label.textContent = 'Une nouvelle version est disponible.';
    const button = document.createElement('button');
    button.type = 'button';
    button.textContent = 'Mettre à jour';
    button.addEventListener('click', () => {
      button.disabled = true;
      location.reload();
    });
    const note = document.createElement('small');
    note.textContent = 'Terminez votre estimation avant de recharger.';
    box.append(label, button, note);
    document.querySelector('main').prepend(box);
  }
  navigator.serviceWorker
    .register('./sw.js', { updateViaCache: 'none' })
    .then(reg => {
      registration = reg;
      reg.update().catch(() => {});
    })
    .catch(() => {});
  check();
  // Les applications ouvertes depuis l’écran d’accueil peuvent rester longtemps en mémoire.
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState !== 'visible') return;
    registration?.update().catch(() => {});
    check();
  });
})();
