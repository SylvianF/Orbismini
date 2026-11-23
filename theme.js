/* Thèmes d'Orbismini, repris des thèmes d'Orbis (theme.js d'Orbis, mêmes règles de couleur) :
   Saphir (d'origine, par défaut), Onyx (le Saphir aux ardoises noires) et Perle (clair), choisis
   sur ce téléphone (menu « Thème » en bas de l'écran des cours).
   Différences avec Orbis : les feuilles style.css et estimation.css sont recopiées dans des <style>
   pour être recolorées (theme.js ne recolore que le texte des <style>) ; pas d'image de fond ;
   couleur de la barre d'état du téléphone suivie. Chargé dans <head>, juste après les feuilles. */
(() => {
  'use strict';
  const KEY = 'orbismini-theme';
  // Thèmes recolorés : teinte des fonds, saturation (min, max), teinte et force du texte,
  // filtre de l'image de fond, pastille du menu. Clés gardées (« warm » = 3.0.36).
  const PALETTES = {
    graphite: { label: 'Onyx', h: 220, s: [0, 0.015], t: 40, ts: 0.12, l: 0.82, filter: 'none', dot: '#1c1c1d' },
  };
  const THEMES = [
    ['dark', 'Saphir', '#1f3a4c'],
    ...Object.entries(PALETTES).map(([k, p]) => [k, p.label, p.dot]),
    ['light', 'Perle', '#f1e9dc'],
  ];
  let light = false,
    warm = false,
    pal = 'graphite';
  try {
    const saved = localStorage.getItem(KEY);
    light = saved === 'light';
    warm = saved in PALETTES;
    if (warm) pal = saved;
  } catch {
    /* mémoire du poste indisponible : sombre */
  }

  // ---------- Feuilles d'Orbismini recopiées dans des <style> (recolorables) ----------
  // Seulement hors Saphir ; lecture immédiate (fichiers déjà gardés par le téléphone).
  function inlineSheets() {
    for (const link of document.querySelectorAll('link[rel="stylesheet"]')) {
      if (!/\/(style|estimation)\.css/.test(link.href) || link.dataset.inlined) continue;
      try {
        const x = new XMLHttpRequest();
        x.open('GET', link.href, false);
        x.send();
        if (x.status !== 200) continue;
        const s = document.createElement('style');
        s.textContent = x.responseText;
        link.after(s);
        link.dataset.inlined = '1';
        link.disabled = true;
      } catch {
        /* feuille illisible : gardée telle quelle (Saphir) */
      }
    }
  }
  if (light || warm) inlineSheets();

  // ---------- Couleurs ----------
  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
  function hsl(r, g, b) {
    (r /= 255), (g /= 255), (b /= 255);
    const max = Math.max(r, g, b),
      min = Math.min(r, g, b),
      l = (max + min) / 2;
    if (max === min) return [0, 0, l];
    const d = max - min,
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    const h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    return [h * 60, s, l];
  }
  function rgb(h, s, l) {
    const k = n => (n + h / 30) % 12,
      a = s * Math.min(l, 1 - l),
      f = n => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
    return [f(0), f(8), f(4)].map(v => Math.round(v * 255));
  }
  // Rôle de la couleur : « text » (couleur du texte), « shadow », sinon fond / bordure.
  function convert(r, g, b, a, role) {
    let [h, s, l] = hsl(r, g, b);
    const neutral = s < 0.45 || l < 0.08 || l > 0.95;
    if (role === 'accent') l = Math.min(l, 0.46); // or des titres et boutons : plus profond
    else if (role === 'shadow') {
      if (l < 0.3) return [70, 52, 24, a * 0.35]; // ombre sombre : brun léger
      [h, s, l] = [h, s, clamp(1 - l * 0.6)];
    } else if (role === 'text') {
      if (neutral) [h, s, l] = [205, s * 0.6, clamp(0.15 + (0.95 - l) * 1.35, 0.08, 0.97)];
      else l = Math.min(l, 0.4); // or, vert, rouge : plus foncés pour rester lisibles
    } else if (neutral && role === 'line') {
      // Bordures : beige soutenu, pour bien dessiner les tuiles blanches.
      [h, s, l] = [36, 0.2, clamp(0.86 - l * 0.35, 0.7, 0.86)];
    } else if (neutral) {
      // Fonds ardoise → Perle contrastée : tuiles (ardoise moyenne) presque blanches, fond
      // de page et champs (ardoise la plus sombre) en crème plus soutenu.
      l = l >= 0.125 ? clamp(0.995 - (l - 0.125) * 0.2) : clamp(0.925 - (0.125 - l) * 0.6, 0.86);
      [h, s] = [38, l > 0.97 ? 0.5 : 0.32];
    } else l = clamp(l * 0.94);
    return [...rgb(h, s, l), a];
  }
  // Bronze : seules les couleurs ardoise (bleu-gris) changent, lumière gardée ; l'or,
  // le vert et le rouge restent.
  function convertWarm(r, g, b, a, role) {
    let [h, s, l] = hsl(r, g, b);
    if (role === 'accent' || h < 170 || h > 250 || s > 0.6) return [r, g, b, a];
    const p = PALETTES[pal];
    if (role === 'text') [h, s] = [p.t, (l > 0.85 ? 0.38 : 0.2) * p.ts];
    else [h, s, l] = [p.h, clamp(s * 0.95, p.s[0], p.s[1]), l * (p.l || 0.96)];
    return [...rgb(h, s, l), a];
  }
  const COLOR = /#(?:[0-9a-f]{8}|[0-9a-f]{6}|[0-9a-f]{3,4})\b|rgba?\(\s*[\d.]+\s*,?\s*[\d.]+\s*,?\s*[\d.]+\s*(?:[,/]\s*[\d.]+%?\s*)?\)|\b(?:white|black)\b/gi;
  function parse(c) {
    c = c.toLowerCase();
    if (c === 'white') return [255, 255, 255, 1];
    if (c === 'black') return [0, 0, 0, 1];
    if (c[0] === '#') {
      let x = c.slice(1);
      if (x.length <= 4) x = [...x].map(v => v + v).join('');
      const n = i => parseInt(x.slice(i, i + 2), 16);
      return [n(0), n(2), n(4), x.length === 8 ? n(6) / 255 : 1];
    }
    const v = c.match(/[\d.]+%?/g).map(p => (p.endsWith('%') ? parseFloat(p) / 100 : parseFloat(p)));
    return [v[0], v[1], v[2], v[3] ?? 1];
  }
  const out = ([r, g, b, a]) => (a >= 1 ? `rgb(${r}, ${g}, ${b})` : `rgba(${r}, ${g}, ${b}, ${+a.toFixed(3)})`);
  function role(prop) {
    // Variables (ex. :host de la proposition de rachat) : rôle d'après leur nom.
    if (prop.startsWith('--')) {
      if (/gold|accent/.test(prop)) return 'accent';
      if (/text|muted|ink|fg|font/.test(prop)) return 'text';
    }
    if (prop === 'color' || prop === 'caret-color' || prop === '-webkit-text-fill-color' || prop === 'text-decoration-color')
      return 'text';
    if (prop === 'box-shadow' || prop === 'text-shadow' || prop === 'filter') return 'shadow';
    if (/^(?:border|outline|column-rule)/.test(prop) || prop === '--line') return 'line';
    return 'surface';
  }
  const COLOR_PROPS = /^(?:--[\w-]+|color|caret-color|accent-color|-webkit-text-fill-color|text-decoration-color|background(?:-color|-image)?|border(?:-[a-z-]+)?|outline(?:-color)?|box-shadow|text-shadow|fill|stroke|column-rule(?:-color)?|scrollbar-color|filter)$/i;
  function convertValue(prop, value) {
    prop = prop.trim().toLowerCase();
    if (prop === 'color-scheme') return light ? value.replace(/\bdark\b/g, 'light') : value;
    if (!COLOR_PROPS.test(prop)) return value;
    const r = role(prop),
      to = light ? convert : convertWarm;
    return value.replace(COLOR, c => out(to(...parse(c), r)));
  }
  // Déclarations « propriété: valeur » d'une feuille de style (les sélecteurs, avant « { »,
  // ne sont pas des propriétés de couleur : un identifiant comme #add reste intact).
  // Mémoire des textes déjà convertis (mêmes styles redessinés sans cesse : agenda, tuiles),
  // vidée au changement de thème et quand elle grossit trop.
  const converted = new Map();
  const convertCss = css => {
    let done = converted.get(css);
    if (done === undefined) {
      done = css.replace(/([-\w]+)(\s*:\s*)([^;{}]+)/g, (m, p, sep, v) => p + sep + convertValue(p, v));
      if (converted.size > 3000) converted.clear();
      converted.set(css, done);
    }
    return done;
  };

  // ---------- Styles suivis ----------
  // Aucune liste des éléments peints : elle gardait en mémoire tout ce qui avait été affiché
  // (agenda et tuiles redessinés sans cesse), et Orbis ralentissait au fil de la journée.
  // Au changement de thème, la page affichée est simplement repeinte (apply).
  const original = new WeakMap(), // <style> → texte d'origine (sombre)
    written = new WeakMap(); // <style> → texte que nous avons écrit
  function paintStyle(el) {
    if (el.dataset?.theme === 'raw') return;
    const text = el.textContent;
    if (written.get(el) !== text) original.set(el, text); // nouveau texte écrit par un module
    const next = light || warm ? convertCss(original.get(el)) : original.get(el);
    if (text !== next) {
      written.set(el, next);
      el.textContent = next;
    } else written.set(el, text);
  }
  const inlineOriginal = new WeakMap(),
    inlineWritten = new WeakMap();
  function paintInline(el) {
    const css = el.getAttribute('style');
    if (css == null || el.closest?.('svg')) return;
    if (inlineWritten.get(el) !== css) {
      if (!/#|rgb|white|black/i.test(css)) return;
      inlineOriginal.set(el, css);
    }
    const next = light || warm ? convertCss(inlineOriginal.get(el)) : inlineOriginal.get(el);
    inlineWritten.set(el, next);
    if (css !== next) el.setAttribute('style', next);
  }
  function scan(node) {
    if (node.nodeType !== 1 && node.nodeType !== 11) return;
    if (node.tagName === 'STYLE') return paintStyle(node);
    if (node.nodeType === 1 && node.hasAttribute('style')) paintInline(node);
    for (const s of node.querySelectorAll('style')) paintStyle(s);
    for (const e of node.querySelectorAll('[style]')) paintInline(e);
  }
  const observer = new MutationObserver(list => {
    for (const m of list) {
      if (m.type === 'childList') {
        if (m.target.tagName === 'STYLE') paintStyle(m.target);
        else m.addedNodes.forEach(scan);
      } else if (m.type === 'characterData') {
        const p = m.target.parentNode;
        if (p?.tagName === 'STYLE') paintStyle(p);
      } else if (m.type === 'attributes') paintInline(m.target);
    }
  });
  const watch = root =>
    observer.observe(root, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ['style'] });
  // Proposition de rachat : styles dans une shadow root.
  const attach = Element.prototype.attachShadow;
  Element.prototype.attachShadow = function (...args) {
    const root = attach.apply(this, args);
    watch(root);
    return root;
  };

  // ---------- Réglages propres au mode clair (non convertis) ----------
  const extra = document.createElement('style');
  extra.dataset.theme = 'raw';
  extra.textContent = `
    html.theme-light { color-scheme: light; --bg: #ece3d3; --surface: #ffffff; --raised: #f7f1e6; --line: #d6c7ad;
      --field: #faf6ef; --text: #1f2a31; --muted: #66757f; --gold: #b8862b; --ink: #ffffff; }
    html.theme-light body { background: #ece3d3 !important; }
    /* Menu « Thème » (barre du bas) : s'ouvre vers le haut, au-dessus de tout. */
    .theme-menu { position: relative; display: inline-block; }
    .theme-menu > button { display: inline-flex; align-items: center; gap: 7px; }
    .theme-dot { width: 12px; height: 12px; border-radius: 50%; border: 1px solid rgba(233,191,117,.65); flex: none; }
    .theme-list { position: absolute; bottom: calc(100% + 6px); right: 0; z-index: 80; min-width: 170px; padding: 6px;
      display: grid; gap: 2px; border-radius: 12px; border: 1px solid var(--line); background: var(--surface); box-shadow: 0 12px 32px rgba(0,0,0,.45); }
    .theme-list[hidden] { display: none; }
    .theme-list button { display: flex; align-items: center; gap: 9px; width: 100%; min-height: 0; padding: 7px 10px; border: 0;
      border-radius: 8px; background: transparent; color: var(--text); font-size: 13.5px; font-weight: 600; text-align: left; }
    .theme-list button:hover { background: var(--field); }
    .theme-list button[aria-checked="true"] { color: var(--gold); }
    .theme-list button[aria-checked="true"]::after { content: '✓'; margin-left: auto; }
    /* Pastilles : couleurs fixes, jamais converties par le thème actif. */
    ${THEMES.map(([k, , dot]) => `.theme-dot[data-t="${k}"] { background: ${dot}; }`).join(' ')}`;
  document.head.append(extra);

  // Barre d'état du téléphone : couleur du fond du thème.
  function statusBar() {
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = light ? '#ece3d3' : warm ? '#0f0f0f' : '#121d25';
  }
  function apply() {
    if (light || warm) inlineSheets();
    statusBar();
    document.documentElement.classList.toggle('theme-light', light);
    document.documentElement.classList.toggle('theme-warm', warm);
    document.documentElement.style.setProperty('--pal-filter', PALETTES[pal].filter);
    for (const k in PALETTES) document.documentElement.classList.toggle('pal-' + k, warm && k === pal);
    converted.clear();
    scan(document.documentElement);
    // Racines fantômes (proposition de rachat) encore affichées.
    for (const host of document.querySelectorAll('*')) if (host.shadowRoot) scan(host.shadowRoot);
    toggle && paintToggle();
  }

  // ---------- Sélecteur ----------
  let toggle = null;
  const current = () => (light ? 'light' : warm ? pal : 'dark');
  function paintToggle() {
    const mode = current(),
      [, label] = THEMES.find(t => t[0] === mode);
    toggle.querySelector('.theme-open .theme-dot').dataset.t = mode;
    toggle.querySelector('.theme-open span:last-child').textContent = 'Thème : ' + label;
    for (const b of toggle.querySelectorAll('.theme-list button')) b.setAttribute('aria-checked', String(b.dataset.set === mode));
  }
  function set(mode) {
    light = mode === 'light';
    warm = mode in PALETTES;
    if (warm) pal = mode;
    try {
      localStorage.setItem(KEY, light ? 'light' : warm ? pal : 'dark');
    } catch {
      /* non mémorisé : valable jusqu'à la fermeture */
    }
    apply();
  }
  function mountToggle() {
    const nav = document.querySelector('#view-cours .footnote');
    if (!nav || document.getElementById('theme-toggle')) return;
    const make = (tag, props = {}, ...kids) => {
      const e = Object.assign(document.createElement(tag), props);
      e.append(...kids);
      return e;
    };
    const list = make('div', { className: 'theme-list', role: 'menu', hidden: true });
    const open = make('button', { type: 'button', className: 'theme-open', title: 'Couleurs d’Orbismini sur ce téléphone' },
      make('i', { className: 'theme-dot' }), make('span'));
    open.setAttribute('aria-haspopup', 'menu');
    const close = () => {
      list.hidden = true;
      open.setAttribute('aria-expanded', 'false');
    };
    open.onclick = e => {
      e.stopPropagation();
      list.hidden = !list.hidden;
      open.setAttribute('aria-expanded', String(!list.hidden));
    };
    for (const [mode, label] of THEMES) {
      const b = make('button', { type: 'button' }, make('i', { className: 'theme-dot' }), label);
      b.firstChild.dataset.t = mode;
      b.dataset.set = mode;
      b.setAttribute('role', 'menuitemradio');
      b.onclick = () => {
        set(mode);
        close();
      };
      list.append(b);
    }
    document.addEventListener('click', e => !toggle.contains(e.target) && close());
    document.addEventListener('keydown', e => e.key === 'Escape' && close());
    toggle = make('span', { id: 'theme-toggle', className: 'theme-menu' }, open, list);
    nav.append(make('br'), toggle);
    paintToggle();
  }

  document.documentElement.classList.toggle('theme-light', light);
  document.documentElement.classList.toggle('theme-warm', warm);
  document.documentElement.style.setProperty('--pal-filter', PALETTES[pal].filter);
  for (const k in PALETTES) document.documentElement.classList.toggle('pal-' + k, warm && k === pal);
  statusBar();
  scan(document.documentElement);
  watch(document.documentElement);
  document.addEventListener('DOMContentLoaded', () => {
    scan(document.documentElement);
    mountToggle();
  });
  // « ?vue=rachat » (application iPhone) : mobile.js ouvre directement cette vue ; d'ici là, la vue
  // Cours reste cachée (style.css), pour ne pas apparaître un instant.
  try {
    const vue = new URLSearchParams(location.search).get('vue');
    if (vue && vue !== 'cours') document.documentElement.dataset.vue = vue;
  } catch { /* adresse illisible : rien */ }
})();
