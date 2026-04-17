#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ESP32Servo.h>

// ── Potentiometer ────────────────────────────────────────────────
#define PIN_SLIDE_POT_A 35

// Position targets (tuned to your pot's real range)
#define RIGHT_TARGET  850
#define LEFT_TARGET   275
#define MID_TARGET    600

// Hard safety limits
#define RIGHT_LIMIT   950
#define LEFT_LIMIT    100

#define TOLERANCE       25
#define STEER_PWM_SPEED 200

// ── Actuator H-bridge pins ───────────────────────────────────────
const int IN1 = 25;
const int IN2 = 26;
const int ENA = 27;

// ── ESC output ────────────────────────────────────────────────────
// Safe default pin for ESP32 signal output that does not conflict with actuator pins.
const int ESC_PIN = 14;

// Typical RC ESC pulse range is 1000–2000 us. Keep limits configurable and cap throttle.
const int ESC_MIN_US = 1000;
const int ESC_MAX_US = 2000;
const int ESC_THROTTLE_CAP_US = 1500;  // Conservative forward throttle cap.
const int ESC_ARM_DELAY_MS = 2000;

const int THROTTLE_STEP_US = 10;
const int THROTTLE_UPDATE_MS = 20;

// ── BLE config (must match BLEMotorCombined) ─────────────────────
#define SERVICE_UUID        "12345678-1234-1234-1234-123456789012"
#define CHARACTERISTIC_UUID "87654321-4321-4321-4321-210987654321"

BLECharacteristic* pCharacteristic = nullptr;
bool deviceConnected = false;
Servo esc;

// ── Commands ──────────────────────────────────────────────────────
enum Command {
  FWD      = 0,
  BACK     = 1,
  LEFT     = 2,
  RIGHT    = 3,
  CMD_STOP = 4
};

// ── Steering state machine ────────────────────────────────────────
enum State { STOP, STEER_LEFT, STEER_RIGHT, STRAIGHT };
State currentState = STOP;

int currentThrottleUs = ESC_MIN_US;
int targetThrottleUs = ESC_MIN_US;
unsigned long lastThrottleUpdateMs = 0;

void handleCommand(char cmd);

// ── Actuator helpers ──────────────────────────────────────────────
void moveLeft() {
  ledcWrite(ENA, STEER_PWM_SPEED);
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
}

void moveRight() {
  ledcWrite(ENA, STEER_PWM_SPEED);
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
}

void stopSteeringMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  ledcWrite(ENA, 0);
}

// ── ESC helpers ───────────────────────────────────────────────────
int clampEscUs(int value) {
  if (value < ESC_MIN_US) return ESC_MIN_US;
  if (value > ESC_MAX_US) return ESC_MAX_US;
  return value;
}

void writeEscUs(int value) {
  currentThrottleUs = clampEscUs(value);
  esc.writeMicroseconds(currentThrottleUs);
}

void applyFailSafeStop() {
  currentState = STOP;
  targetThrottleUs = ESC_MIN_US;
  stopSteeringMotor();
  writeEscUs(ESC_MIN_US);
}

void updateThrottleRamp() {
  unsigned long now = millis();
  if (now - lastThrottleUpdateMs < THROTTLE_UPDATE_MS) {
    return;
  }
  lastThrottleUpdateMs = now;

  if (currentThrottleUs < targetThrottleUs) {
    writeEscUs(currentThrottleUs + THROTTLE_STEP_US);
  } else if (currentThrottleUs > targetThrottleUs) {
    writeEscUs(currentThrottleUs - THROTTLE_STEP_US);
  }
}

// ── BLE callbacks ─────────────────────────────────────────────────
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("BLE client connected.");
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    applyFailSafeStop();
    Serial.println("BLE disconnected. Fail-safe stop and restart advertising.");
    pServer->startAdvertising();
  }
};

class CharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String value = pCharacteristic->getValue();
    if (value.length() > 0) {
      handleCommand((char)value[0]);
    }
  }
};

// ── Command handler ───────────────────────────────────────────────
void handleCommand(char cmd) {
  switch (cmd) {
    case FWD:
      Serial.println("CMD: FWD -> straight + throttle");
      currentState = STRAIGHT;
      targetThrottleUs = ESC_THROTTLE_CAP_US;
      break;

    case BACK:
      Serial.println("CMD: BACK -> stop steering + throttle min");
      currentState = STOP;
      stopSteeringMotor();
      targetThrottleUs = ESC_MIN_US;
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
      stopSteeringMotor();
      targetThrottleUs = ESC_MIN_US;
      break;

    default:
      Serial.println("CMD: Unknown");
      break;
  }

  if (deviceConnected && pCharacteristic) {
    uint8_t ack = 0x80 | (uint8_t)cmd;
    pCharacteristic->setValue(&ack, 1);
    pCharacteristic->notify();
  }
}

// ── Setup ─────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);

  pinMode(PIN_SLIDE_POT_A, INPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  ledcAttach(ENA, 5000, 8);
  stopSteeringMotor();

  esc.setPeriodHertz(50);
  esc.attach(ESC_PIN, ESC_MIN_US, ESC_MAX_US);
  writeEscUs(ESC_MIN_US);
  targetThrottleUs = ESC_MIN_US;

  Serial.println("Arming ESC at minimum throttle...");
  delay(ESC_ARM_DELAY_MS);
  Serial.println("ESC armed.");

  BLEDevice::init("ESP32-SteerBot");
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharacteristic->setCallbacks(new CharacteristicCallbacks());
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setValue("Unified BLE actuator+ESC ready");

  pService->start();
  BLEDevice::getAdvertising()->addServiceUUID(SERVICE_UUID);
  BLEDevice::getAdvertising()->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("BLE advertising. Waiting for connection...");
}

// ── Loop ──────────────────────────────────────────────────────────
void loop() {
  int potVal = analogRead(PIN_SLIDE_POT_A);

  int target = potVal;
  if      (currentState == STEER_LEFT)  target = LEFT_TARGET;
  else if (currentState == STEER_RIGHT) target = RIGHT_TARGET;
  else if (currentState == STRAIGHT)    target = MID_TARGET;

  if (currentState == STOP) {
    stopSteeringMotor();
  } else {
    if      (potVal < target - TOLERANCE) moveRight();
    else if (potVal > target + TOLERANCE) moveLeft();
    else                                  stopSteeringMotor();
  }

  if (potVal > RIGHT_LIMIT) moveLeft();
  if (potVal < LEFT_LIMIT)  moveRight();

  updateThrottleRamp();
  delay(20);
}
