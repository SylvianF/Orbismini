// Chiffres d'Orbis sur le téléphone : achats, marge, ventes, marge réelle de la ville choisie,
// aujourd'hui et sur le mois. Seulement ce que Sylvian a coché pour ce téléphone dans Orbis
// (Réglages › Téléphones) : Orbis applique les droits, le relais de chaque PC jumelé chiffre le
// paquet avec une clé tirée du secret de ce téléphone (jumelage des tickets) et le dépose dans sa
// boîte sur Orbismini, qui ne peut pas le lire. Le paquet le plus récent (« at ») l'emporte.
// L'onglet n'apparaît que sur un téléphone qui a reçu des chiffres.
(() => {
  'use strict';
  const view = document.getElementById('view-chiffres'),
    tab = document.querySelector('button[data-view="chiffres"]');
  if (!view || !tab) return;
  const SEEN = 'orbismini-chiffres',
    CITY = 'orbismini-chiffres-ville';
  const el = (tag, props = {}, ...kids) => {
    const e = Object.assign(document.createElement(tag), props);
    e.append(...kids.filter(k => k != null && k !== ''));
    return e;
  };
  const enc = s => new TextEncoder().encode(s);
  const hex = buf => [...new Uint8Array(buf)].map(x => x.toString(16).padStart(2, '0')).join('');
  const unb64 = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));
  const euro = v =>
    Number(v).toLocaleString('fr-FR', { style: 'currency', currency: 'EUR', minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const grams = v => Number(v).toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' g';
  const store = (k, v) => {
    try {
      v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v);
    } catch {}
  };
  const read = k => {
    try {
      return localStorage.getItem(k);
    } catch {
      return null;
    }
  };
  if (read(SEEN)) tab.hidden = false;

  // Clé et boîte de chaque PC jumelé (même calcul que orbiscan_tickets.py du relais).
  async function hmac(secret, label) {
    const k = await crypto.subtle.importKey('raw', unb64(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    return crypto.subtle.sign('HMAC', k, enc(label));
  }
  async function boxes() {
    let links = {};
    try {
      links = JSON.parse(read('orbismini-tickets') || '{}').links || {};
    } catch {}
    return Promise.all(
      Object.values(links).map(async l => ({ box: hex(await hmac(l.secret, 'chiffres-boite')), key: await hmac(l.secret, 'chiffres-cle') }))
    );
  }
  let data = null,
    error = '';
  async function load() {
    try {
      const list = await boxes();
      if (!list.length) return;
      const r = await fetch('/api/chiffres?boxes=' + list.map(b => b.box).join(','), { cache: 'no-store' });
      if (!r.ok) throw Error('Orbismini ne répond pas (' + r.status + ')');
      const got = (await r.json()).boxes || {};
      let best = null;
      for (const b of list) {
        if (!got[b.box]) continue;
        try {
          const blob = unb64(got[b.box]); // OSC2 | iv (12) | chiffré + étiquette
          if (String.fromCharCode(...blob.subarray(0, 4)) !== 'OSC2') continue;
          const key = await crypto.subtle.importKey('raw', b.key, 'AES-GCM', false, ['decrypt']);
          const plain = await crypto.subtle.decrypt(
            { name: 'AES-GCM', iv: blob.subarray(4, 16), additionalData: enc('chiffres1|' + b.box) },
            key,
            blob.subarray(16)
          );
          const d = JSON.parse(new TextDecoder().decode(plain));
          if (d && d.format === 1 && d.cities && (!best || String(d.at) > String(best.at))) best = d;
        } catch {
          /* paquet illisible (PC remis à zéro…) : ignoré */
        }
      }
      error = '';
      // Rien reçu (Orbismini redémarré : le prochain envoi d'Orbis arrive dans 5 minutes au plus) :
      // on garde ce qu'on a.
      if (best) {
        data = best;
        tab.hidden = false;
        store(SEEN, '1');
      }
    } catch (e) {
      error = e.message || 'Chiffres indisponibles';
    }
    if (document.body.dataset.view === 'chiffres') draw();
  }

  function rows(block) {
    const out = [];
    const row = (label, value, cls = '') => out.push(el('div', { className: 'ch-row ' + cls }, el('span', { textContent: label }), el('b', { textContent: value })));
    if (block.achats) {
      const a = block.achats;
      row('Achats', a.count + ' achat' + (a.count > 1 ? 's' : '') + (a.weight != null ? ' · ' + grams(a.weight) : ''));
      row('Achats taxe comprise', euro(a.ht));
      row('Net payé aux clients', euro(a.ttc));
    }
    if (block.marge != null) row('Marge théorique', euro(block.marge), 'ch-margin' + (Number(block.marge) < 0 ? ' ch-neg' : ''));
    if (block.ventes) {
      const v = block.ventes;
      row('Ventes', v.count + ' vente' + (v.count > 1 ? 's' : ''));
      row('Ventes HT', euro(v.ht));
      row('Ventes TTC', euro(v.ttc));
    }
    if (block.margeReelle != null)
      row('Marge réelle', euro(block.margeReelle), 'ch-margin' + (Number(block.margeReelle) < 0 ? ' ch-neg' : ''));
    return out;
  }

  function draw() {
    if (!data) {
      view.replaceChildren(
        el('section', { className: 'section' }, el('div', { className: 'eyebrow', textContent: 'CHIFFRES' }),
          el('p', { className: 'small', textContent: error || 'Chiffres pas encore reçus.' }))
      );
      return;
    }
    const cities = Object.keys(data.cities).sort();
    let city = read(CITY);
    if (!cities.includes(city)) city = cities[0];
    const c = data.cities[city] || {};
    const age = (Date.now() - Date.parse(data.at)) / 60000;
    const when = new Date(data.at).toLocaleString('fr-FR', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
    const pick = el(
      'div',
      { className: 'tk-cities ch-cities', role: 'group' },
      ...cities.map(name =>
        el('button', {
          type: 'button',
          textContent: name,
          className: name === city ? 'chosen' : '',
          onclick: () => {
            store(CITY, name);
            draw();
          },
        })
      )
    );
    const day = c.day ? new Date(c.day + 'T12:00').toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' }) : '';
    view.replaceChildren(
      el(
        'section',
        { className: 'section' },
        el('div', { className: 'eyebrow', textContent: 'CHIFFRES D’ORBIS' }),
        cities.length > 1 ? pick : el('h2', { className: 'ch-city', textContent: city }),
        el('p', { className: 'small' + (age > 30 ? ' ch-old' : ''), textContent: (age > 30 ? '⚠ Pas mis à jour depuis plus de 30 minutes · ' : 'Mis à jour ') + 'le ' + when + (error ? ' · ' + error : '') })
      ),
      el(
        'section',
        { className: 'section' },
        el('h3', { className: 'list-heading', textContent: 'Aujourd’hui' + (day ? ' · ' + day : '') }),
        ...(c.today ? rows(c.today) : [el('p', { className: 'small', textContent: 'Clôture du jour pas encore lue.' })])
      ),
      c.month
        ? el(
            'section',
            { className: 'section' },
            el('h3', { className: 'list-heading', textContent: 'Mois en cours' + (c.month.days ? ' · ' + c.month.days + ' jour' + (c.month.days > 1 ? 's' : '') : '') }),
            ...rows(c.month)
          )
        : null
    );
  }

  window.addEventListener('view-changed', () => document.body.dataset.view === 'chiffres' && (draw(), load()));
  document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && load());
  setInterval(() => document.visibilityState === 'visible' && document.body.dataset.view === 'chiffres' && load(), 60000);
  load();
})();
