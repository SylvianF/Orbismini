// Ticket de carburant envoyé depuis la pompe, rangé tout seul par Orbis dans « <Agence> - Orbis range ».
// Sur ce téléphone : photo recadrée sur la feuille A4 (scan-feuille.js) et remise au propre (comme
// scanLook d'Orbis), puis agence, montant et jour scellés ENSEMBLE pour chaque PC jumelé (sa clé
// publique, RSA-OAEP 2048 + AES-256-GCM) et signés avec le secret que seuls ce téléphone et ce PC
// connaissent (jumelage par le code à 2 chiffres affiché sur le PC). Orbismini (tickets_boite.py) ne
// garde qu'un paquet illisible ; le relais du PC refuse tout ticket mal signé.
// Le ticket scellé reste ici (IndexedDB) jusqu'à « rangé », et repart tout seul si Orbismini l'a perdu.
(() => {
  'use strict';
  const view = document.getElementById('view-ticket');
  if (!view) return;
  const CITIES = ['Nancy', 'Troyes', 'Calais'];
  // Type de dépense (nom du PDF dans Orbis : « Péage 20.11 (12,40€).pdf »…).
  const KINDS = { carburant: 'Carburant', peage: 'Péage', restaurant: 'Restaurant', parking: 'Parking' };
  const SETTINGS = 'orbismini-tickets';
  const el = (tag, props = {}, ...kids) => {
    const e = Object.assign(document.createElement(tag), props);
    e.append(...kids.filter(k => k != null && k !== ''));
    return e;
  };
  const bytes = s => new TextEncoder().encode(s);
  const hex = buf => [...new Uint8Array(buf)].map(x => x.toString(16).padStart(2, '0')).join('');
  const b64 = buf => {
    const u = new Uint8Array(buf);
    let s = '';
    for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000));
    return btoa(s);
  };
  const unb64 = s => Uint8Array.from(atob(s), c => c.charCodeAt(0));
  const euro = a => Number(a).toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' €';
  const dayText = d => new Date(d + 'T12:00').toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' });

  // Identifiant secret de ce téléphone (le même que pour l'alerte de cours).
  function device() {
    let id = localStorage.getItem('orbismini-appareil');
    if (!/^[0-9a-f]{32}$/.test(id || '')) {
      id = hex(crypto.getRandomValues(new Uint8Array(16)));
      localStorage.setItem('orbismini-appareil', id);
    }
    return id;
  }
  // Réglages : PC jumelés {pc: {name, key, secret}}, nom du téléphone, dernière agence.
  function settings() {
    try {
      const s = JSON.parse(localStorage.getItem(SETTINGS) || '{}');
      return {
        links: s.links || {},
        phoneName: s.phoneName || '',
        city: CITIES.includes(s.city) ? s.city : '',
        kind: KINDS[s.kind] ? s.kind : 'carburant',
      };
    } catch {
      return { links: {}, phoneName: '', city: '', kind: 'carburant' };
    }
  }
  const save = s => localStorage.setItem(SETTINGS, JSON.stringify(s));

  // ---------------------------------------------------------------- tickets en route (IndexedDB)
  function db() {
    return new Promise((ok, ko) => {
      const r = indexedDB.open('orbismini-tickets', 1);
      r.onupgradeneeded = () => r.result.createObjectStore('outbox', { keyPath: 'id' });
      r.onsuccess = () => ok(r.result);
      r.onerror = () => ko(r.error);
    });
  }
  async function store(mode, fn) {
    const d = await db();
    return new Promise((ok, ko) => {
      const tx = d.transaction('outbox', mode);
      const req = fn(tx.objectStore('outbox'));
      tx.oncomplete = () => ok(req?.result);
      tx.onerror = () => ko(tx.error);
    });
  }
  const outbox = () => store('readonly', s => s.getAll()).then(v => (v || []).sort((a, b) => a.created - b.created));
  const put = t => store('readwrite', s => s.put(t));
  const drop = id => store('readwrite', s => s.delete(id));

  // ---------------------------------------------------------------- chiffrement et signature
  // Même enveloppe que les photos d'Orbiscan : OSC1 | taille | clé AES enveloppée | iv | chiffré.
  async function seal(key, path, data) {
    const pub = await crypto.subtle.importKey(
      'jwk',
      { kty: 'RSA', n: key.n, e: key.e, alg: 'RSA-OAEP-256', ext: true },
      { name: 'RSA-OAEP', hash: 'SHA-256' },
      false,
      ['encrypt']
    );
    const aes = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, true, ['encrypt']);
    const wrapped = new Uint8Array(
      await crypto.subtle.encrypt({ name: 'RSA-OAEP' }, pub, await crypto.subtle.exportKey('raw', aes))
    );
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const sealed = new Uint8Array(
      await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: bytes(path) }, aes, data)
    );
    const head = new Uint8Array([79, 83, 67, 49, wrapped.length >> 8, wrapped.length & 255]);
    const out = new Uint8Array(head.length + wrapped.length + iv.length + sealed.length);
    out.set(head);
    out.set(wrapped, head.length);
    out.set(iv, head.length + wrapped.length);
    out.set(sealed, head.length + wrapped.length + iv.length);
    return out;
  }
  async function mac(secret, parts) {
    const k = await crypto.subtle.importKey('raw', unb64(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    return hex(await crypto.subtle.sign('HMAC', k, bytes(parts.join('|'))));
  }

  // ---------------------------------------------------------------- photo (comme Orbis)
  // Photo de facture remise au propre, comme un document scanné : niveaux de gris, fond
  // blanc uniforme (ombres et reflets du papier effacés, page par page), texte noir.
  // Le fond est estimé par blocs (le plus clair de chaque bloc, élargi et lissé), puis
  // chaque point est rapporté à ce fond. Renvoie le JPEG en base64.
  async function scanLook(src) {
    const img = new Image();
    // Chargement attendu par onload (decode() ne finit pas dans tous les navigateurs).
    const loaded = new Promise((ok, ko) => {
      img.onload = ok;
      img.onerror = () => ko(new Error('photo illisible'));
    });
    img.src = src;
    await loaded;
    // Feuille A4 blanche sous le ticket : photo recadrée sur la feuille (scan_feuille.js),
    // le ticket garde ainsi sa taille réelle dans le PDF.
    const canvas = window.GoldSheet
      ? window.GoldSheet.canvasOf(img, 2200)
      : (() => {
          const k = Math.min(1, 2200 / Math.max(img.naturalWidth, img.naturalHeight));
          const c = Object.assign(document.createElement('canvas'), {
            width: Math.max(1, Math.round(img.naturalWidth * k)),
            height: Math.max(1, Math.round(img.naturalHeight * k)),
          });
          c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
          return c;
        })();
    const w = canvas.width,
      h = canvas.height;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    const pixels = ctx.getImageData(0, 0, w, h);
    const p = pixels.data;
    const gray = new Float32Array(w * h);
    for (let i = 0, j = 0; j < gray.length; i += 4, j++) gray[j] = 0.299 * p[i] + 0.587 * p[i + 1] + 0.114 * p[i + 2];
    // Fond par blocs : le plus clair de chaque bloc (sur des moyennes 2 × 2, sans le grain).
    const size = Math.max(16, Math.round(Math.max(w, h) / 50));
    const bw = Math.ceil(w / size),
      bh = Math.ceil(h / size);
    let blocks = new Float32Array(bw * bh);
    for (let y = 0; y + 1 < h; y += 2)
      for (let x = 0; x + 1 < w; x += 2) {
        const v = (gray[y * w + x] + gray[y * w + x + 1] + gray[(y + 1) * w + x] + gray[(y + 1) * w + x + 1]) / 4;
        const b = Math.floor(y / size) * bw + Math.floor(x / size);
        if (v > blocks[b]) blocks[b] = v;
      }
    // Élargi (un bloc tout couvert d'encre prend le fond de ses voisins), puis lissé.
    const pass = reduce => {
      const out = new Float32Array(bw * bh);
      for (let by = 0; by < bh; by++)
        for (let bx = 0; bx < bw; bx++) {
          const near = [];
          for (let dy = -1; dy <= 1; dy++)
            for (let dx = -1; dx <= 1; dx++) {
              const yy = by + dy,
                xx = bx + dx;
              if (yy >= 0 && yy < bh && xx >= 0 && xx < bw) near.push(blocks[yy * bw + xx]);
            }
          out[by * bw + bx] = reduce(near);
        }
      blocks = out;
    };
    pass(v => Math.max(...v));
    pass(v => v.reduce((a, b) => a + b, 0) / v.length);
    // Fond agrandi à la taille de la page par le navigateur (lissage bilinéaire, rapide).
    const small = Object.assign(document.createElement('canvas'), { width: bw, height: bh });
    const sctx = small.getContext('2d');
    const map = sctx.createImageData(bw, bh);
    blocks.forEach((v, b) => {
      map.data[b * 4] = map.data[b * 4 + 1] = map.data[b * 4 + 2] = Math.min(255, Math.round(v));
      map.data[b * 4 + 3] = 255;
    });
    sctx.putImageData(map, 0, 0);
    const big = Object.assign(document.createElement('canvas'), { width: w, height: h });
    const bctx = big.getContext('2d', { willReadFrequently: true });
    bctx.imageSmoothingEnabled = true;
    bctx.imageSmoothingQuality = 'high';
    bctx.drawImage(small, 0, 0, w, h);
    const back = bctx.getImageData(0, 0, w, h).data;
    // Papier (≥ 88 % du fond) blanc, encre (≤ 45 %) noire, entre les deux en dégradé.
    const tone = new Uint8ClampedArray(1001);
    for (let r = 0; r <= 1000; r++) tone[r] = Math.round(255 * Math.pow(Math.min(1, Math.max(0, (r / 1000 - 0.45) / 0.43)), 1.5));
    for (let j = 0, i = 0; j < gray.length; j++, i += 4) {
      const g = tone[Math.min(1000, Math.round((1000 * gray[j]) / Math.max(back[i], 40)))];
      p[i] = p[i + 1] = p[i + 2] = g;
    }
    ctx.putImageData(pixels, 0, 0);
    const blob = await new Promise(ok => canvas.toBlob(ok, 'image/jpeg', 0.75));
    if (!blob) throw new Error('mise au propre impossible');
    return await new Promise((ok, ko) => {
      const reader = new FileReader();
      reader.onload = () => ok(String(reader.result).split(',')[1] || '');
      reader.onerror = () => ko(new Error('mise au propre impossible'));
      reader.readAsDataURL(blob);
    });
  }

  // ---------------------------------------------------------------- envoi et suivi
  async function deliver(t) {
    const r = await fetch('/api/tickets', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Appareil': device() },
      body: JSON.stringify({ id: t.id, packets: t.packets }),
      cache: 'no-store',
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw Error(data.error || 'Orbismini ne répond pas (' + r.status + ')');
    return data.state;
  }
  // État de chaque ticket en route ; inconnu d'Orbismini (redémarré) : renvoyé.
  // ---------------------------------------------------------------- propositions de rachat
  // Trace d'une proposition envoyée au client (Rachat → Imprimer → « Envoyer au client », print.js)
  // vers « Dernières propositions » d'Orbis : même enveloppe et même boîte aux lettres que les
  // tickets, id « p<AAAAMMJJ>-<20 hex> », chemin scellé « /proposition/<id> ». Le texte « data » est
  // signé tel quel : mac = HMAC(secret, "proposition1|id|phone|sha256(data)"). Format convenu avec
  // le relais Orbiscan et Orbis (consigne-relais-propositions.md, 27/11/2026). Gardée ici
  // (localStorage) jusqu'à « rangé », renvoyée toute seule si Orbismini l'a perdue.
  const PROPOSALS = 'orbismini-propositions';
  const proposals = () => {
    try {
      return JSON.parse(localStorage.getItem(PROPOSALS) || '[]') || [];
    } catch {
      return [];
    }
  };
  const keepProposals = list => {
    try {
      localStorage.setItem(PROPOSALS, JSON.stringify(list.slice(-20)));
    } catch {}
  };
  // Courrier scellé pour chaque PC jumelé (même enveloppe et même boîte que les tickets), gardé ici
  // jusqu'à « rangé ». payload(link) donne le contenu signé avec le secret de ce jumelage.
  async function courrier(id, path, payload) {
    const links = Object.entries(settings().links);
    if (!links.length) throw new Error('Ce téléphone n’est jumelé avec aucun PC (Scan → Ticket de frais).');
    const p = { id, created: Date.now(), state: 'nouveau', packets: {} };
    for (const [pc, link] of links) p.packets[pc] = b64(await seal(link.key, path, bytes(JSON.stringify(await payload(link)))));
    keepProposals([...proposals(), p]);
    followProposals();
    return id;
  }
  const newId = letter => letter + new Date().toISOString().slice(0, 10).replace(/-/g, '') + '-' + hex(crypto.getRandomValues(new Uint8Array(10)));

  async function proposition(d) {
    const st = settings(),
      links = Object.entries(st.links);
    if (!links.length) return false; // téléphone jamais jumelé avec un PC : pas de trace possible
    const now = new Date();
    const id = newId('p');
    const data = JSON.stringify({
      city: d.city,
      contact: d.contact,
      client: d.client,
      rows: d.rows,
      lines: d.lines || [],
      at: now.toISOString(),
      phoneName: st.phoneName || '',
    });
    const digest = hex(await crypto.subtle.digest('SHA-256', bytes(data)));
    await courrier(id, '/proposition/' + id, async link => ({
      v: 1,
      genre: 'proposition',
      id,
      phone: device(),
      data,
      mac: await mac(link.secret, ['proposition1', id, device(), digest]),
    }));
    return true;
  }
  // « Virement fait » (chiffres.js, section Demandes de virement) : marquage scellé comme un ticket,
  // chemin « /ticket/<id> », mac = HMAC(secret, "virement1|id|rid|qui|quand|phone"). Un nouvel id à
  // chaque appui. Format : consigne-virements-telephone.md (session Orbis, 27/11/2026).
  async function virementFait(rid, qui) {
    const id = newId('v'),
      quand = new Date().toISOString();
    return courrier(id, '/ticket/' + id, async link => ({
      genre: 'virement-fait',
      id,
      phone: device(),
      rid,
      qui,
      quand,
      mac: await mac(link.secret, ['virement1', id, rid, qui, quand, device()]),
    }));
  }
  async function followProposals() {
    const week = Date.now() - 7 * 86400e3;
    const list = proposals().filter(p => p.created > week);
    if (!list.length) return keepProposals([]);
    try {
      const r = await fetch('/api/tickets/etat?ids=' + list.map(p => p.id).join(','), {
        headers: { 'X-Appareil': device() },
        cache: 'no-store',
      });
      const states = (await r.json()).states || {};
      for (const p of list) {
        p.state = states[p.id] === 'inconnu' || !states[p.id] ? await deliver(p).catch(() => p.state) : states[p.id];
      }
    } catch {}
    keepProposals(list.filter(p => p.state !== 'range'));
  }
  window.OrbisminiPropositions = { envoyer: proposition };
  window.OrbisminiCourrier = { virementFait };

  async function follow() {
    followProposals();
    const list = await outbox().catch(() => []);
    const open = list.filter(t => t.state !== 'range');
    if (open.length) {
      try {
        const r = await fetch('/api/tickets/etat?ids=' + open.map(t => t.id).join(','), {
          headers: { 'X-Appareil': device() },
          cache: 'no-store',
        });
        const states = (await r.json()).states || {};
        for (const t of open) {
          let s = states[t.id];
          if (s === 'inconnu') s = await deliver(t).catch(() => 'inconnu');
          if (s && s !== t.state) {
            t.state = s;
            if (s === 'range') {
              t.packets = null; // rangé : plus rien à garder que la trace
              t.filed = Date.now();
            }
            await put(t);
          }
        }
      } catch {}
    }
    // Trace des tickets rangés gardée 3 jours.
    for (const t of list) if (t.state === 'range' && Date.now() - (t.filed || 0) > 3 * 86400e3) await drop(t.id);
    drawList();
  }

  // ---------------------------------------------------------------- jumelage
  async function peers() {
    const r = await fetch('/api/orbiscan/peers', { cache: 'no-store' });
    return ((await r.json().catch(() => ({}))).peers || []).filter(p => p.key);
  }
  async function pair(peer, code, name, msg) {
    const s = settings();
    const secret = b64(crypto.getRandomValues(new Uint8Array(32)));
    const body = await seal(
      peer.key,
      '/api/ticket/pair',
      bytes(JSON.stringify({ code, phone: device(), name, secret }))
    );
    const r = await fetch('/api/orbiscan/pc/' + peer.pc + '/api/ticket/pair', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-orbiscan-chiffre' },
      body,
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok)
      throw Error(
        data.error === 'code'
          ? 'Code refusé. Sur le PC, dans Orbis : Charges → « Téléphones des tickets » → « Relier un téléphone », puis tape le code affiché.'
          : data.error === 'tickets' || r.status === 403
            ? 'Ce PC n’a pas encore la mise à jour des tickets.'
            : data.error || 'Jumelage impossible (' + r.status + ')'
      );
    s.links[peer.pc] = { name: peer.name, key: peer.key, secret };
    s.phoneName = name;
    save(s);
    msg(peer.name + ' : jumelé ✓');
  }
  async function unlink(pc) {
    const s = settings(),
      link = s.links[pc];
    if (!link) return;
    let told = false;
    try {
      const body = await seal(
        link.key,
        '/api/ticket/unlink',
        bytes(JSON.stringify({ phone: device(), mac: await mac(link.secret, ['unlink', device()]) }))
      );
      const r = await fetch('/api/orbiscan/pc/' + pc + '/api/ticket/unlink', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-orbiscan-chiffre' },
        body,
      });
      told = r.ok;
    } catch {}
    delete s.links[pc];
    save(s);
    return told;
  }

  // ---------------------------------------------------------------- écran
  const list = el('div', { className: 'tk-list' });
  async function drawList() {
    const items = await outbox().catch(() => []);
    const words = {
      nouveau: 'Gardé ici, part au retour du réseau',
      attente: 'En attente du PC',
      recu: 'Reçu par le PC',
      range: 'Rangé ✓',
      inconnu: 'Renvoi en cours',
    };
    list.replaceChildren(
      ...(items.length ? [el('h3', { className: 'list-heading', textContent: 'Tickets envoyés' })] : []),
      ...items
        .slice()
        .reverse()
        .map(t =>
          el(
            'div',
            { className: 'tk-item' + (t.state === 'range' ? ' done' : '') },
            el('span', { textContent: (KINDS[t.kind] || 'Carburant') + ' · ' + t.city + ' · ' + euro(t.amount) + ' · ' + dayText(t.day) }),
            el('b', { textContent: words[t.state] || t.state })
          )
        )
    );
  }

  function draw(message) {
    const s = settings();
    const linked = Object.entries(s.links);
    const msg = el('p', { className: 'small tk-msg', textContent: message || '' });
    const say = (text, bad) => {
      msg.textContent = text;
      msg.classList.toggle('tk-bad', !!bad);
    };
    // Agence et type de dépense (retenus d'une fois sur l'autre).
    let city = s.city,
      kind = s.kind;
    const choice = (cls, options, get, set) => {
      const row = el('div', { className: cls, role: 'group' });
      const paint = () =>
        row.replaceChildren(
          ...options.map(([value, label]) =>
            el('button', {
              type: 'button',
              textContent: label,
              className: value === get() ? 'chosen' : '',
              onclick: () => {
                set(value);
                paint();
              },
            })
          )
        );
      paint();
      return row;
    };
    const remember = (k, v) => {
      const st = settings();
      st[k] = v;
      save(st);
    };
    const cityRow = choice('tk-cities', CITIES.map(c => [c, c]), () => city, v => remember('city', (city = v)));
    const kindRow = choice('tk-kinds', Object.entries(KINDS), () => kind, v => remember('kind', (kind = v)));
    // Photo.
    let photo = null;
    const preview = el('img', { className: 'tk-preview', alt: 'Ticket remis au propre', hidden: true });
    const file = el('input', { type: 'file', accept: 'image/*', hidden: true });
    file.setAttribute('capture', 'environment');
    const shoot = el('button', { type: 'button', className: 'secondary', textContent: '📷 Photographier le ticket' });
    shoot.onclick = () => file.click();
    file.onchange = async () => {
      const f = file.files[0];
      file.value = '';
      if (!f) return;
      shoot.disabled = true;
      shoot.textContent = 'Mise au propre…';
      try {
        const url = URL.createObjectURL(f);
        const jpeg = await scanLook(url);
        URL.revokeObjectURL(url);
        const d = new Date(f.lastModified || Date.now());
        photo = {
          jpeg,
          day: d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0'),
        };
        preview.src = 'data:image/jpeg;base64,' + jpeg;
        preview.hidden = false;
        shoot.textContent = '📷 Reprendre la photo';
        say('');
      } catch (e) {
        say(e.message || 'Photo illisible', true);
        shoot.textContent = '📷 Photographier le ticket';
      } finally {
        shoot.disabled = false;
      }
    };
    // Montant.
    const amount = el('input', { inputMode: 'decimal', placeholder: '0,00', autocomplete: 'off' });
    amount.setAttribute('aria-label', 'Montant du ticket en euros');
    const send = el('button', { type: 'button', className: 'primary', textContent: 'Envoyer' });
    send.onclick = async () => {
      const st = settings(),
        links = Object.entries(st.links);
      const value = Number(amount.value.replace(/[\s  €]/g, '').replace(',', '.'));
      if (!links.length) return say('Jumelle d’abord ce téléphone avec un PC (plus bas).', true);
      if (!city) return say('Choisis l’agence.', true);
      if (!photo) return say('Prends d’abord la photo du ticket.', true);
      if (!(value > 0 && value <= 9999.99)) return say('Tape le montant du ticket, par exemple 71,88.', true);
      send.disabled = true;
      send.textContent = 'Chiffrement…';
      try {
        const day = photo.day.replace(/-/g, '');
        const t = {
          id: 't' + day + '-' + hex(crypto.getRandomValues(new Uint8Array(10))),
          city,
          kind,
          amount: value.toFixed(2),
          day: photo.day,
          created: Date.now(),
          state: 'nouveau',
          packets: {},
        };
        const jpegBytes = unb64(photo.jpeg);
        const jpegHash = hex(await crypto.subtle.digest('SHA-256', jpegBytes));
        for (const [pc, link] of links) {
          const signature = await mac(link.secret, ['ticket2', t.id, t.city, kind, t.amount, t.day, device(), jpegHash]);
          const payload = JSON.stringify({ v: 2, id: t.id, city, kind, amount: t.amount, day: t.day, phone: device(), jpeg: photo.jpeg, mac: signature });
          t.packets[pc] = b64(await seal(link.key, '/ticket/' + t.id, bytes(payload)));
        }
        await put(t); // gardé ici jusqu'à « rangé »
        send.textContent = 'Envoi…';
        try {
          t.state = await deliver(t);
          await put(t);
          draw('Ticket envoyé : ' + KINDS[kind] + ', ' + city + ', ' + euro(t.amount) + '. Le PC le rangera tout seul.');
        } catch (e) {
          draw(
            navigator.onLine === false || e instanceof TypeError
              ? 'Pas de réseau : ticket gardé sur ce téléphone. Il partira tout seul dès que le réseau revient, Orbismini ouvert (ou à sa prochaine ouverture).'
              : 'Ticket gardé sur ce téléphone, envoi réessayé tout seul : ' + e.message
          );
        }
        drawList();
      } catch (e) {
        say(e.message || 'Envoi impossible', true);
        send.disabled = false;
        send.textContent = 'Envoyer';
      }
    };
    // PC jumelés et jumelage.
    const pcs = el(
      'div',
      { className: 'tk-pcs' },
      el('h3', { className: 'list-heading', textContent: 'PC qui reçoivent les tickets' }),
      ...(linked.length
        ? linked.map(([pc, link]) =>
            el(
              'div',
              { className: 'tk-item' },
              el('span', { textContent: link.name }),
              el('button', {
                type: 'button',
                className: 'quiet',
                textContent: 'Délier',
                onclick: async () => {
                  if (!confirm('Délier « ' + link.name + ' » ? Ce PC ne recevra plus les tickets de ce téléphone.')) return;
                  const told = await unlink(pc);
                  draw(told ? link.name + ' délié.' : link.name + ' délié ici. Délie aussi ce téléphone dans Orbis, sur ce PC.');
                },
              })
            )
          )
        : [el('p', { className: 'small', textContent: 'Aucun PC jumelé pour l’instant.' })])
    );
    const pairBox = el('details', { className: 'ga-help' }, el('summary', { textContent: 'Jumeler ce téléphone avec un PC' }));
    const pairMsg = el('p', { className: 'small' });
    const pairList = el('div');
    const name = el('input', { value: s.phoneName, placeholder: 'Nom du téléphone (ex. iPhone Sylvian)', maxLength: 40 });
    name.setAttribute('aria-label', 'Nom du téléphone');
    name.addEventListener('input', () => name.classList.remove('tk-missing'));
    const look = el('button', { type: 'button', className: 'secondary', textContent: 'Chercher les PC' });
    look.onclick = async () => {
      pairMsg.textContent = 'Recherche…';
      const found = await peers().catch(() => []);
      pairMsg.textContent = found.length
        ? 'Sur le PC, dans Orbis : Charges → « Téléphones des tickets » → « Relier un téléphone ». Tape ici le code à 2 chiffres affiché.'
        : 'Aucun PC sur ce réseau : connecte-toi au Wi-Fi du magasin, PC allumé.';
      pairList.replaceChildren(
        ...found.map(peer => {
          const code = el('input', { inputMode: 'numeric', maxLength: 2, placeholder: 'Code' });
          code.setAttribute('aria-label', 'Code à 2 chiffres affiché sur ' + peer.name);
          const go = el('button', { type: 'button', className: 'secondary', textContent: 'Jumeler' });
          // Message juste sous la ligne du PC, case fautive entourée et sélectionnée.
          const rowMsg = el('p', { className: 'small tk-bad tk-pair-msg' });
          const fail = (text, field) => {
            rowMsg.textContent = text;
            for (const f of [name, code]) f.classList.toggle('tk-missing', f === field);
            if (field) {
              field.focus();
              field.scrollIntoView({ block: 'center', behavior: 'smooth' });
            }
          };
          go.onclick = async () => {
            if (!name.value.trim()) return fail('Donne d’abord un nom à ce téléphone (case au-dessus).', name);
            if (!/^\d{2}$/.test(code.value)) return fail('Tape le code à 2 chiffres affiché sur le PC.', code);
            fail('');
            go.disabled = true;
            go.textContent = 'Jumelage…';
            try {
              await pair(peer, code.value, name.value.trim(), t => draw(t));
            } catch (e) {
              fail(e.message);
              go.disabled = false;
              go.textContent = 'Jumeler';
            }
          };
          return el('div', {}, el('div', { className: 'tk-pair' }, el('span', { textContent: peer.name }), code, go), rowMsg);
        })
      );
    };
    pairBox.append(
      el('p', { className: 'small', textContent: 'Une fois par PC, au magasin, sur le Wi-Fi du PC. Les tickets partent ensuite de n’importe où, réseau mobile compris.' }),
      name,
      look,
      pairMsg,
      pairList
    );
    if (!linked.length) pairBox.open = true;
    view.replaceChildren(
      el(
        'section',
        { className: 'section tk' },
        el('div', { className: 'eyebrow', textContent: 'TICKET DE FRAIS' }),
        el('p', { className: 'small', textContent: 'Pose le ticket sur la carte d’échelle ou une feuille A4 blanche : il sera redressé, à sa taille réelle.' }),
        el('label', { className: 'tk-label', textContent: 'Agence' }),
        cityRow,
        el('label', { className: 'tk-label', textContent: 'Type' }),
        kindRow,
        el('label', { className: 'tk-label', textContent: 'Photo' }),
        shoot,
        file,
        preview,
        el('label', { className: 'tk-label', textContent: 'Montant (€)' }),
        amount,
        send,
        msg,
        list
      ),
      el('section', { className: 'section' }, pcs, pairBox)
    );
    drawList();
  }

  const visible = () => document.body.dataset.view === 'ticket';
  window.addEventListener('view-changed', () => visible() && (draw(), follow()));
  document.addEventListener('visibilitychange', () => document.visibilityState === 'visible' && follow());
  window.addEventListener('online', () => follow()); // réseau revenu (sortie de parking…) : envoi aussitôt
  draw();
  follow();
  setInterval(() => document.visibilityState === 'visible' && follow(), 60000);
})();
