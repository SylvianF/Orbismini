(() => {
  'use strict';
  // Deux vues : Cours (cotations seules) et Rachat (tous les calculs).
  const nav = document.querySelector('.views');
  // Écran affiché ; tab : onglet allumé (Pièces et Ticket restent sous « Scan »).
  function showView(view, tab = view) {
    if (typeof selected !== 'undefined' && selected) closeBuy();
    document.body.dataset.view = view;
    for (const v of ['cours', 'scans', 'scan', 'meteo', 'rachat', 'ticket', 'chiffres'])
      document.getElementById('view-' + v).hidden = view !== v;
    window.dispatchEvent(new Event('view-changed'));
    nav.querySelectorAll('button[data-view]').forEach(x => x.setAttribute('aria-pressed', String(x.dataset.view === tab)));
    window.scrollTo({ top: 0, behavior: 'instant' });
  }
  nav.addEventListener('click', e => {
    const b = e.target.closest('button[data-view]'); // pas <body data-view>
    if (b) showView(b.dataset.view);
  });
  // Scan : Pièce inconnue et Ticket s'ouvrent depuis l'écran Scan ; retour en glissant du bord
  // gauche (ou en touchant « Scan »).
  document.getElementById('view-scans').addEventListener('click', e => {
    const card = e.target.closest('[data-open]');
    if (!card) return;
    history.pushState({ scan: card.dataset.open }, '');
    showView(card.dataset.open, 'scans');
  });
  window.addEventListener('popstate', () => {
    if (['scan', 'ticket'].includes(document.body.dataset.view)) showView('scans');
  });
  const hero = document.querySelector('.hero'),
    info = document.createElement('div');
  info.className = 'price18-info';
  const jewelryHeading = document.createElement('div');
  jewelryHeading.className = 'gold-quick-heading';
  const jewelryTitle = hero.querySelector('.eyebrow');
  jewelryTitle.textContent = 'ACHAT BIJOUX';
  jewelryTitle.before(jewelryHeading);
  jewelryHeading.append(jewelryTitle);
  const karats = document.createElement('select');
  karats.id = 'price18-titre';
  karats.setAttribute('aria-label', 'Titrage des bijoux');
  for (const [value, label] of [
    ['9', '9K · 375‰'],
    ['14', '14K · 585‰'],
    ['18', '18K · 750‰'],
    ['22', '22K · 900‰'],
  ]) {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = label;
    karats.append(option);
  }
  karats.value = '18';
  jewelryHeading.append(karats);
  const goldSettings = {
    9: { purity: 0.375, discount: '31', label: '375‰' },
    14: { purity: 0.585, discount: '27', label: '585‰' },
    18: { purity: 0.75, discount: '25', label: '750‰' },
    22: { purity: 0.9, discount: '25', label: '900‰' },
  };
  info.innerHTML =
    '<div class="price18-fields"><label>Prix proposé €/g<input id="price18-proposed" type="text" inputmode="decimal" placeholder="—"></label><label>GtaX (%)<input id="price18-gtax" type="text" inputmode="decimal" placeholder="—"></label></div><details><summary>Référence et base de calcul</summary><div class="row"><span id="price18-reference-label">Intrinsèque · 750‰</span><b id="price18-reference">—</b></div><div class="row"><span>Base de calcul · 1 kg</span><b id="price18-base">—</b></div></details>';
  hero.append(info);
  const discountControls = hero.querySelector('.inputs');
  info.querySelector('details').append(discountControls);
  const proposed = document.getElementById('price18-proposed'),
    gtax = document.getElementById('price18-gtax'),
    discountInput = document.getElementById('mult');
  let override = { mode: 'default', value: '' };
  let saved18Discount = localStorage.getItem('or-discount');
  function quote18(intrinsic, cpor, discount, mode, value, purity = 0.75) {
    const ref = Number.isFinite(intrinsic) && intrinsic > 0 ? (intrinsic * purity) / 1000 : null;
    const base =
      ref !== null && Number.isFinite(cpor) && cpor > 0 ? Math.min(intrinsic, cpor) : null;
    const raw = String(value),
      v = raw.trim() === '' ? NaN : parseNum(raw);
    let price = null;
    if (mode === 'price') price = Number.isFinite(v) && v >= 0 ? v : null;
    else if (mode === 'gtax')
      price = ref !== null && Number.isFinite(v) && v >= 0 && v <= 100 ? ref * (1 - v / 100) : null;
    else {
      const d = String(discount).trim() === '' ? NaN : parseNum(discount);
      price =
        base !== null && Number.isFinite(d) && d >= 0 && d <= 100
          ? ((base * purity) / 1000) * (1 - d / 100)
          : null;
    }
    return {
      ref,
      base,
      price,
      gtax: ref !== null && price !== null ? 100 * (1 - price / ref) : null,
    };
  }
  function update18() {
    const setting = goldSettings[karats.value];
    const result = quote18(
      data.instant,
      data.cpor,
      discountInput.value,
      override.mode,
      override.value,
      setting.purity
    );
    document.getElementById('price18-reference-label').textContent =
      'Intrinsèque · ' + setting.label;
    document.getElementById('price18-reference').textContent = eur(result.ref) + ' /g';
    document.getElementById('price18-base').textContent = eur(result.base);
    document.getElementById('price18').textContent =
      result.price === null ? '— €/g' : eur(result.price) + ' /g';
    if (document.activeElement !== proposed)
      proposed.value = result.price === null ? '' : result.price.toFixed(2);
    if (document.activeElement !== gtax)
      gtax.value = result.gtax === null ? '' : result.gtax.toFixed(2);
  }
  karats.addEventListener('change', () => {
    override = { mode: 'default', value: '' };
    discountInput.value = goldSettings[karats.value].discount;
    update18();
  });
  proposed.addEventListener('input', () => {
    override = { mode: 'price', value: proposed.value };
    update18();
  });
  gtax.addEventListener('input', () => {
    override = { mode: 'gtax', value: gtax.value };
    update18();
  });
  for (const field of [proposed, gtax]) field.addEventListener('blur', update18);
  discountInput.addEventListener('input', () => {
    if (karats.value === '18') saved18Discount = discountInput.value;
    else if (saved18Discount === null) localStorage.removeItem('or-discount');
    else localStorage.setItem('or-discount', saved18Discount);
    override = { mode: 'default', value: '' };
    update18();
  });
  window.addEventListener('prices-updated', update18);
  window.addEventListener('client-reset', () => {
    karats.value = '18';
    saved18Discount = null;
    override = { mode: 'default', value: '' };
    discountInput.value = '25';
    localStorage.removeItem('or-discount');
    for (const id of ['tax-cost', 'tax-date']) document.getElementById(id).value = '';
    document.getElementById('buy-discount').value = buyFee();
    draw();
    update18();
  });
  update18();
})();
