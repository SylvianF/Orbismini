# Orbismini pour iPhone (application native)

Dépôt SylvianF/Orbismini, branche `app-ios` seulement : rien ici ne change le site (main reste ce que Render met en ligne).

## Ce qu’il y a

- **Cours** : la page « Cours » du site (courbes de l’or et de l’argent, pièces et lingots), avec
  en haut la cloche de l’alerte de cours et la roue des réglages (thème, widget).
- **Météo de l’or** (natif), **Alerte de cours** (natif, même alerte que le site sur ce téléphone).
- **Widget** : petit, moyen, grand ; or ou argent, période au choix (appui long → Modifier le
  widget). Même contenu que le widget Scriptable. Toucher = ouvrir l’application.
- **Scan, Rachat, Chiffres** : les pages du site, dans
  l’application, avec la même connexion. La barre d’onglets du site y est cachée.
- **Notifications d’Apple** pour les alertes : à côté de ntfy (qui reste pour le Samsung),
  éteintes tant que Render n’a pas `ORBISMINI_APNS=1`.

À savoir : les pages web de l’application ont leur propre mémoire, séparée de Safari. Les
réglages gardés sur le téléphone par le site (jumelage des PC pour Chiffres et Tickets, favoris)
sont à refaire une fois dans l’application.

## Compilation

GitHub Actions, tâche « Application iPhone » : à chaque envoi sur une branche qui touche `ios/`.
XcodeGen fabrique le projet à partir de `project.yml`, puis compilation, tests et captures du
simulateur (artefact « captures-iphone » en bas de la page de la tâche, données d’exemple).

## Ce que toi seul dois fournir, et quand

Ne colle jamais une clé dans une conversation : chaque clé va directement à l’endroit indiqué.

### Compte Apple Developer

Inscription faite (compte individuel, paiement confirmé). Tant que la page developer.apple.com →
Account affiche « (En attente) » à côté de ton nom, Apple n’a pas fini : rien à faire, attendre.
C’est prêt quand Apple envoie l’e-mail de bienvenue dans l’Apple Developer Program et que la
page Account montre « Adhésion » et « Certificats, identifiants et profils » (en général quelques
heures à deux jours ; au-delà : developer.apple.com → Support → Nous contacter → Adhésion).

### Dès que le compte est actif (sur le PC, dans le navigateur)

1. **Identifiant d’équipe** (Team ID, 10 caractères, lettres et chiffres) : developer.apple.com →
   Account → Adhésion (Membership details) → « Team ID ».
2. **Clé API App Store Connect** (pour que GitHub signe et envoie l’application) :
   appstoreconnect.apple.com → Utilisateurs et accès → Intégrations → Clés de l’API
   App Store Connect → « + ». Nom : GitHub ; accès : **Admin**. Note l’**ID de la clé** et
   l’**ID de l’émetteur** (Issuer ID, en haut de la page), puis télécharge le fichier
   `AuthKey_XXXXXXXXXX.p8` (téléchargeable une seule fois : range-le à l’abri).
3. **Secrets GitHub** : github.com/SylvianF/Orbismini → Settings → Secrets and variables →
   Actions → « New repository secret », quatre fois :
   - `APPLE_TEAM_ID` : l’identifiant d’équipe ;
   - `ASC_KEY_ID` : l’ID de la clé ;
   - `ASC_ISSUER_ID` : l’ID de l’émetteur ;
   - `ASC_KEY_P8` : le contenu du fichier `.p8` (ouvre-le avec le Bloc-notes, copie tout, de
     `-----BEGIN PRIVATE KEY-----` à `-----END PRIVATE KEY-----`).
4. **Fiche de l’application** : appstoreconnect.apple.com → Apps → « + » → Nouvelle app :
   iOS, nom « Orbismini », langue Français, identifiant `fr.cndo.orbismini`, référence
   « orbismini ». Si l’identifiant n’est pas dans la liste : lance d’abord la tâche TestFlight
   une fois (elle le déclare chez Apple, puis échoue à l’envoi), puis crée la fiche et relance.
5. **Envoi** : une étiquette « testflight-N » posée sur la branche app-ios (Claude s’en charge), ou plus tard Actions → « Application iPhone → TestFlight » →
   Run workflow (branche `app-ios`). Après le traitement par Apple (10 à 30 minutes), installe
   l’app **TestFlight** sur l’iPhone : Orbismini y paraît. Ajoute l’autre iPhone comme testeur
   (App Store Connect → TestFlight → Testeurs internes).

### Pour les notifications d’Apple (après l’envoi de cette branche sur main)

1. **Clé APNs** : developer.apple.com → Certificates, Identifiers & Profiles → Keys → « + »,
   coche « Apple Push Notifications service (APNs) », télécharge `AuthKey_YYYYYYYYYY.p8`
   (une seule fois) et note son ID.
2. **Render** : service mon-cours-or → Environment, ajoute :
   - `APNS_KEY` : le contenu du fichier `.p8` de la clé APNs ;
   - `APNS_KEY_ID` : son ID (10 caractères) ;
   - `APNS_TEAM_ID` : l’identifiant d’équipe ;
   - `APNS_TOPIC` : `fr.cndo.orbismini` ;
   - en dernier, `ORBISMINI_APNS` : `1` (l’interrupteur ; `0` ou absent = éteint).
3. Render → Settings → Build Command : `pip install -r requirements.txt || echo Ready`
   (installe les deux bibliothèques des notifications ; si elles manquent, le site marche quand même).

Ensuite, dans l’application : Cours → cloche en haut → « Recevoir les alertes sur cet iPhone ».
L’écran dit si les alertes arrivent dans l’application ou encore par ntfy.

## Identifiants choisis

Application `fr.cndo.orbismini`, widget `fr.cndo.orbismini.widget`, groupe
`group.fr.cndo.orbismini`. Ils peuvent encore changer, mais seulement avant le premier envoi
TestFlight (ensuite, Apple les garde).
