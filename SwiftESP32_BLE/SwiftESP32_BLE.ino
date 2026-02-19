#include <BLEDevice.h>    // Core BLE library - handles device initialization
#include <BLEServer.h>    // Allows ESP32 to act as a BLE server (peripheral)
#include <BLEUtils.h>     // Utility helpers for BLE operations
#include <BLE2902.h>      // Descriptor required to enable BLE notifications

// UUIDs uniquely identify your BLE service and characteristic
// Think of the Service like a container, and the Characteristic as the data slot inside it
// These can be any valid UUID - they just need to match what the client (nRF / Swift app) looks for
#define SERVICE_UUID        "12345678-1234-1234-1234-123456789012"
#define CHARACTERISTIC_UUID "87654321-4321-4321-4321-210987654321"

BLECharacteristic* pCharacteristic = nullptr;  // Pointer to our characteristic, declared globally so loop() can access it
bool deviceConnected = false;                  // Tracks whether a client is currently connected

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
  void onWrite(BLECharacteristic* pCharacteristic) {   // Fires when client writes a value
    String value = pCharacteristic->getValue();       // Use Arduino String, not std::string
    if (value.length() > 0) {                         // Only process if data isn't empty
      Serial.print("Received: ");
      Serial.println(value);                          // Arduino String works directly with Serial.println, no .c_str() needed
    }
  }
};

void setup() {
  Serial.begin(115200);              // Start Serial Monitor at 115200 baud rate for debugging output
  Serial.println("Starting BLE...");

  BLEDevice::init("ESP32-Test");     // Initialize the BLE stack and set the device name (visible during scan)

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
  if (deviceConnected) {                        // Only send data if a client is connected
    static int counter = 0;                     // static keeps the value between loop() calls instead of resetting each time
    char msg[32];                               // Character buffer to hold our outgoing message (32 bytes max)
    snprintf(msg, sizeof(msg), "Ping: %d", counter++);  // Format the message safely into the buffer, then increment counter
    pCharacteristic->setValue(msg);             // Update the characteristic's value with our new message
    pCharacteristic->notify();                  // Push the updated value to the connected client via notification
    Serial.print("Sent: ");
    Serial.println(msg);                        // Log what we sent to Serial Monitor
    delay(2000);                                // Wait 2 seconds before sending the next update
  }
}