# Robot ramasseur de dechets

| Element | Role | Dossier |
|---|---|---|
| iPhone 8 (sur le robot) | Camera + YOLO : detecte `dechet` et `obstacle`, envoie STOP / position / obstacles | `vision-iphone8/` |
| ESP32 | Cerveau : roues, errance, evitement, bras (a brancher), etat | `esp32_robot/` |
| iPhone 11 + Android | Telecommande : AUTO / MANUEL / fleches / STOP | `remote-app/` |

## 1. Modele YOLO (Google Colab)
`data.yaml` avec exactement : `names: ['dechet', 'obstacle', 'personne']`
(ajoute des photos de personnes : le robot s'arrete des qu'il en voit une)
```python
!pip install ultralytics
from ultralytics import YOLO
YOLO("yolov8n.pt").train(data="data.yaml", epochs=50, imgsz=320)
YOLO("runs/detect/train/weights/best.pt").export(format="coreml", nms=True, imgsz=320)
```
Place `best.mlpackage` dans `vision-iphone8/Sources/Model/`.

## 2. Compiler (GitHub, gratuit, sans Mac)
Depot GitHub public, pousse tout ce dossier, puis onglet Actions :
- "Build iPhone 8 vision" -> artefact `vision-iphone8-ipa`
- "Build telecommande" -> `remote-ios-ipa` (iPhone 11) et `remote-android-apk` (Android)

Installe les IPA avec Sideloadly / AltStore (Apple ID gratuit, a renouveler tous les 7 jours).
L'APK s'installe directement sur Android.

## 3. ESP32
Arduino IDE, carte ESP32 : ouvre `esp32_robot/esp32_robot.ino`, adapte les broches
du L298N, televerse. Moniteur serie : 115200.

## Protocole BLE
Service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- `...0002` VISION (iPhone 8 -> ESP32) : `[1]` STOP, `[2,x,y,w,h]` position, `[3]` GO, `[4,masque,personne]` obstacles + presence d'une personne, `[5,dir]` conduite apprise (0 avant, 1 gauche, 2 droite)
- `...0003` CMD (telecommande -> ESP32) : `A` auto, `M` manuel, `F B L R` directions, `X` stop
- `...0004` STATUS (ESP32 -> telecommande et iPhone 8, notify) : 2 octets `[etat, commande manuelle]`, etat : 0 manuel, 1 errance, 2 stop dechet, 3 ramassage, 4 securite, 5 personne, 6 approche

## Conduite apprise (imitation)
1. Installe l'app iPhone 8, connecte le robot, passe en **MANUEL** et touche **Enregistrer la conduite**.
2. Conduis avec la telecommande (20-30 min, lieux varies, corrige quand tu vas vers un obstacle). Touche **Arreter**.
3. Sur l'iPhone 8 : app Fichiers > Sur mon iPhone > YoloBLE > appui long sur `session-...` > Compresser,
   puis envoie le ZIP vers ton PC (Drive, mail...).
4. Ouvre `conduite_apprise.ipynb` dans Google Colab, lance les cellules, envoie le ZIP quand il le demande.
5. Place `drive.mlpackage` dans `vision-iphone8/Sources/Model/` (a cote de `best.mlpackage`), recompile.
6. En AUTO, le robot suit la conduite apprise ; les regles de securite (personne, dechet, camera perdue, obstacle devant) restent prioritaires.

## Regles ("prompt systeme")
Dans `vision-iphone8/Sources/Detector.swift`, le tableau `rules` associe chaque classe a une action
(`stopTotal`, `ramasser`, `eviter`). Pour ajouter une regle : ajoute la classe a ton modele, puis une ligne dans `rules`.

## Capteur HC-SR04 (securite devant)
| HC-SR04 | ESP32-S3 |
|---|---|
| VCC | 5 V (sortie du convertisseur) |
| GND | GND |
| TRIG | GPIO 17 |
| ECHO | GPIO 18, **via un diviseur** : ECHO -> resistance 1 kohm -> GPIO 18 ; du meme point GPIO 18 -> resistance 2 kohm -> GND |

Le diviseur ramene les 5 V du capteur a environ 3,3 V : sans lui, tu abimes l'ESP32.
Seuils dans `esp32_robot.ino` : `STOP_CM` (errance), `MANUAL_STOP_CM` (manuel), `HARD_STOP_CM` (approche).
Place-le a l'avant, a environ 10-15 cm du sol, face vers l'avant.

## Approche du dechet
Quand un dechet est visible mais loin, le robot se centre dessus puis avance lentement.
Il s'arrete et ramasse quand le bas du dechet atteint `NEAR_Y` dans l'image (`esp32_robot.ino`).
Regle `NEAR_Y` en posant un dechet a la distance exacte ou ton bras l'atteint et en lisant la position dans le moniteur serie.

## Securite
- En AUTO, si l'iPhone 8 n'envoie plus rien pendant 1,5 s, le robot s'arrete.
- Le bouton STOP de la telecommande coupe l'AUTO.
- Ajoute un interrupteur physique sur l'alimentation des moteurs et du futur bras.
- Camera seule = seuls les obstacles appris par YOLO sont vus. Teste d'abord a basse vitesse.
