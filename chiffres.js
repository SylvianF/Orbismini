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

  // Lignes d'un bloc de chiffres ; group : un seul groupe (achats, marge, ventes, margeReelle).
  // source « exercice » (Mois, Mois préc., Année) : chiffres du tableau « Exercice comptable »
  // d'Orbis : achats HT, CA HT (envois compris), marge HT ; pas de TTC.
  // Détail du jour, un cadre par transaction (champ « cadre » d'Orbis, jamais affiché) : en tête
  // l'heure (achats) et le total ; dedans, chaque objet (mêmes colonnes que l'Accueil d'Orbis).
  const time = iso => new Date(iso).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  const fine = t => Number(t).toLocaleString('fr-FR', { maximumFractionDigits: 2 }) + ' ‰';
  const pct = v => Number(v).toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' %';
  const cell = ([k, v, cls]) => el('span', { className: cls || '' }, el('small', { textContent: k }), el('b', { textContent: v }));
  function item(l, note, cells) {
    const name = (l.count > 1 ? l.count + ' × ' : '') + (l.article || l.description || 'Objet');
    const facts = [l.titre ? fine(l.titre) : null, l.weight != null ? grams(l.weight) : null, note].filter(Boolean).join(' · ');
    return el(
      'div',
      { className: 'ch-item' },
      el('b', { textContent: name }),
      l.description && l.description !== l.article ? el('small', { className: 'ch-obj-desc', textContent: l.description }) : null,
      facts ? el('small', { className: 'ch-obj-desc', textContent: facts }) : null,
      el('div', { className: 'ch-obj-cells' }, ...cells.filter(c => c && c[1] != null).map(cell))
    );
  }
  const buyItem = l =>
    item(l, '', [
      ['Taxe comprise', l.gross != null ? euro(l.gross) : null],
      ['Net payé', l.net != null ? euro(l.net) : null],
      ['GtaX', l.gtax != null ? pct(l.gtax) : null],
      ['Marge théo.', l.theory != null ? euro(l.theory) : null, l.theory != null ? margin(l.theory) : ''],
    ]);
  const saleItem = l =>
    item(l, [l.to ? 'envoi à ' + l.to : '', l.purchaseDay ? 'acheté le ' + new Date(l.purchaseDay + 'T12:00').toLocaleDateString('fr-FR') : ''].filter(Boolean).join(' · '), [
      ['Vente TTC', l.total != null ? euro(l.total) : null],
      ['Marge HT', l.margin != null ? euro(l.margin) : null, l.margin != null ? margin(l.margin) : ''],
    ]);
  const sum = (lines, k) => (lines.some(l => l[k] != null) ? lines.reduce((n, l) => n + Number(l[k] || 0), 0) : null);
  function frames(lines, buy) {
    const groups = new Map();
    lines.forEach((l, i) => {
      const k = l.cadre ?? 'ligne' + i;
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push(l);
    });
    return [...groups.values()].map(g => {
      const total = buy ? sum(g, 'net') : sum(g, 'total');
      return el(
        'div',
        { className: 'ch-obj' },
        el(
          'div',
          { className: 'ch-obj-head' },
          el('small', { textContent: buy && g[0].at ? time(g[0].at) : '' }),
          total != null ? el('b', { textContent: (buy ? 'Net payé ' : 'Total TTC ') + euro(total) }) : null
        ),
        ...g.map(buy ? buyItem : saleItem)
      );
    });
  }
  const margin = v => 'ch-margin' + (Number(v) < 0 ? ' ch-neg' : '');

  function rows(block, group) {
    const out = [];
    const exercice = block.source === 'exercice';
    if (group) block = { [group]: block[group] };
    const row = (label, value, cls = '') => out.push(el('div', { className: 'ch-row ' + cls }, el('span', { textContent: label }), el('b', { textContent: value })));
    const money = (label, v, cls) => v != null && row(label, euro(v), cls);
    // Ligne « Achats » ou « Ventes » déroulable : détail objet par objet (Aujourd'hui, Hier),
    // comme le survol de l'Accueil d'Orbis.
    const unfold = (label, value, lines, card) => {
      if (!Array.isArray(lines) || !lines.length) return row(label, value);
      // Ventes : aux clients d'abord, puis les envois (GoldTrade, CNDO) sous « Envois ».
      const clients = lines.filter(l => !l.to),
        sent = lines.filter(l => l.to);
      const buy = card === 'achats';
      const list = [...frames(clients, buy), ...(sent.length ? [el('div', { className: 'ch-sub', textContent: 'Envois' }), ...frames(sent, buy)] : [])];
      out.push(
        el(
          'details',
          { className: 'ch-fold' },
          el('summary', { className: 'ch-row' }, el('span', { textContent: label }), el('b', { textContent: value })),
          el('div', { className: 'ch-lines' }, ...list)
        )
      );
    };
    if (block.achats) {
      const a = block.achats;
      if (a.count != null) unfold('Achats', a.count + ' achat' + (a.count > 1 ? 's' : '') + (a.weight != null ? ' · ' + grams(a.weight) : ''), a.lines, 'achats');
      money(exercice ? 'Achats HT' : 'Achats taxe comprise', a.ht);
      money('Net payé aux clients', a.ttc);
    }
    if (block.marge != null) row('Marge théorique', euro(block.marge), margin(block.marge));
    if (block.ventes) {
      const v = block.ventes;
      if (v.count != null) unfold('Ventes', v.count + ' vente' + (v.count > 1 ? 's' : ''), v.lines, 'ventes');
      money(exercice ? 'CA HT' : 'Ventes HT', v.ht);
      money('Ventes TTC', v.ttc);
    }
    if (block.margeReelle != null) row('Marge réelle', euro(block.margeReelle), margin(block.margeReelle));
    return out;
  }

  // Périodes envoyées par Orbis (Aujourd'hui… Année).
  const PERIODS = [
    ['today', 'Aujourd’hui'],
    ['yesterday', 'Hier'],
    ['month', 'Mois'],
    ['previousMonth', 'Mois préc.'],
    ['year', 'Année'],
  ];
  const CHOICE = 'orbismini-chiffres-periode';
  const short = d => new Date(d + 'T12:00').toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' });
  const dayName = d => new Date(d + 'T12:00').toLocaleDateString('fr-FR', { weekday: 'long' });
  const monthName = d => {
    const s = new Date(d + 'T12:00').toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' });
    return s[0].toUpperCase() + s.slice(1);
  };
  const plural = (n, w) => n + ' ' + w + (n > 1 ? 's' : '');
  function periodText(key, p) {
    if (!p) return key === 'today' ? 'Aujourd’hui : clôture du jour pas encore lue.' : 'Hier : pas encore de chiffres.';
    const days = p.days ? ', ' + plural(p.days, 'jour') + ' travaillé' + (p.days > 1 ? 's' : '') : '';
    if (key === 'today') return 'Aujourd’hui, ' + dayName(p.start) + ' ' + short(p.start);
    if (key === 'yesterday') return 'Hier, ' + dayName(p.start) + ' ' + short(p.start);
    if (key === 'month') return monthName(p.start) + ' (du ' + short(p.start) + ' au ' + short(p.end) + days + ')';
    if (key === 'previousMonth') return monthName(p.start) + ' (' + plural(p.days || 0, 'jour') + ' travaillé' + ((p.days || 0) > 1 ? 's' : '') + ')';
    return (p.label || 'Année en cours') + ' (depuis le ' + short(p.start) + days + ')';
  }
  // Un seul cadre : la période choisie en haut (retenue), toutes les lignes dessous.
  function cards(c) {
    const periods = c.periods;
    const saved = read(CHOICE);
    const key = PERIODS.some(([k]) => k === saved) ? saved : 'today';
    const p = periods[key];
    const buttons = el(
      'div',
      { className: 'ch-periods', role: 'group' },
      ...PERIODS.map(([k, label]) =>
        el('button', {
          type: 'button',
          textContent: label,
          className: k === key ? 'chosen' : '',
          onclick: () => {
            store(CHOICE, k);
            draw();
          },
        })
      )
    );
    const body = p ? rows(p) : [];
    return [
      el(
        'section',
        { className: 'section' },
        buttons,
        el('p', { className: 'small ch-when', textContent: periodText(key, p) }),
        ...(p && !body.length ? [el('p', { className: 'small', textContent: 'Rien pour cette période.' })] : body)
      ),
    ];
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
      ...[
      el(
        'section',
        { className: 'section' },
        el('div', { className: 'eyebrow', textContent: 'CHIFFRES D’ORBIS' }),
        cities.length > 1 ? pick : el('h2', { className: 'ch-city', textContent: city }),
        el('p', { className: 'small' + (age > 30 ? ' ch-old' : ''), textContent: (age > 30 ? '⚠ Pas mis à jour depuis plus de 30 minutes · ' : 'Mis à jour ') + 'le ' + when + (error ? ' · ' + error : '') })
      ),
      ...(c.periods ? cards(c) : []),
      c.periods
        ? null
        : el(
        'section',
        { className: 'section' },
        el('h3', { className: 'list-heading', textContent: 'Aujourd’hui' + (day ? ' · ' + day : '') }),
        ...(c.today ? rows(c.today) : [el('p', { className: 'small', textContent: 'Clôture du jour pas encore lue.' })])
      ),
      !c.periods && c.month
        ? el(
            'section',
            { className: 'section' },
            el('h3', { className: 'list-heading', textContent: 'Mois en cours' + (c.month.days ? ' · ' + c.month.days + ' jour' + (c.month.days > 1 ? 's' : '') : '') }),
            ...rows(c.month)
          )
        : null
      ].filter(Boolean)
    );
  }

  window.addEventListener('view-changed', () => document.body.dataset.view === 'chiffres' && (draw(), load()));
  document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && load());
  setInterval(() => document.visibilityState === 'visible' && document.body.dataset.view === 'chiffres' && load(), 60000);
  load();
})();
