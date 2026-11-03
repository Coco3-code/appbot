// Robot ramasseur de dechets : ESP32 = cerveau.
// - iPhone 8 (camera) ecrit dans VISION  : STOP / POSITION / GO / OBSTACLES
// - iPhone 11 / Android ecrit dans CMD   : A (auto), M (manuel), F B L R (direction), X (stop)
// - L'ESP32 notifie son etat sur STATUS  : 0 manuel, 1 errance, 2 stop dechet, 3 ramassage, 4 securite
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define VISION_UUID  "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CMD_UUID     "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
#define STATUS_UUID  "6E400004-B5A3-F393-E0A9-E50E24DCCA9E"

// ---- Pilote moteurs L298N (adapte les broches a ton cablage) ----
const int ENA = 25, IN1 = 26, IN2 = 27;   // moteur gauche
const int ENB = 14, IN3 = 32, IN4 = 33;   // moteur droit
const int SPEED = 150;                     // 0..255

enum State : uint8_t { MANUEL, ERRANCE, STOP_DECHET, RAMASSAGE, SECURITE };
State state = MANUEL;
BLECharacteristic *statusChar;

// Variables partagees avec les callbacks BLE
volatile bool autoMode = false;
volatile char manualCmd = 'X';
volatile bool dechetStop = false;
volatile bool havePos = false;
volatile uint8_t posX, posY, posW, posH;
volatile uint8_t obstacleMask = 0;
volatile unsigned long lastVisionMs = 0;
unsigned long ignoreUntil = 0;

// ---------- Moteurs ----------
void pwmInit() {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcAttach(ENA, 1000, 8);
  ledcAttach(ENB, 1000, 8);
#else
  ledcSetup(0, 1000, 8); ledcAttachPin(ENA, 0);
  ledcSetup(1, 1000, 8); ledcAttachPin(ENB, 1);
#endif
}

void pwmWrite(int channel, int pin, int value) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWrite(pin, value);
#else
  ledcWrite(channel, value);
#endif
}

void drive(int a, int b, int en, int channel, int v) {
  digitalWrite(a, v > 0);
  digitalWrite(b, v < 0);
  pwmWrite(channel, en, abs(v));
}

void setMotors(int left, int right) {
  drive(IN1, IN2, ENA, 0, left);
  drive(IN3, IN4, ENB, 1, right);
}

void stopMotors() { setMotors(0, 0); }

// ---------- Comportements ----------
void manualDrive() {
  switch (manualCmd) {
    case 'F': setMotors(SPEED, SPEED); break;
    case 'B': setMotors(-SPEED, -SPEED); break;
    case 'L': setMotors(-SPEED, SPEED); break;
    case 'R': setMotors(SPEED, -SPEED); break;
    default:  stopMotors();
  }
}

void wander() {
  bool L = obstacleMask & 1, C = obstacleMask & 2, R = obstacleMask & 4;
  if (C || (L && R)) setMotors(SPEED, -SPEED);   // bloque : pivoter
  else if (L)        setMotors(SPEED, 0);        // obstacle a gauche : tourner a droite
  else if (R)        setMotors(0, SPEED);        // obstacle a droite : tourner a gauche
  else               setMotors(SPEED, SPEED);    // libre : avancer
}

// A REMPLACER quand le bras sera pret.
// x, y = centre du dechet dans l'image (0..255), w, h = taille (0..255).
void pickup(uint8_t x, uint8_t y, uint8_t w, uint8_t h) {
  Serial.printf("Ramasser dechet en x=%u y=%u w=%u h=%u\n", x, y, w, h);
  // TODO : convertir (x, y) en angles de servos, attraper, deposer dans le bac.
  delay(3000);  // simulation
}

void setState(State s) {
  if (s != state) {
    state = s;
    uint8_t b = s;
    statusChar->setValue(&b, 1);
    statusChar->notify();
  }
}

// ---------- Callbacks BLE ----------
class VisionCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) {
    auto v = c->getValue();
    if (v.length() < 1) return;
    switch ((uint8_t)v[0]) {
      case 1: dechetStop = true; havePos = false; break;
      case 2:
        if (v.length() >= 5) {
          posX = (uint8_t)v[1]; posY = (uint8_t)v[2];
          posW = (uint8_t)v[3]; posH = (uint8_t)v[4];
          havePos = true;
        }
        break;
      case 3: dechetStop = false; havePos = false; break;
      case 4:
        if (v.length() >= 2) { obstacleMask = (uint8_t)v[1]; lastVisionMs = millis(); }
        break;
    }
  }
};

class CmdCB : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *c) {
    auto v = c->getValue();
    if (v.length() < 1) return;
    char ch = (char)v[0];
    if (ch == 'A') autoMode = true;
    else {
      if (ch == 'X' || ch == 'M') autoMode = false;  // X = arret d'urgence
      manualCmd = ch;
    }
  }
};

class ServerCB : public BLEServerCallbacks {
  void onConnect(BLEServer *s) { BLEDevice::startAdvertising(); }  // autorise un 2e telephone
  void onDisconnect(BLEServer *s) { manualCmd = 'X'; BLEDevice::startAdvertising(); }
};

// ---------- Setup / loop ----------
void setup() {
  Serial.begin(115200);
  int pins[] = {IN1, IN2, IN3, IN4};
  for (int p : pins) pinMode(p, OUTPUT);
  pwmInit();
  stopMotors();

  BLEDevice::init("ESP32-ROBOT");
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCB());
  BLEService *service = server->createService(SERVICE_UUID);

  BLECharacteristic *vision = service->createCharacteristic(
      VISION_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  vision->setCallbacks(new VisionCB());

  BLECharacteristic *cmd = service->createCharacteristic(
      CMD_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  cmd->setCallbacks(new CmdCB());

  statusChar = service->createCharacteristic(
      STATUS_UUID, BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
  statusChar->addDescriptor(new BLE2902());

  service->start();
  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  BLEDevice::startAdvertising();
}

void loop() {
  static unsigned long last = 0, lastNotify = 0;
  if (millis() - last < 50) return;
  last = millis();

  // Securite : en auto, la camera est le seul detecteur d'obstacles.
  // Si l'iPhone 8 n'envoie plus rien pendant 1,5 s, on s'arrete.
  bool visionAlive = (millis() - lastVisionMs) < 1500;

  if (!autoMode) {
    setState(MANUEL);
    manualDrive();
  } else if (!visionAlive) {
    setState(SECURITE);
    stopMotors();
  } else if (dechetStop && millis() > ignoreUntil) {
    stopMotors();
    setState(STOP_DECHET);
    if (havePos) {
      setState(RAMASSAGE);
      pickup(posX, posY, posW, posH);
      ignoreUntil = millis() + 8000;   // laisse le temps au dechet de disparaitre
    }
  } else {
    setState(ERRANCE);
    wander();
  }

  if (millis() - lastNotify > 1000) {
    lastNotify = millis();
    uint8_t b = state;
    statusChar->setValue(&b, 1);
    statusChar->notify();
  }
}
