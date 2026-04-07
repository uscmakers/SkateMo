#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ── Potentiometer ────────────────────────────────────────────────
#define PIN_SLIDE_POT_A 35   // GPIO36 = ADC1_CH0 (VP) — safe with BLE, input-only pin

// Position targets (tuned to your pot's real range)
#define RIGHT_TARGET  850
#define LEFT_TARGET   275
#define MID_TARGET    600    // straight ahead

// Hard safety limits
#define RIGHT_LIMIT   950
#define LEFT_LIMIT    100

#define TOLERANCE     25     // deadband to prevent jitter
#define MOTOR_SPEED   200    // PWM speed 0–255

// ── Motor pins ───────────────────────────────────────────────────
// Using BLE-script pins — digital outputs, so ADC2 conflict doesn't apply
const int IN1 = 25;
const int IN2 = 26;
const int ENA = 27;

// ── BLE config ───────────────────────────────────────────────────
#define SERVICE_UUID        "12345678-1234-1234-1234-123456789012"
#define CHARACTERISTIC_UUID "87654321-4321-4321-4321-210987654321"

BLECharacteristic* pCharacteristic = nullptr;
bool deviceConnected = false;

// ── Commands (must match what your app sends as byte values) ─────
enum Command {
  FWD      = 0,
  BACK     = 1,
  LEFT     = 2,
  RIGHT    = 3,
  CMD_STOP = 4    // renamed to avoid clash with State::STOP
};

// ── Steering state machine ────────────────────────────────────────
enum State { STOP, STEER_LEFT, STEER_RIGHT, STRAIGHT };
State currentState = STOP;

void handleCommand(char cmd);

// ── Motor helpers ─────────────────────────────────────────────────
void moveLeft() {
  analogWrite(ENA, MOTOR_SPEED);
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
}

void moveRight() {
  analogWrite(ENA, MOTOR_SPEED);
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
}

void stopMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  analogWrite(ENA, 0);
}

// ── BLE Callbacks ─────────────────────────────────────────────────
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("BLE Client connected!");
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    stopMotor();                      // safety: stop on disconnect
    currentState = STOP;
    Serial.println("Disconnected. Restarting advertising...");
    pServer->startAdvertising();
  }
};

class CharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue();
    if (value.length() > 0) {
      Serial.print("BLE received: 0x");
      Serial.println((uint8_t)value[0], HEX);
      handleCommand((char)value[0]);
    }
  }
};

// ── Command handler ───────────────────────────────────────────────
void handleCommand(char cmd) {
  switch (cmd) {
    case FWD:
      Serial.println("CMD: FWD (straight)");
      currentState = STRAIGHT;
      break;
    case BACK:
      Serial.println("CMD: BACK → stop steering");
      currentState = STOP;       // no reverse steering; adjust if needed
      stopMotor();
      break;
    case LEFT:
      Serial.println("CMD: LEFT");
      currentState = STEER_LEFT;
      break;
    case RIGHT:
      Serial.println("CMD: RIGHT");
      currentState = STEER_RIGHT;
      break;
    case CMD_STOP:
      Serial.println("CMD: STOP");
      currentState = STOP;
      stopMotor();
      break;
    default:
      Serial.println("CMD: Unknown");
      break;
  }

  // Send 1-byte ACK back to client (0x80 | original command)
  if (deviceConnected && pCharacteristic) {
    uint8_t ack = 0x80 | (uint8_t)cmd;
    pCharacteristic->setValue(&ack, 1);
    pCharacteristic->notify();
    Serial.print("ACK sent: 0x");
    Serial.println(ack, HEX);
  }
}

// ── Setup ─────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);

  pinMode(PIN_SLIDE_POT_A, INPUT);   // GPIO35 is input-only, no pull needed
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(ENA, OUTPUT);
  stopMotor();

  // BLE init
  BLEDevice::init("ESP32-SteerBot");
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ  |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setValue("SteerBot ready");

  pService->start();
  BLEDevice::getAdvertising()->addServiceUUID(SERVICE_UUID);
  BLEDevice::getAdvertising()->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising. Waiting for connection...");
}

// ── Loop ──────────────────────────────────────────────────────────
void loop() {
  int potVal = analogRead(PIN_SLIDE_POT_A);   // 0–4095 on ESP32

  Serial.print("Pot: ");
  Serial.println(potVal);

  // Determine target position from current state
  int target = potVal;   // default: no movement
  if      (currentState == STEER_LEFT)  target = LEFT_TARGET;
  else if (currentState == STEER_RIGHT) target = RIGHT_TARGET;
  else if (currentState == STRAIGHT)    target = MID_TARGET;

  // ── Closed-loop steering control ──
  if (currentState == STOP) {
    stopMotor();
  } else {
    if      (potVal < target - TOLERANCE) moveRight();
    else if (potVal > target + TOLERANCE) moveLeft();
    else                                  stopMotor();   // within deadband → hold
  }

  // ── Hard safety limits (override everything) ──
  if (potVal > RIGHT_LIMIT) moveLeft();
  if (potVal < LEFT_LIMIT)  moveRight();

  delay(50);
}