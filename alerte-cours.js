// Alerte de cours de l’or : propre à chaque téléphone (ses seuils, son canal ntfy), ou commune avec
// Orbis pour le téléphone relié avec le code de Sylvian (alerte_appareils.py).
// Le serveur contrôle le cours toutes les 10 minutes et prévient le téléphone par l’appli ntfy.
(() => {
  'use strict';
  const box = document.getElementById('gold-alert');
  if (!box) return;
  const el = (tag, props = {}, ...kids) => {
    const e = Object.assign(document.createElement(tag), props);
    e.append(...kids.filter(k => k != null && k !== ''));
    return e;
  };
  const kilo = v => Math.round(v).toLocaleString('fr-FR') + ' €/kg';
  const level = (v, dir) => (dir === 'above' ? 'au-dessus de ' : 'en dessous de ') + kilo(v);
  const pct = v => (Math.round(v * 10) / 10).toLocaleString('fr-FR') + ' %';
  // « en hausse de 2,3 % sur 24 h » (variation) ou « au-dessus de 120 000 €/kg » (seuil).
  const what = h => (h.dir === 'up' || h.dir === 'down'
    ? 'en ' + (h.dir === 'up' ? 'hausse' : 'baisse') + ' de ' + pct(Math.abs(h.change || 0)) + ' sur 24 h'
    : level(h.level, h.dir));
  const when = iso =>
    new Date(iso).toLocaleString('fr-FR', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
  const KEY = 'orapp-alerte';
  // Identifiant secret de ce téléphone, tiré une fois (envoyé seulement à Orbismini).
  const device = (() => {
    try {
      let id = localStorage.getItem('orbismini-appareil');
      if (!/^[0-9a-f]{32}$/.test(id || '')) {
        id = [...crypto.getRandomValues(new Uint8Array(16))].map(x => x.toString(16).padStart(2, '0')).join('');
        localStorage.setItem('orbismini-appareil', id);
      }
      return id;
    } catch {
      return '';
    }
  })();
  let state = null;

  async function call(body, path = '/api/alert') {
    const headers = { 'X-Appareil': device };
    if (body) headers['Content-Type'] = 'application/json';
    const r = await fetch(path, body
      ? { method: 'POST', headers, body: JSON.stringify(body), cache: 'no-store' }
      : { headers, cache: 'no-store' });
    const data = await r.json();
    if (!r.ok) throw Error(data.error || 'HTTP ' + r.status);
    state = data;
    if (data.mode !== 'appareil')
      try {
        localStorage.setItem(KEY, JSON.stringify({ above: data.above, below: data.below, move: data.move, updated: data.updated, hits: data.hits }));
      } catch {}
    return data;
  }

  // Alerte d’Orbis : après un redémarrage du serveur, l’état gardé sur l’iPhone est renvoyé
  // (le plus récent l’emporte). L’alerte propre au téléphone, elle, est gardée sur GitHub.
  async function load() {
    let error = '';
    try {
      await call();
      const kept = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (state.mode !== 'appareil' && kept?.updated && (!state.updated || kept.updated > state.updated)) await call(kept);
    } catch (e) {
      error = e.message;
    }
    draw(error, !!error);
  }

  function draw(message, bad) {
    const a = state;
    box.hidden = !a;
    if (!a) return;
    const own = a.mode === 'appareil';
    const field = (name, label) => {
      const input = el('input', {
        name,
        inputMode: 'numeric',
        placeholder: '—',
        value: a[name] ? Math.round(a[name]).toLocaleString('fr-FR') : '',
      });
      input.setAttribute('aria-label', 'Prévenir si l’or passe ' + label + ' (€/kg)');
      return el('label', {}, el('span', { textContent: label }), input, el('small', { textContent: '€/kg' }));
    };
    const msg = el('p', { className: 'small' + (bad ? ' ga-bad' : ''), textContent: message || '' });
    const refuse = text => {
      msg.className = 'small ga-bad';
      msg.textContent = text;
    };
    const send = async (above, below, move, done) => {
      try {
        await call({ above, below, move, updated: new Date().toISOString(), hits: a.hits || [] });
        draw(done);
      } catch (e) {
        refuse(e.message);
      }
    };
    const form = el('form', { className: 'ga-form' },
      field('above', 'Au-dessus de'),
      field('below', 'En dessous de'),
      (() => {
        const input = el('input', { name: 'move', inputMode: 'decimal', placeholder: '—', value: a.move ? String(a.move).replace('.', ',') : '' });
        input.setAttribute('aria-label', 'Prévenir si l’or monte ou baisse de plus de (% sur 24 h)');
        return el('label', {}, el('span', { textContent: 'Hausse ou baisse de plus de' }), input, el('small', { textContent: '% sur 24 h' }));
      })(),
      el('div', { className: 'ga-buttons' },
        el('button', { type: 'submit', className: 'primary', textContent: 'Enregistrer' }),
        a.above || a.below || a.move
          ? el('button', { type: 'button', className: 'secondary', textContent: 'Retirer', onclick: () => send(null, null, null, 'Alerte retirée.') })
          : null));
    form.onsubmit = e => {
      e.preventDefault();
      const read = name => {
        const t = form.elements[name].value.replace(/[\s\u202f\u00a0€]/g, '').replace(',', '.');
        return t ? Number(t) : null;
      };
      const above = read('above'),
        below = read('below'),
        move = read('move');
      if ([above, below].some(v => v != null && !(v > 1000))) return refuse('Saisir un cours en euros par kilo, par exemple 120 000.');
      if (move != null && !(move >= 0.5 && move <= 20)) return refuse('Saisir une variation entre 0,5 et 20 %, par exemple 2.');
      if (a.price && above != null && above <= a.price) return refuse('Le cours est déjà au-dessus de ' + kilo(above) + ' : choisir un seuil plus haut.');
      if (a.price && below != null && below >= a.price) return refuse('Le cours est déjà en dessous de ' + kilo(below) + ' : choisir un seuil plus bas.');
      send(above, below, move, !(above || below || move) ? 'Alerte retirée.'
        : own ? 'Alerte enregistrée pour ce téléphone.' : 'Alerte enregistrée, aussi pour les postes d’Orbis.');
    };
    const active = [a.above && level(a.above, 'above'), a.below && level(a.below, 'below'),
      a.move && 'en cas de hausse ou de baisse de plus de ' + pct(a.move) + ' sur 24 h'].filter(Boolean);
    const last = a.hits?.at(-1);
    const copy = el('button', { type: 'button', className: 'secondary', textContent: 'Copier le nom du canal' });
    copy.onclick = async () => {
      try {
        await navigator.clipboard.writeText(a.channel);
        copy.textContent = 'Copié ✓';
      } catch {
        copy.textContent = a.channel;
      }
    };
    box.replaceChildren(...[
      el('div', { className: 'eyebrow', textContent: 'ALERTE DE COURS' }),
      a.price ? el('p', { className: 'small', textContent: 'Cours actuel : ' + kilo(a.price) }) : null,
      form,
      msg,
      el('p', {
        className: 'small' + (active.length ? ' ga-on' : ''),
        textContent: active.length
          ? '🔔 Active : prévenir ' + active.join(' ou ') + '. ' +
            (own ? 'Alerte propre à ce téléphone' : 'Mêmes réglages sur les postes d’Orbis') +
            ' ; un seuil sonne une fois, la variation reste surveillée (une alerte par sens et par jour au plus).'
          : own
            ? 'Aucune alerte en place. L’alerte réglée ici est propre à ce téléphone : les autres ne la voient pas et ne la reçoivent pas.'
            : 'Aucune alerte en place. Les réglages faits ici valent aussi pour les postes d’Orbis.',
      }),
      last ? el('p', { className: 'small', textContent: 'Dernière alerte : or ' + what(last) + ', le ' + when(last.at) + ' (' + kilo(last.price) + ').' }) : null,
      a.channel
        ? el('details', { className: 'ga-help' },
            el('summary', { textContent: 'Recevoir l’alerte sur ce téléphone' }),
            el('p', { className: 'small', textContent:
              'Installe l’appli gratuite « ntfy » depuis l’App Store, touche « + », puis abonne-toi au canal ci-dessous (serveur ntfy.sh, celui par défaut). ' +
              'La notification arrive même Orbismini fermée. Le cours est contrôlé toutes les 10 minutes en semaine.' }),
            el('p', { className: 'ga-channel', textContent: a.channel }),
            copy)
        : null,
      linkBox(own),
    ].filter(Boolean));
  }

  // Alerte d’Orbis : ce téléphone s’y relie avec le code de Sylvian, ou reprend la sienne.
  function linkBox(own) {
    const msg = el('p', { className: 'small' });
    const go = async (path, body, done) => {
      try {
        await call(body, path);
        draw(done);
      } catch (e) {
        msg.className = 'small ga-bad';
        msg.textContent = e.message;
      }
    };
    if (!own)
      return el('details', { className: 'ga-help' },
        el('summary', { textContent: 'Ce téléphone suit l’alerte d’Orbis' }),
        el('p', { className: 'small', textContent: 'Les seuils sont communs avec les postes d’Orbis. Tu peux reprendre une alerte propre à ce téléphone, avec un autre canal ntfy.' }),
        el('button', { type: 'button', className: 'secondary', textContent: 'Alerte propre à ce téléphone',
          onclick: () => go('/api/alert/detacher', {}, 'Ce téléphone a maintenant sa propre alerte.') }),
        msg);
    const code = el('input', { type: 'password', placeholder: 'Code de Sylvian', autocomplete: 'off' });
    const form = el('form', { className: 'ga-link' }, code,
      el('button', { type: 'submit', className: 'secondary', textContent: 'Relier' }));
    form.onsubmit = e => {
      e.preventDefault();
      if (code.value) go('/api/alert/lier', { code: code.value }, 'Ce téléphone suit maintenant l’alerte d’Orbis.');
    };
    return el('details', { className: 'ga-help' },
      el('summary', { textContent: 'Suivre l’alerte d’Orbis' }),
      el('p', { className: 'small', textContent: 'Réservé à Sylvian : mêmes seuils que les postes d’Orbis, avec son code.' }),
      form, msg);
  }

  const visible = () => document.body.dataset.view === 'meteo';
  window.addEventListener('view-changed', () => visible() && load());
  if (visible()) load();
})();
