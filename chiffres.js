// Chiffres d'Orbis sur le téléphone : achats, marge, ventes, marge réelle de la ville choisie,
// aujourd'hui et sur le mois. Seulement ce que Sylvian a coché pour ce téléphone dans Orbis
// (Réglages › Téléphones) : Orbis applique les droits, le relais de chaque PC jumelé chiffre le
// paquet avec une clé tirée du secret de ce téléphone (jumelage des tickets) et le dépose dans sa
// boîte sur Orbismini, qui ne peut pas le lire. Le paquet le plus récent (« at ») l'emporte.
// L'onglet n'apparaît que sur un téléphone qui a reçu des chiffres.
// Sous les chiffres, la VD en cours de la ville (droit « VD en cours » dans Orbis).
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
  const opened = new Set(); // lignes déroulées (Achats, Ventes), gardées d'un affichage à l'autre
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
      // Rien reçu (Orbismini redémarré : le prochain envoi d'Orbis arrive dans 5 minutes au plus) :
      // on garde ce qu'on a.
      const before = [data?.at, error];
      if (best) {
        data = best;
        tab.hidden = false;
        store(SEEN, '1');
      }
      error = '';
      // Rien de nouveau (contrôle de chaque minute) : l'écran n'est pas redessiné, rien ne se replie.
      const old = data && Date.now() - Date.parse(data.at) > 30 * 60000; // l'alerte « plus de 30 minutes » doit paraître
      if (before[0] === data?.at && !before[1] && !old) return;
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
  // Case : intitulé, valeur, classe, et une petite ligne dessous (cours retenu, comme l'Accueil d'Orbis).
  const cell = ([k, v, cls, sub]) =>
    el('span', { className: cls || '' }, el('small', { textContent: k }), el('b', { textContent: v }), sub ? el('small', { textContent: sub }) : null);
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
      ['% GtaX', l.gtax != null ? pct(l.gtax) : null, '', l.gtax != null && l.cours != null ? 'Cours ' + Number(l.cours).toLocaleString('fr-FR', { maximumFractionDigits: 2 }) : ''],
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
    // Une ligne repliée par transaction : heure, net payé (ou total), marge ; les objets en dépliant.
    return [...groups.values()].map((g, i) => {
      const total = buy ? sum(g, 'net') : sum(g, 'total');
      const gain = buy ? sum(g, 'theory') : sum(g, 'margin');
      const key = (buy ? 'achat:' : 'vente:') + (g[0].cadre ?? 'ligne' + i);
      return el(
        'details',
        {
          className: 'ch-obj ch-tx',
          open: opened.has(key),
          ontoggle: e => (e.target.open ? opened.add(key) : opened.delete(key)),
        },
        el(
          'summary',
          { className: 'ch-obj-head' },
          el('small', { className: 'ch-tx-time', textContent: g[0].at ? time(g[0].at) : '' }),
          el(
            'span',
            { className: 'ch-tx-sum' },
            total != null ? el('b', { textContent: (buy ? 'Net payé ' : 'Total TTC ') + euro(total) }) : null,
            gain != null
              ? el('span', { className: margin(gain) }, el('small', { textContent: buy ? 'Marge théo. ' : 'Marge ' }), el('b', { textContent: euro(gain) }))
              : null
          ),
          chevron()
        ),
        ...g.map(buy ? buyItem : saleItem)
      );
    });
  }
  // Chevron dessiné des lignes déroulables (pivote à l'ouverture).
  function chevron() {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('aria-hidden', 'true');
    svg.classList.add('ch-chevron');
    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('d', 'M9 6l6 6-6 6');
    svg.append(path);
    return svg;
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
          {
            className: 'ch-fold',
            open: opened.has(label),
            ontoggle: e => (e.target.open ? opened.add(label) : opened.delete(label)),
          },
          el(
            'summary',
            { className: 'ch-row' },
            el('span', {}, label, el('small', { className: 'ch-count', textContent: ' · ' + new Set(lines.map((l, i) => l.cadre ?? 'ligne' + i)).size })),
            el('b', { textContent: value }),
            chevron()
          ),
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
    // Charges et résultat (Mois préc., Année ; droit propre dans Orbis).
    if (block.resultat) {
      money('Charges', block.resultat.charges);
      if (block.resultat.resultat != null) row('Résultat', euro(block.resultat.resultat), margin(block.resultat.resultat));
    }
    return out;
  }

  // VD en cours (bloc « vd » d'Orbis, chiffres_telephone.vd_block) : le lot qui attend de
  // partir chez CNDO, pas tout le stock. Valeur = paiement estimé au cours du moment. Orbis
  // calcule l'effet du cours : onePercent (ce que 1 % d'or fait gagner ou perdre au lot) et
  // dayEffect (ce que la variation de l'or sur 24 h lui a déjà fait gagner ou perdre).
  const signed = v => (Number(v) > 0 ? '+ ' : Number(v) < 0 ? '− ' : '') + euro(Math.abs(Number(v)));
  const VD_LEVEL = {
    send: ['⚠ VD à envoyer à CNDO', 'ch-vd-send'],
    sell: ['VD prête : moment de vendre', 'ch-vd-sell'],
    wait: ['Rien ne presse', ''],
  };
  function vdSection(vd) {
    const out = [];
    const row = (label, value, cls = '') => out.push(el('div', { className: 'ch-row ' + cls }, el('span', { textContent: label }), el('b', { textContent: value })));
    const head = el('h3', { className: 'list-heading', textContent: 'VD en cours' + (vd.since ? ' · depuis l’envoi du ' + short(vd.since) : '') });
    const waiting = vd.retraction ? plural(vd.retraction, 'objet') + ' encore en délai de rétractation, hors du lot.' : '';
    if (!vd.count)
      return el('section', { className: 'section' }, head, el('p', { className: 'small', textContent: 'Aucun objet n’attend de partir chez CNDO.' + (waiting ? ' ' + waiting : '') }));
    const [level, cls] = VD_LEVEL[vd.level] || [];
    row('Lot', plural(vd.count, 'objet') + (vd.weight != null ? ' · ' + grams(vd.weight) : ''));
    if (Number(vd.fineGold) > 0) row('Or fin', grams(vd.fineGold));
    if (vd.value != null) row(vd.rate === 'last' ? 'Valeur au cours du dernier envoi' : 'Valeur au cours du jour', euro(vd.value));
    if (vd.margin != null) row('Marge estimée', euro(vd.margin), margin(vd.margin));
    if (Number(vd.onePercent) > 0) {
      row('Or + 1 %', 'VD ' + signed(vd.onePercent), margin(1));
      row('Or − 1 %', 'VD ' + signed(-vd.onePercent), margin(-1));
    }
    if (vd.change != null && vd.dayEffect != null)
      row('Or sur 24 h : ' + (Number(vd.change) > 0 ? '+ ' : Number(vd.change) < 0 ? '− ' : '') + pct(Math.abs(Number(vd.change))), 'VD ' + signed(vd.dayEffect), margin(vd.dayEffect));
    return el(
      'section',
      { className: 'section' },
      head,
      level ? el('p', { className: 'ch-vd-level ' + cls, textContent: level }) : null,
      ...out,
      waiting ? el('p', { className: 'small', textContent: waiting }) : null
    );
  }

  // Demandes de virement (bloc « virements » d'Orbis, virements_telephone.py) : demandes en attente
  // adressées aux personnes de ce téléphone, et résultat des marquages faits d'ici (« faits »). Le
  // virement se passe dans l'application de la banque ; ici on copie l'IBAN, puis « Virement fait »
  // part scellé vers les PC jumelés (ticket.js). Format : consigne-virements-telephone.md.
  const MARKS = 'orbismini-virements-envoyes'; // {rid: {id, qui, at}} : marquages en route
  const marks = () => {
    try {
      return JSON.parse(localStorage.getItem(MARKS) || '{}') || {};
    } catch {
      return {};
    }
  };
  const keepMarks = v => {
    try {
      localStorage.setItem(MARKS, JSON.stringify(v));
    } catch {}
  };
  async function copy(text, button) {
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const t = el('textarea', { value: text });
      document.body.append(t);
      t.select();
      document.execCommand('copy');
      t.remove();
    }
    const was = button.textContent;
    button.textContent = 'Copié ✓';
    setTimeout(() => (button.textContent = was), 1500);
  }
  const minutesOld = () => Math.max(0, Math.round((Date.now() - Date.parse(data.at)) / 60000));
  const ageText = () => {
    const m = minutesOld();
    return (m > 10 ? '⚠ Liste vieille de ' + m + ' min : vérifie dans Orbis avant de payer' : m < 1 ? 'Liste à jour à l’instant' : 'Liste à jour il y a ' + m + ' min');
  };
  function transferCard(d, mark) {
    const line = (label, value, extra) =>
      value ? el('div', { className: 'ch-row ch-tr-line' }, el('span', { textContent: label }), el('b', { textContent: value }), extra || null) : null;
    const copyButton = text => el('button', { type: 'button', className: 'ch-copy', textContent: 'Copier', onclick: e => copy(text, e.currentTarget) });
    const when = d.at ? new Date(d.at).toLocaleString('fr-FR', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : '';
    const status = el('p', { className: 'small ch-tr-status' });
    const actions = el('div', { className: 'ch-tr-actions' });
    const names = (d.qui || []).filter(Boolean);
    const done = async qui => {
      if (!window.OrbisminiCourrier) return (status.textContent = '✖ Envoi impossible depuis cette page.');
      if (!confirm('Virement de ' + euro(d.montant) + ' à ' + (d.client || 'ce client') + ' fait par ' + qui + ' ?')) return;
      actions.hidden = true;
      status.textContent = 'Envoi…';
      try {
        const id = await window.OrbisminiCourrier.virementFait(d.rid, qui);
        keepMarks({ ...marks(), [d.rid]: { id, qui, at: Date.now() } });
        status.textContent = 'Envoyé (' + qui + ') : la demande disparaîtra au prochain passage d’Orbis (une minute environ).';
      } catch (e) {
        actions.hidden = false;
        status.textContent = '✖ ' + (e.message || 'Envoi impossible');
      }
    };
    if (mark) {
      actions.hidden = true;
      status.textContent = 'Envoi en cours (' + mark.qui + ') : la demande disparaîtra au prochain passage d’Orbis.';
    } else if (names.length === 1) {
      actions.append(el('button', { type: 'button', className: 'primary', textContent: 'Virement fait', onclick: () => done(names[0]) }));
    } else {
      actions.append(...names.map(n => el('button', { type: 'button', className: 'primary', textContent: 'Fait par ' + n, onclick: () => done(n) })));
    }
    return el(
      'div',
      { className: 'ch-obj ch-tr' },
      el('div', { className: 'ch-obj-head' }, el('small', { textContent: [d.ville, when].filter(Boolean).join(' · ') }), el('b', { textContent: euro(d.montant) })),
      el('b', { className: 'ch-tr-client', textContent: d.client || '' }),
      d.alertes && d.alertes.length ? el('ul', { className: 'ch-tr-alerts' }, ...d.alertes.map(a => el('li', { textContent: '⚠ ' + a }))) : null,
      line('Ordre', d.ordre),
      line('Demandé par', d.by),
      line('Titulaire', d.titulaire),
      d.iban ? line('IBAN', d.ibanAffiche || d.iban, copyButton(d.iban)) : null,
      d.bic ? line('BIC', d.bic, copyButton(d.bic)) : null,
      d.banque
        ? el('p', {
            className: 'small',
            textContent:
              'Sans RIB : client déjà bénéficiaire à la banque' +
              (d.banque.day ? ' (dernier virement le ' + short(d.banque.day) + (d.banque.amount ? ', ' + euro(d.banque.amount) : '') + ')' : '') +
              '.',
          })
        : null,
      d.note ? el('p', { className: 'small ch-tr-note', textContent: 'Note : ' + d.note }) : null,
      status,
      actions
    );
  }
  function transfers(v) {
    if (!v) return null;
    const waiting = v.attente || [],
      answered = new Set((v.faits || []).map(f => f.id)),
      rids = new Set(waiting.map(d => d.rid)),
      kept = marks();
    // Marquage oublié quand la demande a quitté l'attente, qu'Orbis a répondu, ou après 2 jours.
    for (const [rid, m] of Object.entries(kept)) if (!rids.has(rid) || answered.has(m.id) || Date.now() - m.at > 2 * 86400e3) delete kept[rid];
    keepMarks(kept);
    const results = (v.faits || [])
      .filter(f => Date.now() - Date.parse(f.at) < 86400e3)
      .slice(-5)
      .reverse()
      .map(f => el('p', { className: 'ch-tr-result ' + (f.ok ? 'ok' : 'ko'), textContent: (f.ok ? '✓ ' : '✖ ') + (f.message || (f.ok ? 'Virement marqué fait par ' + f.qui + '.' : 'Marquage refusé.')) }));
    if (!waiting.length && !results.length && !(v.qui || []).length) return null;
    return el(
      'section',
      { className: 'section ch-transfers' },
      el('h3', { className: 'list-heading', textContent: 'Demandes de virement' + (waiting.length ? ' · ' + waiting.length : '') }),
      el('p', { className: 'small ch-tr-age' + (minutesOld() > 10 ? ' ch-old' : ''), textContent: ageText() }),
      ...(waiting.length ? waiting.map(d => transferCard(d, kept[d.rid])) : [el('p', { className: 'small', textContent: 'Aucune demande en attente.' })]),
      ...results
    );
  }
  // L'âge de la liste avance sans tout redessiner (les lignes ouvertes restent ouvertes).
  setInterval(() => {
    const age = view.querySelector('.ch-tr-age');
    if (age && data) {
      age.textContent = ageText();
      age.classList.toggle('ch-old', minutesOld() > 10);
    }
  }, 30000);

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
    if (!cities.length) {
      view.replaceChildren(
        ...[
          el('section', { className: 'section' }, el('div', { className: 'eyebrow', textContent: 'CHIFFRES D’ORBIS' }),
            el('p', { className: 'small', textContent: error || 'Pas de chiffres pour ce téléphone.' })),
          transfers(data.virements),
        ].filter(Boolean)
      );
      return;
    }
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
      transfers(data.virements),
      ...(c.periods ? cards(c) : []),
      c.vd ? vdSection(c.vd) : null,
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
        : null,
      ].filter(Boolean)
    );
  }

  window.addEventListener('view-changed', () => document.body.dataset.view === 'chiffres' && (draw(), load()));
  document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && load());
  setInterval(() => document.visibilityState === 'visible' && document.body.dataset.view === 'chiffres' && load(), 60000);
  load();
})();
