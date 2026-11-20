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

  // Toile recadrée sur la feuille (ou l'image entière), à au plus `max` points de côté.
  function canvasOf(img, max) {
    const W = img.naturalWidth || img.width,
      H = img.naturalHeight || img.height;
    const r = find(img) || { x: 0, y: 0, w: W, h: H };
    const k = Math.min(1, max / Math.max(r.w, r.h));
    const c = Object.assign(document.createElement('canvas'), {
      width: Math.max(1, Math.round(r.w * k)),
      height: Math.max(1, Math.round(r.h * k)),
    });
    c.getContext('2d', { willReadFrequently: true }).drawImage(img, r.x, r.y, r.w, r.h, 0, 0, c.width, c.height);
    c.sheet = r.w !== W || r.h !== H;
    return c;
  }

  window.GoldSheet = { find, canvasOf };
})();
