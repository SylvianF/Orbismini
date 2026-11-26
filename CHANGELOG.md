# Historique

## 26/11/2026 — Estimation envoyée au client ; notifications « achat à risque » et « VD »

- Rachat → Imprimer : dans l'application iPhone, bouton « Envoyer au client » (PDF de la fiche,
  SMS ou e-mail au client). Jamais les pourcentages internes FC / GtaX.
- Serveur : deux nouveaux événements d'Orbis, par ville : « risque » (achat à marge théorique
  négative ou % GtaX inhabituel) et « vd » (vente directe à envoyer ou prête à vendre).

## 26/11/2026 — Alerte de cours : le premier contrôle n'est plus sauté

- Le contrôle des alertes (au plus une fois par minute) partait de l'heure 0 de l'horloge interne :
  juste après un démarrage du serveur, le premier contrôle pouvait être sauté. Vu grâce aux tests
  lancés par GitHub. Site inchangé.

## 26/11/2026 — Tests du serveur : détail des échecs

- Le contrôle « Tests du serveur » affiche chaque échec en clair (annotations), à l'heure de Paris. Site inchangé.

## 26/11/2026 — L'application iPhone réunie avec le site dans main, tests avant mise en ligne

- Le dossier `ios/` (application iPhone, jusqu'ici sur la branche `app-ios`) est fusionné dans
  main : une seule copie du code. Envois TestFlight par étiquette posée sur main, et envoi
  automatique du 1er des mois impairs depuis main.
- Nouveau contrôle « Tests du serveur » (`.github/workflows/serveur.yml`) à chaque envoi ; Render
  ne met en ligne qu'après sa réussite.
- Application : verrou Face ID à la réouverture (après 30 s), réglable par téléphone. Site inchangé.

## 26/11/2026 — Son des notifications : celui d'Orbis

- Sylvian préfère le son d'Orbis à l'arrivée d'une demande de virement (trois notes montantes) :
  c'est lui que joue l'application iPhone, sous le même nom « orbismini.caf ». Il remplace le son
  Mixkit de l'entrée précédente, qui n'a jamais été diffusé. Site inchangé.

## 26/11/2026 — Notifications de l'application iPhone : un son commun

- Les notifications envoyées par Apple demandent le son « orbismini.caf », rangé dans
  l'application (« Melodic bonus collect » de Mixkit, choisi par Sylvian). Une version de
  l'application qui ne l'a pas encore joue le son d'iOS. Site inchangé.

## 26/11/2026 — La date d'actualisation dans la pastille « Tire pour actualiser »

- La pastille qui descend quand on tire l'écran vers le bas affiche aussi « Dernière
  actualisation : … ». L'application iPhone cache la ligne du haut et la montre seulement là.

## 26/11/2026 — Chiffres : une ligne déroulante par transaction

- En dépliant « Achats » ou « Ventes », chaque transaction tient sur une ligne : l'heure, le net
  payé (ou le total TTC pour une vente) et la marge (théorique pour un achat). On la touche pour
  voir les objets. Les lignes ouvertes restent ouvertes d'un rafraîchissement à l'autre.

## 26/11/2026 — Chiffres : « % GtaX » et cours retenu, comme l'Accueil d'Orbis

- Détail des achats : la case s'appelle « % GtaX » et montre dessous, en petit, le cours retenu
  à la saisie (« Cours 1 234,5 »), comme l'Accueil d'Orbis. Données déjà envoyées par Orbis
  (avec le droit marge).

## 25/11/2026 — Notifications d'Orbis : milliers bien séparés

- Les espaces insécables du texte envoyé par Orbis (« 1 240 € ») sont gardées ; elles étaient
  retirées (« 1240 € »). Site inchangé.

## 25/11/2026 — Achats et ventes d'Orbis vers l'application iPhone, ville par ville

- Nouveaux événements `achat` et `vente`, avec une `ville` : `POST /api/orbis/evenement`
  `{type, ville, id, titre, texte}`. Seuls les téléphones cochés pour cette ville les reçoivent.
- Cases d'un téléphone : `virement`, `transfert`, `achat:Nancy`, `vente:Calais`…
  (`POST /api/orbis/telephones`).
- La notification d'un achat ou d'une vente ouvre l'onglet Chiffres de l'application. Site inchangé.

## 25/11/2026 — Demandes de virement et transferts d'Orbis vers l'application iPhone

- `GET /api/orbis/telephones` : téléphones qui ont l'application iPhone, avec le nom qu'on leur a
  donné et les événements qu'ils reçoivent ; `POST` du même chemin : cases cochées dans Orbis.
- `POST /api/orbis/evenement` (`type` : virement ou transfert, `id`, `titre`, `texte`) : Orbis
  annonce une nouvelle demande, envoyée aux seuls téléphones cochés, une fois par annonce.
- Clé d'Orbis seule (`X-Alert-Key`, la même que pour l'alerte commune) ; refus sinon.
- Le nom du téléphone est rangé chiffré dans le dépôt public. Site inchangé.

## 24/11/2026 — Notifications de l'application iPhone (éteintes tant que Render n'a pas la clé)

- `apns.py` : envoi des alertes de cours par les notifications d'Apple, à côté de ntfy (qui reste).
  Éteint tant que `ORBISMINI_APNS` ne vaut pas 1 et que la clé d'Apple manque sur Render.
- `POST /api/apns` : l'application iPhone y dépose l'adresse de notification du téléphone.
- `requirements.txt` (httpx, cryptography) et commande de construction de Render qui les installe ;
  sans elles, le site et ntfy marchent comme avant. Tests : `tests/test_apns.py`.

## 24/11/2026 — Application iPhone : envoi automatique à TestFlight tous les deux mois

- `.github/workflows/ios-testflight.yml` copié sur main : le 1er des mois impairs, l'application
  (branche `app-ios`) est renvoyée à TestFlight, pour que la version installée n'expire jamais
  (90 jours). GitHub ne lance les tâches programmées que depuis main. Rien ne change pour le site.

## 23/11/2026 — Ouverture directe sur une vue (`?vue=`)

- `/?vue=rachat` (ou `meteo`, `scans`, `scan`, `ticket`, `chiffres`) ouvre la page directement sur
  cette vue, sans passer un instant par Cours. Sert à l'application iPhone, qui montre chaque
  vue du site dans son propre onglet. Sans `?vue=`, rien ne change.

## 21/11/2026 — Chiffres : le détail ouvert ne se referme plus tout seul

- Le contrôle de chaque minute ne redessine l'écran que si de nouveaux chiffres sont arrivés, et
  « Achats » ou « Ventes » restent déroulés d'un affichage à l'autre (changement de période compris).

## 21/11/2026 — Chiffres : un cadre par transaction

- Mois préc. et Année : lignes « Charges » et « Résultat » (rouge si négatif), avec le droit
  « Charges et résultat » d'Orbis.
- Lignes déroulables : chevron dessiné qui pivote, toute la ligne à toucher (44 px), nombre de
  transactions en petit (« Achats · 4 »).
- Détail du jour : un cadre par transaction (champ `cadre` d'Orbis 3.1.28, jamais affiché), avec
  l'heure et le net payé additionné pour un achat, le total TTC pour une vente ; dedans, chaque
  objet. Les envois restent sous « Envois ».

## 21/11/2026 — Chiffres : envois séparés dans le détail des ventes

- Détail des ventes : ventes aux clients d'abord, puis « Envois » (GoldTrade, CNDO), pour que les
  lignes retombent sur le total des ventes (format d'Orbis 3.1.26 : champ `to`).

## 21/11/2026 — Chiffres : détail objet par objet du jour

- Aujourd'hui et Hier : les lignes « Achats » et « Ventes » se déroulent et montrent chaque objet,
  comme le survol de l'Accueil d'Orbis (achats : article, titre, poids, heure, taxe comprise, net
  payé, GtaX, marge théorique ; ventes : article, date d'achat, vente TTC, marge HT). Seulement si
  Orbis envoie ce détail (lignes `lines`), selon les droits du téléphone.

## 20/11/2026 — Plus de vide à faire défiler sur les écrans courts

- La page fait au moins la hauteur de l'écran, sans plus (avant : chaque onglet faisait la hauteur
  de l'écran en plus du haut de page, d'où un vide à faire défiler sur Scan, Météo…). La barre du
  bas ne remonte toujours pas.

## 20/11/2026 — Chiffres : Mois, Mois préc. et Année comme le tableau « Exercice comptable »

- Avec les chiffres de l'exercice d'Orbis (source « exercice ») : « Achats HT », « CA HT » (envois
  compris) et « Marge réelle » (marge HT du tableau) ; les lignes TTC absentes ne s'affichent plus.
  Aujourd'hui et Hier ne changent pas.

## 20/11/2026 — Chiffres : un seul cadre, la période en haut

- Un seul cadre avec toutes les lignes (achats, marge théorique, ventes, marge réelle) et, au-dessus,
  les boutons Aujourd'hui · Hier · Mois · Mois préc. · Année ; période choisie retenue.
- Corrigé : « nullnull » affiché sous les chiffres.

## 20/11/2026 — Chiffres : une période par cadre

- Avec un Orbis qui envoie les périodes (après la 3.1.21) : un cadre par groupe (Achats, Marge
  théorique, Ventes, Marge réelle), chacun avec ses boutons Aujourd'hui, Hier (dernier jour
  travaillé), Mois, Mois précédent, Année (exercice de l'agence) ; dates de la période affichées ;
  dernier bouton retenu par cadre. Avec un Orbis plus ancien : affichage d'avant (jour et mois).

## 20/11/2026 — Onglet « Scan » : 5 boutons en bas

- Barre du bas : Cours · Météo · Scan · Rachat · Chiffres (Chiffres seulement pour les téléphones
  autorisés). L'onglet Scan ouvre trois cartes : Orbiscan, Pièce inconnue, Ticket de frais ; retour
  aux cartes en glissant du bord gauche ou en touchant « Scan ».

## 20/11/2026 — Chiffres d'Orbis sur le téléphone

- Onglet « Chiffres », seulement sur un téléphone à qui Sylvian l'a ouvert dans Orbis (Réglages ›
  Téléphones) : ville au choix (retenue), aujourd'hui et mois en cours ; achats (nombre, poids,
  « Achats taxe comprise », « Net payé aux clients »), marge théorique, ventes HT et TTC, marge
  réelle (négative en rouge), seulement les blocs autorisés ; heure de mise à jour, en rouge
  au-delà de 30 minutes.
- Le relais du PC chiffre les chiffres avec une clé tirée du secret de ce téléphone (jumelage des
  tickets) et les dépose dans sa boîte : Orbismini (tickets_boite.Figures) garde le dernier paquet,
  en mémoire, sans pouvoir le lire ni savoir à qui il est. Le plus récent des PC l'emporte.

## 20/11/2026 — Thèmes Onyx et Perle, comme dans Orbis

- Menu « Thème » en bas de l'écran des cours : Saphir (d'origine), Onyx et Perle (clair), avec
  les règles de couleur d'Orbis (theme.js repris d'Orbis, feuilles d'Orbismini recolorées) ;
  choix retenu sur le téléphone, barre d'état du téléphone assortie.

## 20/11/2026 — Ménage du code (suite)

- Rien ne change à l’écran.
- estimation.js : restes de la copie d’Orbis retirés (ensureLine jamais appelée, présélection
  des montants en double avec edit-fields.js, commentaire du scanner).
- pc.json et alertes.json : lecture et écriture sur GitHub écrites une seule fois
  (orbiscan_pc.py), mêmes messages et mêmes fichiers qu’avant.
- README : barre du bas décrite telle qu’elle est (cinq onglets et Orbiscan).

## 20/11/2026 — Ménage du code

- Rien ne change à l’écran.
- Styles .brand-mark et .back retirés (le bouton « Retour aux cours » n’existe plus).
- kitco.py : last_close retirée (appelée nulle part depuis octobre).
- README : liste des fichiers complétée (pièces, tickets, Orbiscan, annonce de mise à jour…).

## 20/11/2026 — Ticket : envoi sans réseau

- Sans réseau (parking en sous-sol) : « Pas de réseau : ticket gardé sur ce téléphone. Il partira
  tout seul dès que le réseau revient » ; dans la liste : « Gardé ici, part au retour du réseau ».
- Envoi aussitôt que le réseau revient (en plus du retour dans l'application, de l'ouverture et
  d'un essai par minute, Orbismini ouvert).

## 20/11/2026 — Ticket : jumelage plus clair

- « Jumeler » sans nom de téléphone ou sans code : message juste sous la ligne du PC, case à
  remplir entourée en rouge et curseur dedans (avant, le message s'affichait plus haut, hors de vue).

## 20/11/2026 — Ticket : carte d'échelle sur papier de couleur

- scan-feuille.js repris d'Orbis (563d4b9) : carte imprimée sur papier coloré (vert) : seul le
  ticket (blanc et noir) est gardé, carte, inscriptions, bureau et ombres effacés, comme un scan.
  Sur carte blanche, rien ne change.

## 20/11/2026 — Ticket : carte d'échelle mieux reconnue

- scan-feuille.js repris d'Orbis (1f60bb0) : seuil propre à la carte d'échelle (carrés imprimés
  gris foncé sur les vraies photos) et carrés de même taille ; les 4 carrés sont reconnus, la
  perspective corrigée.

## 20/11/2026 — Ticket : type de dépense et carte d'échelle

- Type du ticket à choisir comme l'agence (retenu d'une fois sur l'autre) : carburant, péage,
  restaurant ou parking. Scellé et signé avec le reste ; Orbis nomme le PDF « Péage 20.11 (12,40€).pdf »…
- scan-feuille.js repris d'Orbis (395e609) : carte d'échelle imprimée reconnue d'abord (4 carrés de
  8 mm, échelle exacte, perspective corrigée, 3 carrés suffisent), fausses détections écartées.

## 20/11/2026 — Ticket : feuille à petits carreaux avec repères

- scan-feuille.js repris d'Orbis (0119501) : une feuille à petits carreaux portant 3 cases noircies
  en équerre donne l'échelle et l'inclinaison ; la photo devient une page A4 à l'échelle 1,
  redressée, bureau et cases effacés. Sans cases noires, la feuille A4 est reconnue comme avant.

## 20/11/2026 — Ticket : où trouver le code de jumelage

- L'écran Ticket indique où lire le code à 2 chiffres sur le PC : Orbis, Charges → « Téléphones
  des tickets » → « Relier un téléphone ».

## 20/11/2026 — Ticket de carburant envoyé depuis la pompe

- Onglet « Ticket » : agence (Nancy, Troyes, Calais ; la dernière est retenue), photo du ticket
  posé sur une feuille A4 (recadrée sur la feuille par scan-feuille.js, repris d'Orbis, puis remise
  au propre en noir et blanc comme dans Orbis), montant, « Envoyer ». Marche partout, réseau mobile
  compris ; Orbis range le ticket tout seul dans « <Agence> - Orbis range ».
- Sécurité : photo, agence, montant et jour scellés ensemble sur le téléphone pour chaque PC
  jumelé (sa clé publique) et signés avec un secret propre au téléphone et à ce PC (jumelage une
  fois par PC, au magasin, avec le code à 2 chiffres affiché sur le PC). Orbismini
  (tickets_boite.py) ne garde qu'un paquet illisible, en mémoire, effacé dès qu'Orbis l'a rangé ;
  30 tickets par jour et par téléphone ; « Délier » un PC depuis le téléphone.
- Le ticket scellé reste sur le téléphone jusqu'à « Rangé ✓ » et repart tout seul si Orbismini
  l'a perdu (redémarrage). Le relais du PC est prévenu par sa ligne déjà ouverte ; il ne prend un
  ticket que si Orbis tourne sur ce PC, sinon l'autre PC le prend (réservation de 10 minutes).
- Il faut la mise à jour des relais (orbiscan_tickets.py) pour jumeler un PC.

## 20/11/2026 — Proposition de rachat : modifications d'Orbis reprises

- Nom « Proposition de rachat » (au lieu d'« Estimation client »).
- Nouveaux produits : Napoléon 40, 50 et 100 Frs / Lire (toujours Non Boursable, or fin ×
  instantané) et lingotin d'une once.
- Comparer TMP / TPV : prix d'achat du client par unité ou en total.
- Signaux de remise par produit : « ! Limite » sous le seuil, « ✗ Trop bas » sous le minimum
  (bijoux 9 K 25/20 %, 14 K 23/18 %, 18 et 22 K 18/15 %, dentaire 19/16 %, bijoux argent 38/30 %,
  pièces or Non Boursables 12/11 %).
- Pièces or Non Boursables (et Or divers) sous 12 % de FC : fenêtre « Olivier gagne plus que toi
  à ce prix-là ! » (« J'en ai conscience » / « Pas question »).
- Une seule ligne dépliée à la fois ; Pièce Divers : désignation tapée reprise dans le titre.
- Pas repris (propre au PC) : « Dernières propositions » et bouton « Scanner » des lignes Pièce
  Divers.

## 20/11/2026 — Calcul du prix d'achat des pièces en argent ; plus de bouton « Retour aux cours »

- Cours de l'Argent : chaque pièce connue des calculs affiche son prix de rachat et s'ouvre,
  comme les pièces d'or, sur le calcul du prix d'achat (cotation Gold.fr, frais par défaut de
  l'estimation : 34 % pièces françaises, 20 % pièces modernes ; part GoldTrade 9 % ou 5 % ; TMP
  11,5 % ; comparaison TMP / TPV). Le lingot de 1 kg reste en lecture seule.
- Calcul du prix d'achat : bouton « ← Retour aux cours » retiré ; on revient en glissant du
  bord gauche de l'écran.

## 20/11/2026 — Annonce de mise à jour seulement pour une vraie nouvelle version

- « Une nouvelle version est disponible » ne paraît que si la version en ligne diffère de celle
  affichée sur le téléphone (vérifié à l'ouverture et à chaque retour dans l'application).
  Avant, l'annonce pouvait paraître alors que la page était déjà la dernière (copie de secours du
  téléphone renouvelée). Le bouton « Mettre à jour » reste : rien n'est mis à jour sans toi.

## 20/11/2026 — Météo de l'or : RSI comme sur la courbe

- Le RSI de la météo se calcule sur les 20 derniers jours (14 jours de bourse), comme sur la
  courbe d'Orbis, et plus sur 14 jours de calendrier week-ends compris (environ 10 jours de
  bourse) : la météo et la courbe donnent la même valeur.

## 15/11/2026 — Alerte de cours propre à chaque téléphone

- Chaque téléphone a sa propre alerte (seuils, variation sur 24 h) et son propre canal ntfy : les
  autres ne la voient pas, ne la changent pas et ne la reçoivent pas. Identifiant secret tiré à la
  première ouverture, gardé sur le téléphone (Safari et l'icône de l'écran d'accueil comptent
  comme deux téléphones).
- Gardée sur GitHub (fichier alertes.json de la branche « alertes », même clé que les PC
  d'Orbiscan) : seulement l'empreinte de l'identifiant, les seuils et les dernières alertes. Le
  canal ntfy n'y est pas (calculé avec le mot de passe d'Orbismini).
- « Suivre l'alerte d'Orbis », avec le code de Sylvian (ORBISCAN_ADMIN) : ce téléphone règle et
  reçoit l'alerte commune avec Orbis, comme avant ; « Alerte propre à ce téléphone » pour revenir.
- Le contrôle toutes les 10 minutes vérifie les deux, avec un seul relevé du cours.

## 15/11/2026 — Courbe : dernière durée gardée

- À l'ouverture, la courbe du cours reprend la dernière durée consultée (1 j, 7 j, 1 mois, 1 an,
  5 ans ou 10 ans), comme le métal (or ou argent) ; 1 jour seulement la toute première fois.

## 15/11/2026 — Nom « Orbismini » partout

- Widget de l'écran d'accueil (Scriptable) : titre « Orbismini », fichier renommé
  widget/Orbismini-widget.js, mode d'emploi mis à jour. Pour voir le nouveau titre sur un widget déjà
  installé, recopier le script dans Scriptable.
- README, commentaires : Orbismini. Les identifiants internes (canal ntfy orapp-…, clé d'alerte)
  ne changent pas, pour ne pas casser la liaison avec Orbis et l'iPhone.

## 15/11/2026 — Orbiscan : adresse du téléphone impossible à falsifier

- L'adresse internet qui sert à reconnaître la connexion du magasin est lue dans True-Client-IP (ou
  CF-Connecting-IP), posés par Cloudflare devant Render, et plus dans X-Forwarded-For, dont le début
  peut être écrit par l'appelant. Vérifié sur le vrai Render : une fausse adresse est ignorée.

## 15/11/2026 — Orbiscan : chaque PC retenu pour de bon

- À sa première venue, chaque PC est retenu avec l'empreinte de son secret et de sa clé (fichier
  pc.json de la branche orbiscan-pc, sur GitHub) : ensuite, tout autre secret ou toute autre clé
  est refusé, même après un redémarrage de Render. Sans clé GitHub ou si GitHub ne répond pas,
  aucun nouveau PC n'est accepté.
- Page /orbiscan-pc : liste des PC retenus et remise à zéro, avec le code de Sylvian (ORBISCAN_ADMIN).
- Réglages Render à ajouter : ORBISCAN_GITHUB_TOKEN et ORBISCAN_ADMIN.

## 15/11/2026 — Orbiscan : barre du bas toujours visible

- Orbiscan s'ouvre au-dessus de l'écran mais laisse la barre du bas (Cours, Météo, Orbiscan, Pièces,
  Rachat) : un autre bouton de la barre, ou la croix en haut à gauche, referme Orbiscan.

## 15/11/2026 — Orbiscan dans Orbismini

- Le bouton « Orbiscan » ouvre en plein écran la page Orbiscan du PC du magasin, avec seulement
  une croix en haut à gauche pour revenir : plus de fenêtre Safari.
- Les demandes passent par Orbismini (orbiscan_tunnel.py), entièrement en mémoire : rien sur disque
  ni dans les journaux. Chaque photo est chiffrée sur le téléphone avec la clé du PC
  (RSA-OAEP 2048 + AES-256-GCM, orbiscan-shim.js) ; Orbismini refuse toute photo en clair, l'efface
  dès que le PC l'a prise, et oublie tout au bout de 2 minutes.
- Ne marche que sur la connexion du magasin (même sortie internet que le PC). Seules les adresses
  de la page du téléphone passent, jamais celles du scanner GtaX ni d'Orbis.
- Le relais de chaque PC doit être mis à jour (module orbiscan_nuage.py). En attendant, l'écran
  propose d'ouvrir l'Orbiscan du PC par le Wi-Fi, comme avant. L'icône Orbiscan reste inchangée.

## 14/11/2026 — Orbiscan ouvert dans la même fenêtre (essai abandonné)

- Essai d’ouverture dans la même fenêtre qu’Orbismini : pas mieux sur l’iPhone, plutôt moins bien.
  Retour à l’ouverture dans une nouvelle fenêtre.

## 14/11/2026 — Barre du bas : Cours, Météo, Orbiscan, Pièces, Rachat

- Nouvel ordre des boutons : Cours / Météo / Orbiscan / Pièces / Rachat.
- Le bouton « Scan » s’appelle « Orbiscan », avec une icône reprise de celle d’Orbiscan
  (cadre, anneau d’Orbis à trois points, trait de scan).

## 14/11/2026 — Écran d’ouverture : barre dorée horizontale

- L’icône étant au-dessus du nom « Orbismini », la barre dorée passe à l’horizontale, entre les deux.

## 14/11/2026 — Pièces : bouton « Rechercher »

- Sous les photos de la pièce, « Demander à Claude » devient « Rechercher ».
- Recherche par le nom : le bouton devient « Chercher ce nom ».
- Onglet « Pièces » : nouvelle icône, une pièce marquée « ? » dans un cadre photo (au lieu de la loupe).

## 14/11/2026 — OrApp devient Orbismini ; bouton « Scan » vers Orbiscan

- L’application s’appelle maintenant Orbismini (nom, logo, page de connexion, écran d’accueil).
- Nouveau bouton « Scan » à droite de « Rachat » : il ouvre Orbiscan, la page du relais du PC
  (http://orbiscan.local:8790/t). Pièces d’identité, RIB et pièces : les photos vont directement
  du téléphone au PC par le Wi-Fi du magasin, jamais par internet. Ne marche que sur le Wi-Fi
  d’un PC Orbis. L’icône Orbiscan reste utilisable par les collaborateurs.
- L’onglet du scanner de pièces (Claude et Numista) s’appelle maintenant « Pièces ».

## 14/11/2026 — Barre d’onglets qui remontait sur l’onglet Scan

- Chaque onglet est au moins aussi haut que l’écran : sur l’onglet Scan, trop court, Safari
  réaffichait sa barre d’adresse et la barre d’onglets du bas remontait.

## 14/11/2026 — Onglet « Scan » : scanner de pièces

- Nouvel onglet entre Cours et Météo, repris du scanner de pièces d’Orbis : photo de la face
  (et du revers) → « Demander à Claude » → pièces du catalogue Numista ; ou recherche par le
  nom, le pays et l’année. Fiche Numista (métal, titre, poids, diamètre, métal fin, tirage) et
  prix d’achat indicatif (calcul de la ligne « Divers » des tarifs non boursables d’Orbis).
- Clés à saisir dans Render : ANTHROPIC_API_KEY et NUMISTA_API_KEY (jamais dans le dépôt).

## 14/11/2026 — Cours : écran épuré, courbe sur 5 et 10 ans, bande de Bollinger

- Première ligne « Kitco : cours » retirée (le cours est déjà dans le cadre) ; sous le cours,
  la source seulement ; sous la courbe, plus de cours répété (il s’affiche en touchant la courbe).
- Logo : barre dorée verticale entre l’anneau et le nom, reprise du logo d’Orbis.
- Courbe : périodes 5 ans et 10 ans (points de 10 jours et d’un mois de BullionVault).
- Bouton « Bollinger » : moyenne des 20 derniers points ± 2 écarts-types, en bleu.

## 14/11/2026 — Alerte de cours : variation brusque

- Nouveau réglage « Hausse ou baisse de plus de … % sur 24 h » (par rapport au cours de
  BullionVault 24 h plus tôt). Contrairement aux seuils, il reste en place après avoir sonné ;
  une alerte par sens toutes les 20 heures au plus. Commun avec Orbis, notification ntfy.

## 13/11/2026 — Météo : repère « Inflation attendue »

- Inflation attendue aux États-Unis (obligations indexées TIP face aux obligations
  classiques IEF, sur un mois), affichée parmi les repères, sans effet sur le score. Après
  une nette baisse, l’or était plus haut 3 mois plus tard dans 77 % des cas depuis 2003
  (70 à 83 %), contre 64 % en temps normal. Même calcul que dans Orbis.

## 13/11/2026 — Météo : fiabilité de « Et ensuite ? »

- Chaque pourcentage a sa fourchette (là où il tombe 9 fois sur 10, en tirant au sort des
  épisodes entiers) ; couleur seulement si l’écart avec « tous temps confondus » est net.
- Même calcul avant et depuis 2016 : un chiffre qui change de plus de 15 points est signalé
  « instable ». Même calcul que dans Orbis (meteo_or.py).

## 13/11/2026 — Alerte de cours, commune avec Orbis

- Onglet Météo : « Alerte de cours » (prévenir si l’or passe au-dessus ou en dessous d’un
  cours en €/kg). Mêmes seuils que dans Orbis : réglés d’un côté, ils valent partout.
- Notification sur l’iPhone, même OrApp fermée, par l’appli gratuite ntfy (canal secret tiré
  du mot de passe, affiché dans l’onglet). L’alerte sonne une fois puis le seuil est retiré.
- Contrôle du cours toutes les 10 minutes en semaine par GitHub Actions
  (`.github/workflows/alerte-cours.yml`), qui garde aussi le service Render éveillé.
- `alerte.py` : même calcul que `alerte_cours.py` d’Orbis ; Orbis échange avec `/api/alert`
  grâce à une clé tirée du mot de passe (`X-Alert-Key`), jamais le mot de passe lui-même.

## 13/11/2026 — Météo de l’or : historique et « Et ensuite ? »

- Même calcul que la météo d’Orbis : frise des 4 dernières semaines (météo de chaque jour
  ouvré, recalculée avec les cours de fin de journée) et « Et ensuite ? » : ce qui a suivi,
  depuis 2005, les jours de même météo (or plus haut après 1 semaine, 1 mois, 3 mois,
  comparé à tous les jours). Fréquences du passé, pas une prévision.
- Une source qui ne répond pas est nommée clairement (« taux américains », « indice de la
  peur »…) et relue au bout de 5 minutes au lieu de 30.

## 09/11/2026 — GoldApp devient OrApp

- Nouveau nom et nouvelle icône, celle d’Orbis : l’anneau doré et ses trois points.
- Logo complet : `orapp-logo.svg` / `orapp-logo.png`.
- Sur l’iPhone, le nom et l’icône de l’écran d’accueil ne changent qu’en réinstallant l’app
  (Safari, Partager, Sur l’écran d’accueil). Le widget Scriptable affiche « OrApp » une fois
  le nouveau script collé.

## 02/11/2026 — Onglet Météo allégé

- Retrait de l’encadré « Résumé du contexte, pas une prévision… », qui prenait trop de place
  sur l’iPhone. La mention « à titre informatif » reste en bas de l’onglet.

## 02/11/2026 — Frais d’achat par défaut

- Or : 4 % sur le lingot 1 kg, 7,5 % sur les autres pièces et lingots (cours, détail, prix
  rapide, estimation client). Un frais modifié dans le détail ne vaut que pour ce détail.

## 02/11/2026 — Météo de l’or après test sur 22 ans

- Rejouée sur 2005-2026 : pas d’avantage mesurable à 1 semaine ou 1 mois, signal faible et
  instable au-delà. Elle est donc présentée comme un résumé du contexte, pas une prévision.
- Dollar et euro passent en simples repères : ils se contredisaient 2 123 jours sur 2 128.
  Seuils adaptés (0,25 et 0,63) : même météo qu’avant 95 % des jours.
- Une pondération calée sur les résultats n’a pas battu les poids actuels sur les années non
  vues : poids inchangés.

## 02/11/2026 — Météo de l’or

- Nouvel onglet « Météo » entre Cours et Rachat : soleil, éclaircies, temps variable, averses
  ou orage selon les indices de tendance, avec le détail et l’explication de chacun.
  Mêmes indices, seuils et textes que dans GoldGestion (meteo_or.py, tests repris).
- Dernière météo gardée sur l’iPhone si les sources ne répondent pas.

## 29/10/2026 — widget plein

- La courbe du widget remplit tout l’espace libre : taille réelle du widget selon le modèle
  d’iPhone (du SE au Pro Max), au lieu de dimensions fixes.

## 28/10/2026 — widget iPhone

- Widget d’écran d’accueil (app Scriptable) : cours de l’or ou de l’argent avec sa
  courbe et sa variation ; trois tailles, période au choix. Voir widget/LISEZ-MOI-WIDGET.txt.
- /api/widget : lecture seule des cours, ouverte par une clé à part (GOLDAPP_WIDGET_KEY).
- Relecture du widget : compatible iOS 14+, tailles ajustées pour l’iPhone SE, messages
  clairs (clé à coller, clé refusée), délai court pour garder le dernier relevé.

## 28/10/2026 — tirer pour actualiser

- Le bouton « Actualiser » de l’en-tête est remplacé par le geste : tirer l’écran vers le
  bas depuis le haut. Une pastille suit le doigt (« Relâche pour actualiser »), une roulette
  tourne en haut à droite pendant l’actualisation. Le geste marche aussi en partant d’une
  carte produit (pas depuis le graphique, réservé à la lecture des cours).

## 28/10/2026 — graphique de l’argent

- Choix Or / Argent sur le graphique (historique BullionVault, comme GoldGestion) ;
  le choix est retenu. Pour l’argent, le cours affiché est le dernier point BullionVault.

## 28/10/2026 — graphique en premier

- Onglet Cours : le cours de l’or et son graphique en tête, avant la recherche et les favoris.

## 28/10/2026 — mot de passe

- Mot de passe à l’ouverture (variable GOLDAPP_PASSWORD sur Render), retenu 180 jours
  sur l’iPhone ; « Verrouiller l’application » en bas de l’onglet Cours.
- Sans mot de passe, ni la page, ni les cours, ni les scripts ne sont lisibles
  (seule l’icône l’est, pour l’écran d’accueil).
- Dépôt nettoyé : fins de ligne uniformes (.gitattributes).

## 28/10/2026 — confort en déplacement

- Onglets Cours / Rachat en bas de l’écran, au pouce.
- Recherche en haut des cours (« napo », « krug », « 100 g »…).
- Favoris : appui long sur un produit pour l’épingler en haut des cours.
- Variation de l’or sur la période (↑ vert / ↓ rouge) et bulle de lecture sur le graphique.
- Bandeau d’alerte quand le cours de l’or a plus de 30 min.
- Les prix qui changent à l’actualisation clignotent en vert ou en rouge.
- Écran d’ouverture ; vignettes d’argent en meilleure qualité, rondes.

## 28/10/2026 — illustrations de l’argent

- Cours de l’Argent : une vignette par pièce et lingot (images Gold.fr), en cartes
  comme les cours de l’or.

## 28/10/2026 — rangement façon GoldGestion

- Deux onglets, Cours et Rachat : les calculs ne sont plus mélangés aux cours.
- Cours : pièces et lingots affichés ensemble en cartes, avec le prix de rachat sous
  chaque produit ; graphique de l’or toujours visible.
- Icône, couleurs et en-tête de GoldGestion.
- iPhone uniquement : la mise en page PC (qui masquait les cours) est supprimée, ainsi
  que DEMARRER-WINDOWS.bat.
- Six feuilles de style empilées remplacées par style.css et estimation.css.
- Notes de version rangées dans docs/historique/ ; fichiers inutilisés retirés
  (bullionvault-chart.html, print-preview.html, print-view.js, print-document.css,
  cotations.exemple.json).

## 24/10/2026 — samedi

- Kitco : quand le marché est fermé (week-end, pause quotidienne), le cours de
  clôture est accepté au lieu d’être refusé ; l’écran indique « Marché fermé ».

## 24/10/2026 — graphique

- Courbe redessinée : dégradé doré, halo, repère du début de période, plus haut et
  plus bas, dernier cours animé, point de lecture au doigt ou à la souris.

## 24/10/2026 — alignement sur GoldApp

- Calculs repris de GoldApp (FC Agence / % GT, décotes argent 20 / 9 / 5 pt,
  alignement bijoux, saisie directe, « Net à verser » indique ce qui manque).
- Cotations CPoR lues chez Loomis (comme GoldApp) au lieu de Gold.fr.
- Or pur : BullionVault en secours quand Kitco ne répond pas (le week-end notamment).
- Illustrations des pièces et lingotins (mêmes images que GoldApp), lingotin 1 once.
- Cache serveur des cours ; seuls les fichiers de l’application sont publiés.
- Code remis en forme, code mort retiré (goldprice.dev, Frankfurter, fichier
  `cotations.json` qui remplaçait les cours en direct), tests ajoutés.
- Notes de version regroupées dans `docs/historique/`.
