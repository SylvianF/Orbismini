# Orbismini

(anciennement OrApp ; dépôt et service Render gardent le nom mon-cours-or)

Anciennement GoldApp. Logo dérivé de celui d’Orbis : `icon.svg` (icône),
`orapp-logo.svg` / `orapp-logo.png` (logo complet).

Application iPhone (ajoutée à l’écran d’accueil depuis Safari) pour suivre les cours de
l’or et répondre en déplacement à « combien vous rachetez ce produit ? ». Hébergée sur
Render (`render.yaml`) à partir du dépôt GitHub. Aucune donnée client n’est stockée sur le
serveur.

## Barre du bas

Cinq onglets et un bouton, dans cet ordre : Cours, Météo, Orbiscan, Pièces, Rachat, Ticket.

- **Cours** : recherche, favoris (appui long sur un produit), or pur 1 kg avec sa variation
  et son graphique, pièces et lingots CPoR, argent. Sous chaque
  pièce ou lingot d’or : le prix de **rachat** (prix net client : FC du calcul d’achat,
  7,5 % par défaut, 4 % sur le lingot 1 kg, puis TMP 11,5 %). Toucher un produit ouvre le détail (frais, TMP/TPV).
- **Météo** : météo de l’or, résumé des indices de tendance (pas une prévision, voir
  CHANGELOG). Dollar et euro y sont de simples repères, comme dans GoldGestion. Sources : BullionVault et Yahoo Finance (dollar, euro, taux, VIX).
- **Orbiscan** (bouton, pas un onglet) : ouvre par-dessus l’écran la page Orbiscan du PC du
  magasin ; les photos partent chiffrées depuis le téléphone. Ne marche qu’avec un PC relié.
- **Pièces** : poids et titre d’une pièce peu courante, comme le scanner de pièces d’Orbis :
  photo (Claude) ou recherche guidée (mots, pays, année), fiche Numista et prix d’achat indicatif.
- **Rachat** : estimation client multi-lignes et impression, achat bijoux (9K à 22K),
  prix rapide d’une pièce d’or.
- **Ticket** : ticket de frais (carburant, péage, restaurant, parking) pris en photo, recadré,
  scellé et signé sur le téléphone pour les PC jumelés ; Orbis le range dans « <Agence> - Orbis
  range ». Sans réseau, il attend sur le téléphone et part dès le retour du réseau.

Mise en page reprise de GoldGestion. L’application est pensée pour l’iPhone
uniquement.

## Mot de passe

Réglé dans Render : service *mon-cours-or* > **Environment** > variable
`GOLDAPP_PASSWORD` (jamais dans le dépôt). Render redémarre le service tout seul.
L’iPhone le retient 180 jours ; « Verrouiller l’application », en bas de l’onglet Cours,
le redemande. Changer le mot de passe déconnecte tous les appareils. Sans cette variable,
l’application reste ouverte à tous.

## Widget iPhone

Cours et courbe sur l’écran d’accueil grâce à l’app Scriptable : script
`widget/Orbismini-widget.js`, mode d’emploi `widget/LISEZ-MOI-WIDGET.txt`. Le widget lit
`/api/widget` avec sa propre clé (`GOLDAPP_WIDGET_KEY` sur Render), sans le mot de passe.

## Sources des cours

| Cours | Source | Secours |
|---|---|---|
| Or pur · 1 kg | Kitco, cours Bid en €/kg | BullionVault, signalé à l’écran |
| Pièces et lingots | Cotations CPoR (Loomis) | derniers cours conservés |
| Argent C3E achat (bijoux argent) | Cookson-Clal | derniers cours conservés |
| Pièces d’argent | Gold.fr | derniers cours conservés |
| Graphiques or et argent | BullionVault | dernier historique conservé |

## Fichiers

- `index.html`, `style.css` : page et mise en page (couleurs GoldGestion).
- `app.js` (cours, prix d’achat), `gold-chart.js`, `silver.js`, `c3e.js`, `freshness.js`.
- `meteo.js` (onglet Météo) et `meteo_or.py` (calcul des indices, repris de GoldGestion).
- `alerte.py` : alerte de cours commune avec Orbis ; `alerte_appareils.py` : alerte propre à
  chaque téléphone (gardée sur GitHub, branche « alertes ») ; page : `alerte-cours.js`.
- `cours-plus.js` : recherche, favoris, prix qui clignotent, alerte cours périmés,
  écran d’ouverture.
- Calculs repris de l’ancienne GoldApp : `estimation.js` + `estimation.css`, `alignment.js`,
  `fiscal.js`, `mobile.js` (onglets, achat bijoux), `quick-prices.js`, `print.js` + `print.css`.
- `edit-fields.js` : montants et pourcentages présélectionnés au premier toucher.
- `update.js` : annonce « Une nouvelle version est disponible » (quand `VERSION` de `sw.js` change).
- Onglet Pièces : `scan.js` (page) et `pieces_scan.py` (Numista et Claude, repris du scanner
  de pièces d’Orbis).
- Tickets de frais : `ticket.js` (photo, scellé et signé sur le téléphone), `scan-feuille.js`
  (recadrage sur la feuille A4 ou la carte d’échelle, repris tel quel d’Orbis) et
  `tickets_boite.py` (boîte aux lettres entre le téléphone et les PC).
- Orbiscan : `orbiscan-cadre.js` (bouton de la barre du bas), `orbiscan-shim.js` (photos
  chiffrées sur le téléphone), `orbiscan_tunnel.py` (passage vers le relais du PC) et
  `orbiscan_pc.py` (PC retenus, gardés sur GitHub).
- Serveur : `server.py` et `kitco.py`, `cpor.py`, `bullionvault.py` (cours de secours),
  `bullionvault_history.py` (graphiques), `market.py`.
- `icon.svg`, `icon.png`, `favicon.ico` : icône d’Orbismini, tirée du logo d’Orbis ;
  `manifest.webmanifest` : nom et icône sur l’écran d’accueil ; `logo-cndo.png` : logo des
  estimations imprimées.
- `img/cpor/` (or) et `img/argent/` (argent, d’après Gold.fr) : vignettes des produits.
- `docs/historique/` : anciennes notes de version (non publiées).

## Nouvelle version

Changer `VERSION` dans `sw.js` et les `?v=` de `index.html` (même valeur).

## Tests

    python -m unittest discover -s tests -t .
