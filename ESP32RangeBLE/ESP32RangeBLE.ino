#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

#define PIN_SLIDE_POT_A 35

// Targets
#define RIGHT_TARGET 4025
#define LEFT_TARGET 850
#define MID_TARGET 2300

// Limits
#define RIGHT_LIMIT 4094
#define LEFT_LIMIT 700

#define TOLERANCE 25

// Motor pins
const int IN1 = 25;
const int IN2 = 26;
const int ENA = 27;

// PWM (ESP32 core v3)
const int pwmFreq = 5000;
const int pwmResolution = 8;
const int motorSpeed = 180;

// --- BLE UUIDs ---
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

String command = "";

enum State {STOP, LEFT, RIGHT, STRAIGHT};
State currentState = STOP;

unsigned long lastPrintTime = 0; 

// --- BLE Connection State Variables ---
BLEServer* pServer = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// --- BLE Server Callbacks (Handles Connect/Disconnect) ---
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("BLE Device Connected!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("BLE Device Disconnected!");
    }
};

// --- BLE Characteristic Callbacks (Handles incoming messages) ---
class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue().c_str();
      rxValue.trim(); 

      if (rxValue.length() > 0) {
        Serial.print("Received BLE Command: ");
        Serial.println(rxValue);

        // USE EQUALSIGNORECASE HERE FOR BLUETOOTH
        if (rxValue.equalsIgnoreCase("left")) currentState = LEFT;
        else if (rxValue.equalsIgnoreCase("right")) currentState = RIGHT;
        else if (rxValue.equalsIgnoreCase("straight")) currentState = STRAIGHT;
        else if (rxValue.equalsIgnoreCase("stop")) currentState = STOP;
      }
    }
};

void setup() {
  Serial.begin(115200);

  pinMode(PIN_SLIDE_POT_A, INPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);

  ledcAttach(ENA, pwmFreq, pwmResolution);
  ledcWrite(ENA, motorSpeed);

  stopMotor();

  // --- BLE Setup ---
  Serial.println("Starting BLE...");
  BLEDevice::init("ESP32_Motor_Controller"); 
  
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks()); // Attach server callbacks
  
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
}

void loop() {
  // --- BLE Reconnection Logic ---
  // If the device just disconnected, restart advertising
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); // Give the Bluetooth stack a moment to reset
      pServer->startAdvertising(); 
      Serial.println("Restarted Advertising...");
      oldDeviceConnected = deviceConnected;
  }
  // If a device just connected, update state
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
  }

  // --- Main Control Loop ---
  int pos = analogRead(PIN_SLIDE_POT_A);

  if (Serial.available()) {
    command = Serial.readStringUntil('\n');
    command.trim();

    if (command.equalsIgnoreCase("left")) currentState = LEFT;
  else if (command.equalsIgnoreCase("right")) currentState = RIGHT;
  else if (command.equalsIgnoreCase("straight")) currentState = STRAIGHT;
  else if (command.equalsIgnoreCase("stop")) currentState = STOP;
  }

  int target = MID_TARGET;

  if (currentState == LEFT) target = LEFT_TARGET;
  else if (currentState == RIGHT) target = RIGHT_TARGET;
  else if (currentState == STRAIGHT) target = MID_TARGET;

  if (millis() - lastPrintTime >= 250) {
    Serial.print("Pos: ");
    Serial.print(pos);
    Serial.print(" | Target: ");
    Serial.println(target);
    lastPrintTime = millis();
  }

  if (currentState == STOP) {
    stopMotor();
    delay(30);
    return;
  }

  bool allowMoveRight = true; 
  bool allowMoveLeft = true;  

  if (pos >= RIGHT_LIMIT) {
    allowMoveRight = false; 
  }
  if (pos <= LEFT_LIMIT) {
    allowMoveLeft = false;  
  }

  if (pos < target - TOLERANCE && allowMoveRight) {
    moveRight();
  }
  else if (pos > target + TOLERANCE && allowMoveLeft) {
    moveLeft();
  }
  else {
    stopMotor();
  }

  delay(30);
}

// --- Motor ---
void moveRight() {
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
}

void moveLeft() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
}

void stopMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
}