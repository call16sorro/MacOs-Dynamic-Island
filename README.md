# Dynamic Island pour Mac

Transforme l'encoche du MacBook en **Dynamic Island**, comme sur iPhone : elle s'élargit pour afficher la musique, un minuteur ou une notification, et se déplie au survol de la souris.

Sur un Mac sans encoche (ou un écran externe), l'app dessine une fausse encoche en haut de l'écran.

## Fonctionnalités

**En compact (autour de l'encoche)**
- Musique en cours : pochette et égaliseur aux couleurs de la pochette, icône pause quand la lecture est en pause.
- Minuteur / chronomètre en direct, à côté de la musique si les deux tournent.
- Pastilles caméra (verte) et micro (orange) quand une app les utilise.

**Alertes temporaires**
- Branchement / débranchement du chargeur, avec le niveau de batterie.
- Volume et luminosité (jauge).
- Connexion d'AirPods et d'appareils Bluetooth, avec la batterie des écouteurs.
- Notifications des autres apps (clic pour ouvrir l'app).
- Rappel d'un événement du calendrier 5 minutes avant, échéance d'un rappel, fin du minuteur.

**Vue dépliée (au survol)**
- **Accueil** : lecteur complet (précédent / lecture / suivant, barre de progression déplaçable), bascule entre lecteurs (Deezer, YouTube dans Safari, Spotify…), prochain événement du calendrier, minuteur.
- **Rappels** : liste des rappels, cocher d'un clic, créer un rappel.
- **Notifications** : les 20 dernières.
- **Étagère** : glissez des fichiers sur l'encoche pour les garder sous la main, les redéposer ailleurs ou les envoyer par AirDrop.

La lecture en cours est lue depuis le « À l'écoute » de macOS : Deezer, Spotify, Musique, Safari, Chrome…

## Prérequis

- macOS 14 (Sonoma) ou plus récent
- Les outils de développement Apple (Xcode ou simplement les *Command Line Tools* : `xcode-select --install`)

## Installation

```bash
git clone https://github.com/call16sorro/MacOs-Dynamic-Island.git
cd MacOs-Dynamic-Island
./build.sh run
```

`build.sh` compile l'app, crée `build/DynamicIsland.app` et la lance (`run`). Sans argument, il compile sans lancer.

L'app vit dans la barre des menus (icône de gélule) : minuteurs, simulations de chaque animation, ouverture au démarrage de la session et Quitter.

## Autorisations

macOS demande certaines autorisations à la première utilisation de chaque fonction :

| Fonction | Autorisation | Où |
|---|---|---|
| Calendrier | Calendriers | demandée au lancement |
| Rappels | Rappels | demandée au lancement |
| AirPods / Bluetooth | Bluetooth | demandée au lancement |
| Contrôle de Musique / Spotify | Automatisation | demandée au premier contrôle |
| Notifications | Accès complet au disque | Réglages › Confidentialité et sécurité, à ajouter à la main |
| Relancer Deezer depuis l'île | Accessibilité | Réglages › Confidentialité et sécurité |

### Signature et autorisations qui se perdent

macOS associe les autorisations à la signature de l'app. Avec une signature « ad hoc » (sans certificat), chaque compilation est vue comme une nouvelle app et les autorisations sont à redonner.

`build.sh` signe donc avec un certificat local nommé **« Dynamic Island Dev »** s'il existe dans le trousseau, sinon en ad hoc (avec un avertissement). Pour créer ce certificat auto-signé :

```bash
cat > /tmp/di-cert.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Dynamic Island Dev
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config /tmp/di-cert.cnf -keyout /tmp/di-key.pem -out /tmp/di-cert.pem
openssl pkcs12 -export -legacy -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -inkey /tmp/di-key.pem -in /tmp/di-cert.pem -name "Dynamic Island Dev" -out /tmp/di.p12 -passout pass:temp
security import /tmp/di.p12 -k ~/Library/Keychains/login.keychain-db -P temp -T /usr/bin/codesign
rm /tmp/di-key.pem /tmp/di.p12
```

Il apparaît comme « non approuvé » dans `security find-identity`, c'est normal et sans conséquence pour la signature.

## Comment ça marche

### Lecture en cours (MediaRemote)

Depuis macOS 15.4, le framework privé MediaRemote (qui alimente « À l'écoute ») refuse les apps tierces. L'app lance donc un petit adaptateur (`Helper/MediaRemoteAdapter.m`) chargé dans `/usr/bin/perl`, un binaire Apple qui y a toujours accès. L'adaptateur envoie l'état de lecture en JSON sur sa sortie standard et reçoit les commandes sur son entrée standard.

> ⚠️ C'est un contournement : Apple peut le bloquer dans une future version de macOS. Dans ce cas, l'app revient automatiquement à un mode de secours limité à Musique et Spotify (notifications distribuées + AppleScript).

Pour basculer vers une app qui n'est plus enregistrée comme lecteur (Deezer une fois en pause), l'île active l'élément « Lecture » de son menu via l'API d'accessibilité.

### Notifications

macOS n'offre pas d'API pour lire les notifications des autres apps. L'app lit donc, en lecture seule, la base du Centre de notifications (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`), d'où le besoin de l'Accès complet au disque. Les bannières de macOS restent affichées en parallèle ; désactivez-les app par app dans Réglages › Notifications si besoin.

## Diagnostics

```bash
# Ce que voit le moniteur de lecture (lecteur, titre, position, lecteurs disponibles)
./build/DynamicIsland.app/Contents/MacOS/DynamicIsland --nowplaying

# Rendu PNG de chaque état de l'île dans un dossier
mkdir -p /tmp/island && ./build/DynamicIsland.app/Contents/MacOS/DynamicIsland --snapshot /tmp/island
```

## Structure

```
Sources/DynamicIsland/
  IslandController.swift   fenêtre, position sur l'encoche, survol
  IslandModel.swift        état de l'île (modes, activités, géométrie)
  IslandView.swift         île, vues compactes et alertes
  ExpandedView.swift       vue dépliée et ses onglets
  NowPlayingMonitor.swift  lecture en cours, bascule entre lecteurs
  MediaRemoteBridge.swift  pilotage de l'adaptateur MediaRemote
  NotificationMonitor.swift, ReminderMonitor.swift, CalendarMonitor.swift,
  TimerManager.swift, SystemHUDMonitor.swift, BluetoothMonitor.swift,
  PrivacyMonitor.swift, BatteryMonitor.swift, ShelfModel.swift
Helper/                    adaptateur MediaRemote (Objective-C + perl)
Resources/Info.plist
build.sh
```

## Limites connues

- Le HUD de volume/luminosité de macOS s'affiche encore en plus de celui de l'île.
- Les notifications ne tiennent pas compte des modes Concentration.
- La lecture en cours et les notifications reposent sur des mécanismes non officiels d'Apple.
