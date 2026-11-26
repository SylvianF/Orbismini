(() => {
  'use strict';
  const money = n =>
    Number.isFinite(n) ? n.toLocaleString('fr-FR', { style: 'currency', currency: 'EUR' }) : '—';
  const dialog = document.createElement('dialog');
  dialog.id = 'client-print-dialog';
  dialog.innerHTML =
    '<form><h2>Imprimer l’estimation</h2><label>Nom et prénom<input name="client" autocomplete="off"></label><label>Téléphone<input name="phone" type="tel" autocomplete="off"></label><label>Adresse e-mail<input name="email" type="email" autocomplete="off"></label><label class="print-check"><input name="internal" type="checkbox">Imprimer les pourcentages FC / GtaX</label><div id="print-proposition" hidden><p class="print-agency-title">Agence de la proposition</p><div class="print-agencies" role="group"><button type="button" data-agence="Troyes">Troyes</button><button type="button" data-agence="Nancy">Nancy</button><button type="button" data-agence="Calais">Calais</button></div><label>Votre contact<input name="contact" autocomplete="off" placeholder="Prénom et téléphone de l’agence"></label></div><p id="print-error" role="alert"></p><div class="print-actions"><button type="button" id="print-cancel" class="secondary">Annuler</button><button type="button" id="print-send" class="secondary" hidden>Envoyer au client</button><button type="submit">Imprimer</button></div></form>';
  document.body.append(dialog);
  const sheet = document.createElement('article');
  sheet.id = 'client-print-sheet';
  document.body.append(sheet);
  const form = dialog.querySelector('form');
  function element(tag, text, parent, className) {
    const el = document.createElement(tag);
    if (text !== null) el.textContent = text;
    if (className) el.className = className;
    parent.append(el);
    return el;
  }
  function build(rows, now = new Date()) {
    sheet.replaceChildren();
    sheet.className =
      (form.elements.internal.checked ? 'with-internals ' : '') +
      (rows.length <= 4 ? 'print-short' : rows.length <= 7 ? 'print-medium' : 'print-compact');
    sheet.dataset.lineCount = rows.length;
    const header = element('header', null, sheet),
      brand = element('div', null, header),
      logo = element('img', null, brand);
    logo.src = 'logo-cndo.png';
    logo.alt = 'Comptoir National de l’Or';
    const dateFmt = new Intl.DateTimeFormat('fr-FR', {
      timeZone: 'Europe/Paris',
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
    element('p', 'Établie le ' + dateFmt.format(now) + ' (Paris)', header);
    element('h1', 'Estimation de rachat', sheet);
    const customer = element('section', null, sheet, 'print-customer');
    element('strong', form.elements.client.value.trim() || 'Client', customer);
    element(
      'p',
      [form.elements.phone.value.trim(), form.elements.email.value.trim()]
        .filter(Boolean)
        .join(' · '),
      customer
    );
    const table = element('table', null, sheet),
      thead = element('thead', null, table),
      head = element('tr', null, thead);
    for (const title of [
      'Désignation',
      'Qté / poids',
      'P.U. avant taxes',
      'Total avant taxes',
      'Taxe',
      'Net client',
    ])
      element('th', title, head);
    const tbody = element('tbody', null, table);
    let gross = 0,
      net = 0,
      tax = 0;
    const groups = new Map();
    for (const row of rows) {
      const c = row.result;
      gross += c.gross;
      net += c.net;
      tax += c.tax;
      const groupLabel = c.taxLabel,
        rate = c.taxRate;
      let group = groups.get(groupLabel);
      if (!group) {
        group = { label: groupLabel, rate, base: 0, tax: 0 };
        groups.set(groupLabel, group);
      }
      group.base += c.taxBase;
      group.tax += c.tax;
      const tr = element('tr', null, tbody),
        name = element('td', null, tr);
      element('strong', row.name, name);
      element('small', [row.titre, row.mode].filter(Boolean).join(' · '), name);
      if (form.elements.internal.checked)
        element(
          'small',
          row.percentage +
            ' : ' +
            (Number.isFinite(row.percent) ? row.percent.toFixed(2).replace('.', ',') + ' %' : '—'),
          name
        );
      element('td', row.quantity, tr);
      element('td', money(c.gross / row.count), tr);
      element('td', money(c.gross), tr);
      const taxCell = element('td', null, tr);
      element(
        'small',
        groupLabel + (rate ? ' ' + (rate * 100).toLocaleString('fr-FR') + ' %' : ''),
        taxCell
      );
      element('span', c.tax ? '-' + money(c.tax) : money(0), taxCell);
      element('td', money(c.net), tr);
    }
    const recap = element('div', null, sheet, 'print-recap'),
      taxBox = element('section', null, recap, 'print-tax-summary');
    element('h2', 'Récapitulatif des taxes', taxBox);
    const taxTable = element('table', null, taxBox),
      taxHead = element('tr', null, element('thead', null, taxTable));
    for (const title of ['Taxe', 'Taux', 'Base', 'Montant']) element('th', title, taxHead);
    const taxBody = element('tbody', null, taxTable);
    for (const group of groups.values()) {
      const tr = element('tr', null, taxBody);
      for (const text of [
        group.label,
        (group.rate * 100).toLocaleString('fr-FR') + ' %',
        money(group.base),
        group.tax ? '-' + money(group.tax) : money(0),
      ])
        element('td', text, tr);
    }
    if (groups.has('TPV'))
      element('small', 'Base TPV : plus-value imposable après abattement de détention.', taxBox);
    const totals = element('section', null, recap, 'print-totals');
    for (const [label, value] of [
      ['Total avant taxes', gross],
      ['Total des taxes', tax ? -tax : 0],
      ['Net à verser au client', net],
    ]) {
      const p = element('p', null, totals);
      element('span', label, p);
      element('strong', money(value), p);
    }
    const footer = element('footer', null, sheet);
    element(
      'p',
      'Les cours de l’or évoluant, cette estimation est valable uniquement pendant 2 heures à compter de son établissement.',
      footer
    );
    element(
      'p',
      'Valable jusqu’au ' +
        dateFmt.format(new Date(now.getTime() + 7200000)) +
        ' (heure de Paris).',
      footer
    );
  }
  document.getElementById('est-print').addEventListener('click', () => {
    form.elements.internal.checked = false;
    document.getElementById('print-error').textContent = '';
    dialog.showModal();
  });
  document.getElementById('print-cancel').onclick = () => dialog.close();
  // Fiche prête (lignes complètes, logo chargé) : vrai ; sinon le message d'erreur est affiché.
  async function prepare() {
    const rows = window.GoldEstimate.snapshot();
    if (!rows.length || rows.some(r => !r.result)) {
      document.getElementById('print-error').textContent =
        'Complète toutes les lignes avant d’imprimer.';
      return false;
    }
    build(rows);
    const image = sheet.querySelector('img');
    try {
      await image.decode();
    } catch {
      document.getElementById('print-error').textContent =
        'Le logo n’a pas pu être chargé. Réessaie après actualisation.';
      return false;
    }
    return true;
  }
  form.addEventListener('submit', async e => {
    e.preventDefault();
    if (!(await prepare())) return;
    dialog.close();
    window.print();
  });
  // Application iPhone : « Envoyer au client » demande au serveur la Proposition de rachat d'Orbis
  // (même PDF qu'au comptoir, proposition.py), puis l'application ouvre un SMS ou un e-mail adressé
  // au client. Agence et contact retenus sur ce téléphone. Jamais les pourcentages internes.
  const share = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.partager;
  const send = document.getElementById('print-send');
  const KEPT = 'orbismini-proposition';
  const kept = () => {
    try {
      return JSON.parse(localStorage.getItem(KEPT) || '{}') || {};
    } catch {
      return {};
    }
  };
  const keep = v => {
    try {
      localStorage.setItem(KEPT, JSON.stringify({ ...kept(), ...v }));
    } catch {}
  };
  const agencies = [...dialog.querySelectorAll('[data-agence]')];
  const showAgency = name => agencies.forEach(b => b.classList.toggle('chosen', b.dataset.agence === name));
  agencies.forEach(b =>
    b.addEventListener('click', () => {
      keep({ agence: b.dataset.agence });
      showAgency(b.dataset.agence);
    })
  );
  const toBase64 = blob =>
    new Promise((ok, ko) => {
      const reader = new FileReader();
      reader.onload = () => ok(String(reader.result).split(',')[1] || '');
      reader.onerror = () => ko(new Error('PDF illisible'));
      reader.readAsDataURL(blob);
    });
  if (share) {
    send.hidden = false;
    document.getElementById('print-proposition').hidden = false;
    document.getElementById('est-print').addEventListener('click', () => {
      showAgency(kept().agence);
      form.elements.contact.value = kept().contact || '';
    });
    send.addEventListener('click', async () => {
      const say = text => (document.getElementById('print-error').textContent = text);
      const rows = window.GoldEstimate.snapshot();
      const client = form.elements.client.value.trim();
      const agence = kept().agence;
      if (!rows.length || rows.some(r => !r.result)) return say('Complète toutes les lignes avant d’envoyer.');
      if (!client) return say('Indique le nom du client.');
      if (!agence) return say('Choisis l’agence de la proposition.');
      const contact = form.elements.contact.value.trim();
      keep({ contact });
      send.disabled = true;
      send.textContent = 'Préparation…';
      try {
        const r = await fetch('/api/proposition', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          cache: 'no-store',
          body: JSON.stringify({
            agence,
            contact,
            client: { name: client, phone: form.elements.phone.value.trim(), email: form.elements.email.value.trim() },
            rows: rows.map(({ fcNet, ...row }) => row),
          }),
        });
        // 503 : PDF d'Orbis pas encore possible (mentions des agences, reportlab) : la fiche imprimable
        // sert de secours, faite en PDF par l'application.
        if (!r.ok && r.status !== 503)
          throw Error((await r.json().catch(() => ({}))).error || 'Orbismini ne répond pas (' + r.status + ')');
        const pdf = r.ok ? await toBase64(await r.blob()) : '';
        // Fiche imprimable aussi prête : une application pas encore à jour en fait elle-même le PDF.
        form.elements.internal.checked = false;
        if (!(await prepare())) return;
        dialog.close();
        share.postMessage({
          pdf,
          client,
          phone: form.elements.phone.value.trim(),
          email: form.elements.email.value.trim(),
        });
        // Trace dans « Dernières propositions » d'Orbis, par les PC jumelés (ticket.js) ; sans PC
        // jumelé, rien à faire : l'envoi au client ne dépend pas d'elle.
        window.OrbisminiPropositions?.envoyer({
          city: agence,
          contact,
          client: { name: client, phone: form.elements.phone.value.trim(), email: form.elements.email.value.trim() },
          rows: rows.map(({ fcNet, ...row }) => row),
        }).catch(() => {});
      } catch (e) {
        say(e.message || 'Envoi impossible');
      } finally {
        send.disabled = false;
        send.textContent = 'Envoyer au client';
      }
    });
  }
  document.getElementById('est-reset').addEventListener('click', () => {
    form.reset();
    sheet.replaceChildren();
  });
  // Conserver le document : certains navigateurs signalent afterprint avant la fin de la capture.
})();
