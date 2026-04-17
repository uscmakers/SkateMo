#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <ESP32Servo.h> // Make sure you have the ESP32Servo library installed

// --- Steering Slide Pot & Targets ---
#define PIN_SLIDE_POT_A 35
#define RIGHT_TARGET 4025
#define LEFT_TARGET 850
#define MID_TARGET 2300

#define RIGHT_LIMIT 4094
#define LEFT_LIMIT 700
#define TOLERANCE 25

// --- Steering Motor Pins ---
const int IN1 = 25;
const int IN2 = 26;
const int ENA = 27;

// --- PWM (ESP32 core v3) for Steering ---
const int pwmFreq = 5000;
const int pwmResolution = 8;
const int motorSpeed = 180;

// --- ESC Settings ---
const int ESC_PIN = 14;          
const int MIN_US = 1000;        // 0% throttle (stop)
const int MAX_US = 2800;        // 40% throttle cap (Try 2000 if 2800 fails)
Servo esc;

int currentEscUs = MIN_US;       // Tracks the current speed of the ESC
unsigned long lastEscUpdate = 0; // Timer for non-blocking ESC ramp

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

        if (rxValue.equalsIgnoreCase("left")) currentState = LEFT;
        else if (rxValue.equalsIgnoreCase("right")) currentState = RIGHT;
        else if (rxValue.equalsIgnoreCase("straight")) currentState = STRAIGHT;
        else if (rxValue.equalsIgnoreCase("stop")) currentState = STOP;
      }
    }
};

void setup() {
  Serial.begin(115200);

  // --- Prevent Timer Conflicts between standard PWM and ESP32Servo ---
  ESP32PWM::allocateTimer(0);
  ESP32PWM::allocateTimer(1);
  ESP32PWM::allocateTimer(2);
  ESP32PWM::allocateTimer(3);

  // Steering Setup
  pinMode(PIN_SLIDE_POT_A, INPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);

  ledcAttach(ENA, pwmFreq, pwmResolution);
  ledcWrite(ENA, motorSpeed);
  stopMotor();

  // --- ESC Setup ---
  esc.setPeriodHertz(50); // CRITICAL: Standard ESCs require 50Hz 
  esc.attach(ESC_PIN, 500, 3000); 
  
  Serial.println("Arming ESC...");
  esc.writeMicroseconds(MIN_US);
  
  // Give ESC plenty of time to read the low signal before doing anything else
  delay(3000); 
  Serial.println("ESC armed. Ready.");

  // --- BLE Setup ---
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
}

void loop() {
  // --- BLE Reconnection Logic ---
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); 
      pServer->startAdvertising(); 
      Serial.println("Restarted Advertising...");
      oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
  }

  // --- Serial Command Override ---
  if (Serial.available()) {
    command = Serial.readStringUntil('\n');
    command.trim();

    if (command.equalsIgnoreCase("left")) currentState = LEFT;
    else if (command.equalsIgnoreCase("right")) currentState = RIGHT;
    else if (command.equalsIgnoreCase("straight")) currentState = STRAIGHT;
    else if (command.equalsIgnoreCase("stop")) currentState = STOP;
  }

  // --- 1. Steering Motor Control ---
  int pos = analogRead(PIN_SLIDE_POT_A);
  int target = MID_TARGET;

  if (currentState == LEFT) target = LEFT_TARGET;
  else if (currentState == RIGHT) target = RIGHT_TARGET;
  else if (currentState == STRAIGHT) target = MID_TARGET;

  if (currentState == STOP) {
    stopMotor();
  } else {
    bool allowMoveRight = true; 
    bool allowMoveLeft = true;  

    if (pos >= RIGHT_LIMIT) allowMoveRight = false; 
    if (pos <= LEFT_LIMIT) allowMoveLeft = false;  

    if (pos < target - TOLERANCE && allowMoveRight) {
      moveRight();
    }
    else if (pos > target + TOLERANCE && allowMoveLeft) {
      moveLeft();
    }
    else {
      stopMotor();
    }
  }

  // --- 2. ESC Motor Control (Non-Blocking Ramp) ---
  int targetEscUs = (currentState == STOP) ? MIN_US : MAX_US;

  if (millis() - lastEscUpdate >= 10) {
    if (currentEscUs < targetEscUs) {
      currentEscUs += 20; // FASTER RAMP: Increased from 5 to 20
      if (currentEscUs > targetEscUs) currentEscUs = targetEscUs; 
    } 
    else if (currentEscUs > targetEscUs) {
      currentEscUs -= 20; // FASTER RAMP: Increased from 5 to 20
      if (currentEscUs < targetEscUs) currentEscUs = targetEscUs;
    }
    
    esc.writeMicroseconds(currentEscUs);
    lastEscUpdate = millis();
  }

  // --- Debug Printing ---
  if (millis() - lastPrintTime >= 250) {
    Serial.print("Pos: ");
    Serial.print(pos);
    Serial.print(" | Target: ");
    Serial.print(target);
    Serial.print(" | ESC (us): ");
    Serial.println(currentEscUs);
    lastPrintTime = millis();
  }

  delay(5); 
}

// --- Motor Functions ---
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