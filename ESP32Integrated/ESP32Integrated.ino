#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

// =============================
// Steering Slide Pot & Targets
// =============================
#define PIN_SLIDE_POT_A 35

#define RIGHT_TARGET 3600
#define LEFT_TARGET 1500
#define MID_TARGET 2900

#define RIGHT_LIMIT 4000
#define LEFT_LIMIT 1400
#define TOLERANCE 25

// =============================
// Steering Motor Pins
// =============================
const int IN1 = 25;
const int IN2 = 26;
const int ENA = 27;

// =============================
// Steering PWM
// Explicit LEDC channel to avoid ESC conflict
// =============================
const int STEERING_PWM_FREQ = 5000;
const int STEERING_PWM_RESOLUTION = 8;
const int STEERING_PWM_CHANNEL = 0;
const int motorSpeed = 255;

// =============================
// ESC Settings
// Explicit separate LEDC channel
// =============================
const int ESC_PIN = 14;
const int MIN_US = 1000;
const int MAX_US = 2000;

const int ESC_PWM_FREQ = 50;
const int ESC_PWM_RESOLUTION = 16;
const int ESC_PWM_CHANNEL = 1;

int currentEscUs = MIN_US;
unsigned long lastEscUpdate = 0;

// =============================
// BLE UUIDs
// =============================
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

String command = "";

// =============================
// State Machine
// =============================
enum State { STOP, LEFT, RIGHT, STRAIGHT };
State currentState = STOP;

unsigned long lastPrintTime = 0;
unsigned long lastPosCheck = 0;
int lastPos = 0;

// =============================
// BLE Connection State Variables
// =============================
BLEServer* pServer = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// =============================
// ESC Helper Functions
// =============================
uint32_t usToDuty(int us) {
  const uint32_t maxDuty = (1 << ESC_PWM_RESOLUTION) - 1;
  const uint32_t periodUs = 20000;
  return (uint32_t)((((uint64_t)us) * maxDuty) / periodUs);
}

void writeESCus(int us) {
  ledcWriteChannel(ESC_PWM_CHANNEL, usToDuty(us));
}

// =============================
// Steering Motor Functions
// =============================
// Based on your working test code:
// moveForward: IN1 HIGH, IN2 LOW
// moveBackward: IN1 LOW, IN2 HIGH
// Your old position logic called these "left/right", but the working code
// proved these are the actual useful directions.

void moveForward() {
  ledcWriteChannel(STEERING_PWM_CHANNEL, motorSpeed);
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
}

void moveBackward() {
  ledcWriteChannel(STEERING_PWM_CHANNEL, motorSpeed);
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
}

void stopMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  ledcWriteChannel(STEERING_PWM_CHANNEL, 0);
}

// =============================
// BLE Server Callbacks
// =============================
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("BLE Device Connected!");
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("BLE Device Disconnected!");
  }
};

// =============================
// BLE Characteristic Callbacks
// =============================
class MyCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String rxValue = pCharacteristic->getValue().c_str();
    rxValue.trim();

    if (rxValue.length() > 0) {
      Serial.print("Received BLE Command: ");
      Serial.println(rxValue);

      if (rxValue.equalsIgnoreCase("left")) {
        currentState = LEFT;
      }
      else if (rxValue.equalsIgnoreCase("right")) {
        currentState = RIGHT;
      }
      else if (rxValue.equalsIgnoreCase("straight")) {
        currentState = STRAIGHT;
      }
      else if (rxValue.equalsIgnoreCase("stop")) {
        currentState = STOP;
      }
    }
  }
};

// =============================
// Setup
// =============================
void setup() {
  Serial.begin(115200);

  pinMode(PIN_SLIDE_POT_A, INPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);

  // Steering PWM on explicit channel 0
  ledcAttachChannel(
    ENA,
    STEERING_PWM_FREQ,
    STEERING_PWM_RESOLUTION,
    STEERING_PWM_CHANNEL
  );

  stopMotor();

  // ESC PWM on explicit channel 1
  ledcAttachChannel(
    ESC_PIN,
    ESC_PWM_FREQ,
    ESC_PWM_RESOLUTION,
    ESC_PWM_CHANNEL
  );

  Serial.println("Arming ESC...");
  writeESCus(MIN_US);
  delay(3000);
  Serial.println("ESC armed. Ready.");

  Serial.println("Starting BLE...");
  BLEDevice::init("ESP32_Motor_Controller");

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  BLECharacteristic *pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE
  );

  pCharacteristic->setCallbacks(new MyCallbacks());
  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("BLE Ready! Connect to 'ESP32_Motor_Controller' in nRF Connect.");
  Serial.println("Serial commands also work: left, right, straight, stop");
}

// =============================
// Main Loop
// =============================
void loop() {
  // BLE reconnect handling
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);
    pServer->startAdvertising();
    Serial.println("Restarted Advertising...");
    oldDeviceConnected = deviceConnected;
  }

  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  // Serial commands for debugging
  if (Serial.available()) {
    command = Serial.readStringUntil('\n');
    command.trim();

    Serial.print("Received Serial Command: ");
    Serial.println(command);

    if (command.equalsIgnoreCase("left")) {
      currentState = LEFT;
    }
    else if (command.equalsIgnoreCase("right")) {
      currentState = RIGHT;
    }
    else if (command.equalsIgnoreCase("straight")) {
      currentState = STRAIGHT;
    }
    else if (command.equalsIgnoreCase("stop")) {
      currentState = STOP;
    }
  }

  int pos = analogRead(PIN_SLIDE_POT_A);
  int target = MID_TARGET;

  if (currentState == LEFT) {
    target = LEFT_TARGET;
  }
  else if (currentState == RIGHT) {
    target = RIGHT_TARGET;
  }
  else if (currentState == STRAIGHT) {
    target = MID_TARGET;
  }

  bool steeringAtTarget = abs(pos - target) <= TOLERANCE;

  // =============================
  // Steering Closed-Loop Logic
  // =============================
  if (currentState == STOP) {
    stopMotor();
    steeringAtTarget = true;
  }
  else {
    bool allowIncrease = true;
    bool allowDecrease = true;

    if (pos >= RIGHT_LIMIT) {
      allowIncrease = false;
    }

    if (pos <= LEFT_LIMIT) {
      allowDecrease = false;
    }

    // IMPORTANT:
    // This assumes moveBackward() increases the potentiometer value
    // and moveForward() decreases the potentiometer value.
    //
    // If it moves the wrong way, swap moveBackward() and moveForward()
    // in the two blocks below.

    if (pos < target - TOLERANCE && allowIncrease) {
      moveBackward();
      steeringAtTarget = false;
    }
    else if (pos > target + TOLERANCE && allowDecrease) {
      moveForward();
      steeringAtTarget = false;
    }
    else {
      stopMotor();
      steeringAtTarget = true;
    }
  }

  // =============================
  // ESC Control
  // Only spin rear wheels once steering is at target
  // =============================
  int targetEscUs = MIN_US;

  if (currentState != STOP && steeringAtTarget) {
    targetEscUs = MAX_US;
  }

  if (millis() - lastEscUpdate >= 10) {
    if (currentEscUs < targetEscUs) {
      currentEscUs += 20;
      if (currentEscUs > targetEscUs) {
        currentEscUs = targetEscUs;
      }
    }
    else if (currentEscUs > targetEscUs) {
      currentEscUs -= 20;
      if (currentEscUs < targetEscUs) {
        currentEscUs = targetEscUs;
      }
    }

    writeESCus(currentEscUs);
    lastEscUpdate = millis();
  }

  // =============================
  // Debug Printing
  // =============================
  if (millis() - lastPosCheck >= 200) {
    Serial.print("Steering Pos: ");
    Serial.print(pos);
    Serial.print(" | Delta: ");
    Serial.println(pos - lastPos);

    lastPos = pos;
    lastPosCheck = millis();
  }

  if (millis() - lastPrintTime >= 250) {
    Serial.print("State: ");

    if (currentState == STOP) {
      Serial.print("STOP");
    }
    else if (currentState == LEFT) {
      Serial.print("LEFT");
    }
    else if (currentState == RIGHT) {
      Serial.print("RIGHT");
    }
    else if (currentState == STRAIGHT) {
      Serial.print("STRAIGHT");
    }

    Serial.print(" | Pos: ");
    Serial.print(pos);

    Serial.print(" | Target: ");
    Serial.print(target);

    Serial.print(" | AtTarget: ");
    Serial.print(steeringAtTarget ? "YES" : "NO");

    Serial.print(" | SteeringPWM: ");
    Serial.print(steeringAtTarget || currentState == STOP ? 0 : motorSpeed);

    Serial.print(" | ESC us: ");
    Serial.println(currentEscUs);

    lastPrintTime = millis();
  }

  delay(5);
}
