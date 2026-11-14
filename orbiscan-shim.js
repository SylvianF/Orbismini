// Orbiscan dans Orbismini : raccord chargé avant le code de la page Orbiscan du PC.
// La page croit parler au relais du PC sur le Wi-Fi ; ses appels passent en fait par
// Orbismini (/api/orbiscan/pc/<PC>/…, orbiscan_tunnel.py). Chaque photo est chiffrée ici,
// sur le téléphone, avec la clé publique du PC (RSA-OAEP 2048 + AES-256-GCM) : Orbismini
// ne la voit jamais en clair, et refuse toute photo qui ne l'est pas.
(() => {
  'use strict';
  const HOME = window.ORBISCAN_HOME;
  const send = window.fetch.bind(window);
  const keys = {}; // PC → clé publique {n, e}

  try {
    localStorage.setItem('gtaxHelpSeen', '1'); // pas d'aide « écran d'accueil » dans Orbismini
  } catch {}
  // La page change son adresse (/t, /p/…) : on la garde sous /orbiscan/ pour qu'un rechargement marche.
  for (const name of ['replaceState', 'pushState']) {
    const original = history[name].bind(history);
    history[name] = (state, title, url) =>
      original(state, title, typeof url === 'string' && /^\/(?!orbiscan\/)/.test(url) ? '/orbiscan' + url : url);
  }

  async function peers() {
    const r = await send('/api/orbiscan/peers', { cache: 'no-store' });
    const data = await r.json().catch(() => ({ peers: [] }));
    const list = data.peers || [];
    for (const p of list) keys[p.pc] = p.key;
    // Le PC qui sert la page en premier : la page lui donne l'adresse '' (la sienne).
    list.sort((a, b) => (a.pc === HOME ? -1 : b.pc === HOME ? 1 : 0));
    return list;
  }

  const bytes = s => new TextEncoder().encode(s);
  async function seal(pc, path, blob) {
    if (!keys[pc]) await peers();
    const k = keys[pc];
    if (!k) throw new TypeError('PC introuvable');
    const pub = await crypto.subtle.importKey(
      'jwk',
      { kty: 'RSA', n: k.n, e: k.e, alg: 'RSA-OAEP-256', ext: true },
      { name: 'RSA-OAEP', hash: 'SHA-256' },
      false,
      ['encrypt']
    );
    const aes = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, true, ['encrypt']);
    const wrapped = new Uint8Array(
      await crypto.subtle.encrypt({ name: 'RSA-OAEP' }, pub, await crypto.subtle.exportKey('raw', aes))
    );
    const iv = crypto.getRandomValues(new Uint8Array(12));
    // Le chemin (/api/upload/<demande>/<côté>) est lié au chiffrement : le PC refuse une photo déplacée.
    const sealed = new Uint8Array(
      await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: bytes(path) }, aes, await blob.arrayBuffer())
    );
    // OSC1 | longueur de la clé enveloppée (2 octets) | clé enveloppée | iv (12) | photo chiffrée + étiquette
    const head = new Uint8Array([79, 83, 67, 49, wrapped.length >> 8, wrapped.length & 255]);
    return new Blob([head, wrapped, iv, sealed]);
  }

  window.fetch = async (input, opts = {}) => {
    let url = typeof input === 'string' ? input : input.url;
    // L'ancienne adresse locale (http://orbiscan.local…) : inaccessible depuis Orbismini.
    if (/^[a-z]+:\/\//i.test(url) && !url.startsWith(location.origin)) throw new TypeError('hors Orbismini');
    url = url.replace(location.origin, '');
    if (url === '/api/peers') {
      const list = await peers();
      return new Response(JSON.stringify({ peers: list.map(p => ({ pc: p.pc, name: p.name, url: p.url })) }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    if (url.startsWith('/api/') && !url.startsWith('/api/orbiscan/')) url = '/api/orbiscan/pc/' + HOME + url;
    const m = url.match(/^\/api\/orbiscan\/pc\/([\w-]+)(\/api\/upload\/.*)$/);
    if (m && opts.body instanceof Blob) {
      opts = {
        ...opts,
        body: await seal(m[1], m[2], opts.body),
        headers: { 'Content-Type': 'application/x-orbiscan-chiffre' },
      };
    }
    return send(url, opts);
  };

  document.addEventListener('DOMContentLoaded', () => {
    const foot = document.querySelector('footer');
    if (foot) foot.textContent = 'Par Orbismini : photos chiffrées sur ce téléphone, lisibles seulement par le PC.';
  });
})();
