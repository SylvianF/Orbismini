# Orbismini pour iPhone (application native)

Branche `app-ios` seulement : rien ici ne change le site (main reste ce que Render met en ligne).

## Ce qu’il y a

- **Cours** (natif) : or et argent pur au kilo, variation, courbe (1 jour, 7 jours, 1 mois, 1 an),
  lecture du cours au doigt sur la courbe. Derniers cours gardés : affichés hors connexion, avec
  l’heure. Quand Render dort, l’application patiente (jusqu’à 3 essais) et le dit.
- **Météo de l’or** (natif), **Alerte de cours** (natif, même alerte que le site sur ce téléphone).
- **Widget** : petit, moyen, grand ; or ou argent, période au choix (appui long → Modifier le
  widget). Même contenu que le widget Scriptable. Toucher = ouvrir l’application.
- **Scan, Rachat, Chiffres**, et la liste des pièces et lingots : les pages du site, dans
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

Fait (compte individuel, « Abonnement confirmé » reçu). Pour vérifier qu’il est bien actif :
sur le PC, developer.apple.com → Account (connexion avec ton identifiant Apple) → la page
affiche « Apple Developer Program » avec une date d’expiration dans un an. Sur l’iPhone, l’app
Apple Developer → Compte montre la même chose.

### Maintenant que le compte est actif (sur le PC, dans le navigateur)

1. **Identifiant d’équipe** (Team ID, 10 caractères, lettres et chiffres) : developer.apple.com →
   Account → Membership details → « Team ID ».
2. **Clé API App Store Connect** (pour que GitHub signe et envoie l’application) :
   appstoreconnect.apple.com → Utilisateurs et accès → Intégrations → Clés de l’API
   App Store Connect → « + ». Nom : GitHub ; accès : **Admin**. Note l’**ID de la clé** et
   l’**ID de l’émetteur** (Issuer ID, en haut de la page), puis télécharge le fichier
   `AuthKey_XXXXXXXXXX.p8` (téléchargeable une seule fois : range-le à l’abri).
3. **Secrets GitHub** : github.com/Tawek8/mon-cours-or → Settings → Secrets and variables →
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
5. **Envoi** : github.com/Tawek8/mon-cours-or → Actions → « Application iPhone → TestFlight » →
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

Ensuite, dans l’application : Cours → Alerte de cours → « Recevoir les alertes sur cet iPhone ».
L’écran dit si les alertes arrivent dans l’application ou encore par ntfy.

## Identifiants choisis

Application `fr.cndo.orbismini`, widget `fr.cndo.orbismini.widget`, groupe
`group.fr.cndo.orbismini`. Ils peuvent encore changer, mais seulement avant le premier envoi
TestFlight (ensuite, Apple les garde).
