/* Feuille A4 sous le document photographié (choix de Sylvian, 20/11/2026) : un ticket posé
   sur une feuille A4 blanche, elle-même sur une surface plus foncée, est recadré sur la
   feuille. La feuille devient la page du PDF : le ticket garde sa taille réelle, quel que
   soit son format. Sans feuille reconnue, la photo reste entière (comme avant).

   Recherche sur une image réduite : seuil de clarté (méthode d'Otsu), plus grande zone
   claire d'un seul tenant, puis contrôles (au moins 20 % de la photo, presque pleine,
   ne touchant pas tous les bords, proportions d'une A4 à ±8 %).
   Fichier autonome, repris tel quel par Orbismini (tickets de carburant). */
(() => {
  'use strict';
  const A4 = 297 / 210;

  // Rectangle de la feuille dans l'image (pixels d'origine), ou null.
  function find(img) {
    const W = img.naturalWidth || img.width,
      H = img.naturalHeight || img.height;
    const k = Math.min(1, 320 / Math.max(W, H));
    const w = Math.max(8, Math.round(W * k)),
      h = Math.max(8, Math.round(H * k));
    const c = Object.assign(document.createElement('canvas'), { width: w, height: h });
    const ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(img, 0, 0, w, h);
    const p = ctx.getImageData(0, 0, w, h).data;
    const gray = new Uint8Array(w * h);
    const hist = new Float64Array(256);
    for (let i = 0, j = 0; j < gray.length; i += 4, j++) {
      gray[j] = Math.round(0.299 * p[i] + 0.587 * p[i + 1] + 0.114 * p[i + 2]);
      hist[gray[j]]++;
    }
    // Seuil d'Otsu : sépare au mieux le clair (feuille) du foncé (bureau).
    const n = gray.length;
    let sum = 0;
    for (let t = 0; t < 256; t++) sum += t * hist[t];
    let sumB = 0,
      wB = 0,
      best = -1,
      cut = 128;
    for (let t = 0; t < 256; t++) {
      wB += hist[t];
      if (!wB || wB === n) continue;
      sumB += t * hist[t];
      const mB = sumB / wB,
        mF = (sum - sumB) / (n - wB);
      const between = wB * (n - wB) * (mB - mF) * (mB - mF);
      if (between > best) [best, cut] = [between, t];
    }
    // Plus grande zone claire d'un seul tenant.
    const seen = new Uint8Array(n);
    let top = null;
    const stack = new Int32Array(n);
    for (let s = 0; s < n; s++) {
      if (seen[s] || gray[s] <= cut) continue;
      let sp = 0,
        count = 0,
        x0 = w,
        y0 = h,
        x1 = -1,
        y1 = -1;
      stack[sp++] = s;
      seen[s] = 1;
      while (sp) {
        const q = stack[--sp],
          x = q % w,
          y = (q - x) / w;
        count++;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
        for (const r of [x > 0 ? q - 1 : -1, x < w - 1 ? q + 1 : -1, y > 0 ? q - w : -1, y < h - 1 ? q + w : -1])
          if (r >= 0 && !seen[r] && gray[r] > cut) {
            seen[r] = 1;
            stack[sp++] = r;
          }
      }
      if (!top || count > top.count) top = { count, x0, y0, x1, y1 };
    }
    if (!top) return null;
    const bw = top.x1 - top.x0 + 1,
      bh = top.y1 - top.y0 + 1;
    const edges = (top.x0 <= 1) + (top.y0 <= 1) + (top.x1 >= w - 2) + (top.y1 >= h - 2);
    const ratio = Math.max(bw, bh) / Math.min(bw, bh);
    if (
      top.count < 0.2 * n || // trop petite : pas une feuille
      top.count < 0.8 * bw * bh || // pas un rectangle plein (zone claire en lambeaux)
      edges >= 3 || // touche presque tous les bords : pas de bureau autour, rien à recadrer
      Math.abs(ratio - A4) > 0.08 * A4
    )
      return null;
    // Retrait d'un point réduit tout autour : ni bord du bureau, ni ombre de la feuille.
    const x = (top.x0 + 1) / k,
      y = (top.y0 + 1) / k;
    return {
      x: Math.max(0, x),
      y: Math.max(0, y),
      w: Math.min(W - x, (bw - 2) / k),
      h: Math.min(H - y, (bh - 2) / k),
    };
  }

  // ---- Papier à petits carreaux (5 mm) avec 3 cases noircies (choix de Sylvian) ----
  // Les 3 cases, posées en équerre (deux l'une au-dessus de l'autre, deux côte à côte),
  // donnent l'échelle et l'inclinaison : la case noire fixe l'ordre de grandeur, puis le
  // quadrillage mesuré entre deux cases, en nombre entier de carreaux, l'échelle exacte.
  const CELL_MM = 5;

  function otsu(gray) {
    const hist = new Float64Array(256);
    for (const v of gray) hist[v]++;
    const n = gray.length;
    let sum = 0;
    for (let t = 0; t < 256; t++) sum += t * hist[t];
    let sumB = 0,
      wB = 0,
      best = -1,
      cut = 128;
    for (let t = 0; t < 256; t++) {
      wB += hist[t];
      if (!wB || wB === n) continue;
      sumB += t * hist[t];
      const mB = sumB / wB,
        mF = (sum - sumB) / (n - wB),
        between = wB * (n - wB) * (mB - mF) * (mB - mF);
      if (between > best) [best, cut] = [between, t];
    }
    return cut;
  }

  // Zones foncées d'un seul tenant : [{count, x0, y0, x1, y1}].
  function blobs(dark, w, h) {
    const n = w * h,
      seen = new Uint8Array(n),
      stack = new Int32Array(n),
      out = [];
    for (let s = 0; s < n; s++) {
      if (seen[s] || !dark[s]) continue;
      let sp = 0,
        count = 0,
        x0 = w,
        y0 = h,
        x1 = -1,
        y1 = -1;
      stack[sp++] = s;
      seen[s] = 1;
      while (sp) {
        const q = stack[--sp],
          x = q % w,
          y = (q - x) / w;
        count++;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
        for (const r of [x > 0 ? q - 1 : -1, x < w - 1 ? q + 1 : -1, y > 0 ? q - w : -1, y < h - 1 ? q + w : -1])
          if (r >= 0 && !seen[r] && dark[r]) {
            seen[r] = 1;
            stack[sp++] = r;
          }
      }
      out.push({ count, x0, y0, x1, y1, seed: s });
    }
    return out;
  }

  // Période du quadrillage (en points) le long d'un segment, cherchée autour de `guess`.
  function period(chan, w, h, a, b, guess) {
    const len = Math.hypot(b.x - a.x, b.y - a.y),
      ux = (b.x - a.x) / len,
      uy = (b.y - a.y) / len;
    const start = guess * 1.2,
      stop = len - guess * 1.2,
      step = 0.5;
    const prof = [];
    for (let t = start; t < stop; t += step) {
      let v = 0,
        c = 0;
      for (let o = -2; o <= 2; o++) {
        const x = Math.round(a.x + ux * t - uy * o * guess * 0.15),
          y = Math.round(a.y + uy * t + ux * o * guess * 0.15);
        if (x >= 0 && y >= 0 && x < w && y < h) (v += chan[y * w + x]), c++;
      }
      prof.push(c ? v / c : 0);
    }
    if (prof.length < 8 * guess / step) return null;
    const mean = prof.reduce((s, v) => s + v, 0) / prof.length;
    const z = prof.map(v => v - mean);
    let best = null;
    // Une case noircie remplit un carreau : le carreau a la taille des cases, à 20 % près
    // (les caractères d'un ticket, plus serrés, ne passent pas pour des carreaux).
    for (let lag = Math.round((0.8 * guess) / step); lag <= Math.round((1.25 * guess) / step); lag++) {
      let s = 0;
      for (let i = 0; i + lag < z.length; i++) s += z[i] * z[i + lag];
      s /= z.length - lag;
      if (!best || s > best.s) best = { s, lag };
    }
    const variance = z.reduce((s, v) => s + v * v, 0) / z.length;
    // Vrai quadrillage : motif marqué qui se répète nettement (mesuré le 20/11/2026 : carreaux
    // 0,79 à 0,80 ; grain d'une feuille blanche 0,48 à 0,50 ; ticket traversé 0,13 à 0,39).
    return best && variance > 10 && best.s / variance > 0.6 ? best.lag * step : null;
  }

  // Image réduite, niveaux de gris, seuil, et carrés noirs repérés (carrés, pleins, petits,
  // entourés de papier clair). Commun à la carte et au papier à carreaux.
  function scan(img) {
    const W = img.naturalWidth || img.width,
      H = img.naturalHeight || img.height;
    const k = Math.min(1, 1400 / Math.max(W, H));
    const w = Math.max(8, Math.round(W * k)),
      h = Math.max(8, Math.round(H * k));
    const c = Object.assign(document.createElement('canvas'), { width: w, height: h });
    const ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(img, 0, 0, w, h);
    const p = ctx.getImageData(0, 0, w, h).data;
    const gray = new Uint8Array(w * h),
      red = new Uint8Array(w * h);
    for (let i = 0, j = 0; j < gray.length; i += 4, j++) {
      gray[j] = Math.round(0.299 * p[i] + 0.587 * p[i + 1] + 0.114 * p[i + 2]);
      red[j] = p[i]; // lignes bleues du quadrillage : sombres dans le rouge
    }
    const cut = otsu(gray);
    const dark = new Uint8Array(w * h);
    for (let j = 0; j < gray.length; j++) dark[j] = gray[j] < cut * 0.55 ? 1 : 0;
    const big = Math.max(w, h);
    // Cases noires : carrées, pleines, petites, entourées de papier clair.
    const marks = [];
    for (const b of blobs(dark, w, h)) {
      const bw = b.x1 - b.x0 + 1,
        bh = b.y1 - b.y0 + 1;
      if (bw < big * 0.006 || bw > big * 0.06 || bh / bw < 0.65 || bh / bw > 1.55 || b.count < 0.6 * bw * bh) continue;
      const m = Math.round(Math.max(bw, bh) * 0.6);
      let ring = 0,
        bright = 0;
      for (let y = b.y0 - m; y <= b.y1 + m; y++)
        for (let x = b.x0 - m; x <= b.x1 + m; x++) {
          if (x >= b.x0 && x <= b.x1 && y >= b.y0 && y <= b.y1) continue;
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          ring++;
          if (gray[y * w + x] > cut) bright++;
        }
      if (ring && bright / ring > 0.85) marks.push({ x: (b.x0 + b.x1) / 2, y: (b.y0 + b.y1) / 2, size: (bw + bh) / 2 });
    }
    return { k, w, h, gray, red, cut, marks };
  }

  // Échelle (points de l'image d'origine par mm), inclinaison, cases ; ou null.
  function grid(img, s = scan(img)) {
    const { k, w, h, red, cut, marks } = s;
    // Trois cases de même taille, en équerre : l'angle droit est à l'une d'elles.
    let best = null;
    for (let i = 0; i < marks.length; i++)
      for (let j = 0; j < marks.length; j++)
        for (let l = j + 1; l < marks.length; l++) {
          if (i === j || i === l) continue;
          const o = marks[i],
            a = marks[j],
            b = marks[l];
          const sizes = [o.size, a.size, b.size],
            mid = (Math.min(...sizes) + Math.max(...sizes)) / 2;
          if (Math.max(...sizes) > Math.min(...sizes) * 1.45) continue;
          const v1 = [a.x - o.x, a.y - o.y],
            v2 = [b.x - o.x, b.y - o.y];
          const n1 = Math.hypot(...v1),
            n2 = Math.hypot(...v2);
          if (n1 < mid * 6 || n2 < mid * 6) continue;
          const cos = Math.abs((v1[0] * v2[0] + v1[1] * v2[1]) / (n1 * n2));
          if (cos > 0.08) continue;
          if (!best || cos < best.cos) best = { cos, o, a, b, mid };
        }
    if (!best) return null;
    // Échelle exacte : quadrillage mesuré sur chaque branche de l'équerre.
    const pitches = [];
    for (const end of [best.a, best.b]) {
      const per = period(red, w, h, best.o, end, best.mid);
      const dist = Math.hypot(end.x - best.o.x, end.y - best.o.y);
      // Le quadrillage doit se voir aussi près d'une des deux cases, sur le papier (une
      // branche qui ne traverse que le ticket ne prouve rien).
      const along = f => ({ x: best.o.x + ((end.x - best.o.x) * f) / dist, y: best.o.y + ((end.y - best.o.y) * f) / dist });
      const span = 12 * best.mid;
      const local =
        per && dist > span * 1.5
          ? [period(red, w, h, best.o, along(span), best.mid), period(red, w, h, along(dist - span), end, best.mid)]
          : [];
      if (!local.some(l => l && Math.abs(l - per) < 0.08 * per)) continue;
      const cells = per ? Math.round(dist / per) : 0;
      if (cells >= 4 && Math.abs(dist / per - cells) < 0.25) pitches.push(dist / cells);
    }
    if (!pitches.length) return null; // pas de quadrillage lisible : échelle inconnue
    const pitch = pitches.reduce((s, v) => s + v, 0) / pitches.length;
    // Inclinaison : la branche la plus verticale de l'équerre devrait l'être.
    const legs = [best.a, best.b].map(e => Math.atan2(e.x - best.o.x, e.y - best.o.y));
    const tilt = legs
      .map(t => {
        let r = t % (Math.PI / 2);
        if (r > Math.PI / 4) r -= Math.PI / 2;
        if (r < -Math.PI / 4) r += Math.PI / 2;
        return r;
      })
      .reduce((s, v) => s + v, 0) / 2;
    return {
      pxPerMm: pitch / CELL_MM / k,
      tilt,
      marks: [best.o, best.a, best.b].map(m => ({ x: m.x / k, y: m.y / k, size: m.size / k })),
      cells: pitches.length,
      cut,
    };
  }

  // Hors du papier (bureau, sol, ombre) : blanc. Le papier, ce sont les grandes zones
  // claires (feuille, ticket : l'ombre du ticket peut couper la feuille en deux) ; on efface
  // depuis les bords tout ce qui n'en fait pas partie.
  function whiten(out, cut) {
    const ctx = out.getContext('2d', { willReadFrequently: true });
    const d = ctx.getImageData(0, 0, out.width, out.height),
      q = d.data,
      ow = out.width,
      oh = out.height;
    const light = new Uint8Array(ow * oh);
    for (let j = 0; j < light.length; j++) light[j] = 0.299 * q[j * 4] + 0.587 * q[j * 4 + 1] + 0.114 * q[j * 4 + 2] > cut ? 1 : 0;
    const paper = new Uint8Array(ow * oh);
    const zones = blobs(light, ow, oh),
      largest = Math.max(0, ...zones.map(b => b.count));
    for (const top of zones.filter(b => b.count >= largest * 0.15)) {
      // Zone retenue : remplissage depuis son premier point.
      const st = [top.seed];
      while (st.length) {
        const j = st.pop();
        if (paper[j] || !light[j]) continue;
        paper[j] = 1;
        const x = j % ow;
        if (x > 0) st.push(j - 1);
        if (x < ow - 1) st.push(j + 1);
        if (j >= ow) st.push(j - ow);
        if (j < (oh - 1) * ow) st.push(j + ow);
      }
    }
    const seen = new Uint8Array(ow * oh),
      stack = [];
    for (let x = 0; x < ow; x++) stack.push(x, (oh - 1) * ow + x);
    for (let y = 0; y < oh; y++) stack.push(y * ow, y * ow + ow - 1);
    while (stack.length) {
      const j = stack.pop();
      if (seen[j] || paper[j]) continue;
      seen[j] = 1;
      q[j * 4] = q[j * 4 + 1] = q[j * 4 + 2] = 255;
      const x = j % ow;
      if (x > 0) stack.push(j - 1);
      if (x < ow - 1) stack.push(j + 1);
      if (j >= ow) stack.push(j - ow);
      if (j < (oh - 1) * ow) stack.push(j + ow);
    }
    ctx.putImageData(d, 0, 0);
  }

  // Page A4 (au plus `max` points de haut) où la photo est posée à l'échelle 1 : redressée,
  // centrée sur le papier, bureau et cases noires effacés en blanc.
  function a4OnGrid(img, g, max) {
    const W = img.naturalWidth || img.width,
      H = img.naturalHeight || img.height;
    const out = Object.assign(document.createElement('canvas'), { width: Math.round((max * 210) / 297), height: max });
    const ctx = out.getContext('2d', { willReadFrequently: true });
    const perMm = max / 297;
    // Centre du papier clair (ticket compris), sur une image réduite.
    const k = Math.min(1, 400 / Math.max(W, H));
    const sw = Math.round(W * k),
      sh = Math.round(H * k);
    const sc = Object.assign(document.createElement('canvas'), { width: sw, height: sh });
    const sctx = sc.getContext('2d', { willReadFrequently: true });
    sctx.drawImage(img, 0, 0, sw, sh);
    const sp = sctx.getImageData(0, 0, sw, sh).data;
    let cx = 0,
      cy = 0,
      cn = 0;
    for (let y = 0, i = 0; y < sh; y++)
      for (let x = 0; x < sw; x++, i += 4)
        if (0.299 * sp[i] + 0.587 * sp[i + 1] + 0.114 * sp[i + 2] > g.cut) (cx += x), (cy += y), cn++;
    cx = cn ? cx / cn / k : W / 2;
    cy = cn ? cy / cn / k : H / 2;
    // Hors de la photo : noir, effacé ensuite avec le bureau.
    ctx.fillStyle = '#000';
    ctx.fillRect(0, 0, out.width, out.height);
    ctx.save();
    ctx.translate(out.width / 2, out.height / 2);
    ctx.rotate(g.tilt);
    ctx.scale(perMm / g.pxPerMm, perMm / g.pxPerMm);
    ctx.translate(-cx, -cy);
    ctx.drawImage(img, 0, 0);
    // Cases noires effacées (un peu plus grandes que la case, pour l'ombre du feutre).
    ctx.fillStyle = '#fff';
    for (const m of g.marks) ctx.fillRect(m.x - m.size * 0.9, m.y - m.size * 0.9, m.size * 1.8, m.size * 1.8);
    ctx.restore();
    whiten(out, g.cut);
    out.sheet = true;
    out.grid = g;
    return out;
  }

  // ---- Carte d'échelle Orbis (outils/carte_echelle.py) ----
  // 4 carrés noirs de 8 mm centrés aux coins d'un rectangle de 180 × 120 mm. Les 4 coins
  // donnent l'échelle exacte et corrigent une photo prise de biais (perspective) ; si le
  // ticket cache un carré, les 3 autres suffisent (photo prise bien d'en haut).
  const CARD = { w: 180, h: 120, square: 8 };

  // Coins de la carte dans l'image réduite : [hautGauche, hautDroite, basDroite, basGauche].
  function cardCorners(marks) {
    const near = (u, v, tol) => Math.abs(u - v) <= tol * Math.max(u, v);
    const ratio = CARD.w / CARD.h;
    const fits = pts => {
      // Ordre autour du centre, puis contrôle d'un rectangle aux proportions de la carte.
      const cx = pts.reduce((s, p) => s + p.x, 0) / 4,
        cy = pts.reduce((s, p) => s + p.y, 0) / 4;
      const o = [...pts].sort((a, b) => Math.atan2(a.y - cy, a.x - cx) - Math.atan2(b.y - cy, b.x - cx));
      // o : sens des aiguilles d'une montre (y vers le bas), à partir du haut-gauche.
      const start = o.reduce((best, p, i) => (p.x + p.y < o[best].x + o[best].y ? i : best), 0);
      const q = [0, 1, 2, 3].map(i => o[(start + i) % 4]);
      const d = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
      const top = d(q[0], q[1]),
        right = d(q[1], q[2]),
        bottom = d(q[2], q[3]),
        left = d(q[3], q[0]);
      if (!near(top, bottom, 0.12) || !near(left, right, 0.12)) return null;
      const r = (top + bottom) / (left + right);
      const long = r >= 1 ? r : 1 / r;
      if (Math.abs(long - ratio) > 0.08 * ratio) return null; // photo prise à peu près d'en haut
      const short = Math.min(top + bottom, left + right) / 2;
      const real = pts.filter(p => !p.ghost);
      const size = real.reduce((s, p) => s + p.size, 0) / real.length;
      // Carré de 8 mm pour 120 mm de petit côté : écarte une carte faite à la main.
      if (Math.abs(size / short - CARD.square / CARD.h) > 0.25 * (CARD.square / CARD.h)) return null;
      return { corners: q, landscape: r >= 1, score: Math.abs(long - ratio) };
    };
    let best = null;
    const n = marks.length;
    for (let a = 0; a < n; a++)
      for (let b = a + 1; b < n; b++)
        for (let c = b + 1; c < n; c++) {
          const three = [marks[a], marks[b], marks[c]];
          // Trois carrés : le quatrième est déduit (parallélogramme).
          for (let i = 0; i < 3; i++) {
            const o = three[i],
              u = three[(i + 1) % 3],
              v = three[(i + 2) % 3];
            const ghost = { x: u.x + v.x - o.x, y: u.y + v.y - o.y, size: o.size, ghost: true };
            const f = fits([o, u, v, ghost]);
            if (f && (!best || (best.count === 3 && f.score < best.score))) best = { ...f, count: 3 };
          }
          for (let e = c + 1; e < n; e++) {
            const f = fits([marks[a], marks[b], marks[c], marks[e]]);
            if (f && (!best || best.count < 4 || f.score < best.score)) best = { ...f, count: 4 };
          }
        }
    return best;
  }

  // Homographie qui envoie 4 points (mm de la carte) sur 4 points (image) : 8 inconnues.
  function homography(src, dst) {
    const A = [],
      B = [];
    for (let i = 0; i < 4; i++) {
      const [X, Y] = src[i],
        [x, y] = dst[i];
      A.push([X, Y, 1, 0, 0, 0, -X * x, -Y * x]);
      B.push(x);
      A.push([0, 0, 0, X, Y, 1, -X * y, -Y * y]);
      B.push(y);
    }
    for (let c = 0; c < 8; c++) {
      let piv = c;
      for (let r = c + 1; r < 8; r++) if (Math.abs(A[r][c]) > Math.abs(A[piv][c])) piv = r;
      [A[c], A[piv]] = [A[piv], A[c]];
      [B[c], B[piv]] = [B[piv], B[c]];
      if (Math.abs(A[c][c]) < 1e-12) return null;
      for (let r = 0; r < 8; r++) {
        if (r === c) continue;
        const f = A[r][c] / A[c][c];
        for (let k = c; k < 8; k++) A[r][k] -= f * A[c][k];
        B[r] -= f * B[c];
      }
    }
    const h = B.map((v, i) => v / A[i][i]);
    return (X, Y) => {
      const z = h[6] * X + h[7] * Y + 1;
      return [(h[0] * X + h[1] * Y + h[2]) / z, (h[3] * X + h[4] * Y + h[5]) / z];
    };
  }

  // Page A4 à l'échelle 1, centrée sur la carte, perspective corrigée ; carrés et bureau
  // effacés.
  function a4OnCard(img, s, found, max) {
    const W = img.naturalWidth || img.width,
      H = img.naturalHeight || img.height;
    const src = Object.assign(document.createElement('canvas'), { width: W, height: H });
    const sctx = src.getContext('2d', { willReadFrequently: true });
    sctx.drawImage(img, 0, 0);
    const sp = sctx.getImageData(0, 0, W, H).data;
    const hw = (found.landscape ? CARD.w : CARD.h) / 2,
      hh = (found.landscape ? CARD.h : CARD.w) / 2;
    const corners = found.corners.map(p => [p.x / s.k, p.y / s.k]);
    const square = [
      [-hw, -hh],
      [hw, -hh],
      [hw, hh],
      [-hw, hh],
    ];
    const map = homography(square, corners);
    if (!map) return null;
    const out = Object.assign(document.createElement('canvas'), { width: Math.round((max * 210) / 297), height: max });
    const ctx = out.getContext('2d', { willReadFrequently: true });
    const ow = out.width,
      oh = out.height,
      perMm = max / 297;
    const d = ctx.createImageData(ow, oh),
      q = d.data;
    for (let v = 0; v < oh; v++) {
      const Y = (v - oh / 2) / perMm;
      for (let u = 0; u < ow; u++) {
        const X = (u - ow / 2) / perMm;
        const [x, y] = map(X, Y);
        const i = (v * ow + u) * 4;
        const xi = Math.round(x),
          yi = Math.round(y);
        q[i + 3] = 255;
        if (xi < 0 || yi < 0 || xi >= W || yi >= H) continue; // hors de la photo : noir, effacé avec le bureau
        const j = (yi * W + xi) * 4;
        q[i] = sp[j];
        q[i + 1] = sp[j + 1];
        q[i + 2] = sp[j + 2];
      }
    }
    ctx.putImageData(d, 0, 0);
    // Les 4 carrés (connus au millimètre) effacés, avec une marge pour leur ombre.
    ctx.fillStyle = '#fff';
    const half = (CARD.square / 2 + 2) * perMm;
    for (const [X, Y] of square) ctx.fillRect(ow / 2 + X * perMm - half, oh / 2 + Y * perMm - half, 2 * half, 2 * half);
    whiten(out, s.cut);
    out.sheet = true;
    out.card = {
      count: found.count,
      pxPerMm: Math.hypot(corners[1][0] - corners[0][0], corners[1][1] - corners[0][1]) / (2 * hw),
    };
    return out;
  }

  // Toile recadrée sur la feuille (ou l'image entière), à au plus `max` points de côté.
  // Ordre : carte d'échelle, papier à carreaux, feuille A4 seule. Des carrés noirs sans
  // échelle lisible (carte faite à la main) : photo entière, plutôt qu'une feuille prise
  // à tort pour une A4.
  function canvasOf(img, max) {
    const s = scan(img);
    const found = cardCorners(s.marks);
    const onCard = found && a4OnCard(img, s, found, max);
    if (onCard) return onCard;
    const g = grid(img, s);
    if (g) return a4OnGrid(img, g, max);
    const W = img.naturalWidth || img.width,
      H = img.naturalHeight || img.height;
    const r = (s.marks.length < 3 && find(img)) || { x: 0, y: 0, w: W, h: H };
    const k = Math.min(1, max / Math.max(r.w, r.h));
    const c = Object.assign(document.createElement('canvas'), {
      width: Math.max(1, Math.round(r.w * k)),
      height: Math.max(1, Math.round(r.h * k)),
    });
    c.getContext('2d', { willReadFrequently: true }).drawImage(img, r.x, r.y, r.w, r.h, 0, 0, c.width, c.height);
    c.sheet = r.w !== W || r.h !== H;
    return c;
  }

  window.GoldSheet = { find, grid, scan, cardCorners, canvasOf };
})();
