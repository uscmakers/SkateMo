#include <BLEDevice.h>    // Core BLE library - handles device initialization
#include <BLEServer.h>    // Allows ESP32 to act as a BLE server (peripheral)
#include <BLEUtils.h>     // Utility helpers for BLE operations
#include <BLE2902.h>      // Descriptor required to enable BLE notifications
#include <string>

const int IN1 = 25;
const int IN2 = 26;
const int ENA = 27;
const int DEFAULT_MOTOR_SPEED = 200;

// UUIDs uniquely identify your BLE service and characteristic
// Think of the Service like a container, and the Characteristic as the data slot inside it
// These can be any valid UUID - they just need to match what the client (nRF / Swift app) looks for
#define SERVICE_UUID        "12345678-1234-1234-1234-123456789012"
#define CHARACTERISTIC_UUID "87654321-4321-4321-4321-210987654321"


BLECharacteristic* pCharacteristic = nullptr;  // Pointer to our characteristic, declared globally so loop() can access it
bool deviceConnected = false;                  // Tracks whether a client is currently connected
void handleCommand(uint8_t cmd);
void Motor1_Forward(int speed = DEFAULT_MOTOR_SPEED);
void Motor1_Backward(int speed = DEFAULT_MOTOR_SPEED);
void Motor1_Brake();

enum Command { 
  FWD = 0,
  BACK = 1,
  LEFT = 2, 
  RIGHT = 3,
  STOP = 4,
};

// ServerCallbacks handles connection and disconnection events
// We inherit from BLEServerCallbacks and override the two event functions
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {         // Fires when a client connects
    deviceConnected = true;                    // Update our connection flag
    Serial.println("Connected!");              // Print to Serial Monitor for debugging
  }
  void onDisconnect(BLEServer* pServer) {      // Fires when a client disconnects
    deviceConnected = false;                   // Update our connection flag
    Serial.println("Disconnected. Restarting advertising...");
    pServer->startAdvertising();               // Resume advertising so a new client can connect
  }
};

// CharacteristicCallbacks handles events on the characteristic itself
// In this case, we only care about onWrite - when the client sends data to us
class CharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    std::string value = pCharacteristic->getValue();
    if (!value.empty()) {
      const uint8_t cmd = static_cast<uint8_t>(value[0]);
      Serial.print("Received command byte: 0x");
      Serial.println(cmd, HEX);
      handleCommand(cmd);
    }
  }
};

void setup() {

  //set pin modes of the motor controller on ESP32
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(ENA, OUTPUT);

  Serial.begin(115200);              // Start Serial Monitor at 115200 baud rate for debugging output
  Serial.println("Starting BLE...");

  BLEDevice::init("ESP32-Enum");     // Initialize the BLE stack and set the device name (visible during scan)

  BLEServer* pServer = BLEDevice::createServer();    // Create the BLE server (ESP32 is the peripheral)
  pServer->setCallbacks(new ServerCallbacks());       // Attach our connection/disconnection callback handlers

  BLEService* pService = pServer->createService(SERVICE_UUID);  // Create a BLE service with our defined UUID

  // Create a characteristic inside the service
  // PROPERTY_READ   = client can read the current value
  // PROPERTY_WRITE  = client can write/send a value to us
  // PROPERTY_NOTIFY = we can push updates to the client without them asking
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ   |
    BLECharacteristic::PROPERTY_WRITE  |
    BLECharacteristic::PROPERTY_NOTIFY
  );

  pCharacteristic->setCallbacks(new CharacteristicCallbacks());  // Attach our write callback handler
  pCharacteristic->addDescriptor(new BLE2902());                 // BLE2902 descriptor is required for NOTIFY to work
  pCharacteristic->setValue("Hello from ESP32");                 // Set an initial readable value on the characteristic

  pService->start();  // Start the service so it becomes active and discoverable

  BLEDevice::getAdvertising()->addServiceUUID(SERVICE_UUID);  // Include our service UUID in the advertisement packet
  BLEDevice::getAdvertising()->setScanResponse(true);         // Allow extra data (like device name) to be sent on scan response
  BLEDevice::startAdvertising();                              // Begin broadcasting so clients can find us

  Serial.println("Advertising... Open nRF Connect and scan!");
}

void loop() {
  delay(20);
}

void handleCommand(uint8_t cmd) {
  Serial.print("handleCommand: 0x");
  Serial.println(cmd, HEX);

  switch (cmd) {
    case FWD:
      Serial.println("FWD Received");
      // write commands for straightening out the motor
      Motor1_Forward();
      break; 
    case BACK:
      Serial.println("BACK Received");
      // straighten out and reverse wheels
      Motor1_Backward();
      break;
    case RIGHT:
      Serial.println("RIGHT Received");
      // turn motor right
      break;
    case LEFT:
      Serial.println("LEFT Received");
      // turn motor left
      break;
    case STOP:
      Serial.println("STOP Received");
      Motor1_Brake();
      break;
    default:
      Serial.println("Unknown Command");
      break;
  }

  // send a one-byte ACK back by notifying (0x80 | cmd)
  if (deviceConnected && pCharacteristic) { 
    uint8_t ack = 0x80 | cmd;
    pCharacteristic->setValue(&ack, 1);
    pCharacteristic->notify();
    Serial.print("Sent ACK: 0x");
    Serial.println(ack, HEX);
  }
}

void Motor1_Forward(int Speed)  {
  digitalWrite(IN1,HIGH);
  digitalWrite(IN2,LOW);
  analogWrite(ENA,Speed);
}

void Motor1_Backward(int Speed)  {
  digitalWrite(IN1,LOW);
  digitalWrite(IN2,HIGH);
  analogWrite(ENA,Speed);
}

void Motor1_Brake(){
  digitalWrite(IN1,LOW);
  digitalWrite(IN2,LOW);
  analogWrite(ENA,0);
}
