#ifdef ARDUINO_ARCH_ESP32
  #include "BLEDevice.h"
  #include "BLEUtils.h"
  #include "BLEServer.h"
#else
  #error "This sketch is for ESP32 only."
#endif

#define SERVICE_UUID        "180C"
#define CHARACTERISTIC_UUID "2A56"

#define PIN1 34
#define PIN2 35

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;

class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
  }
};

const int bufSize = 200;
const unsigned long sampleInterval = 5000;  // 5 ms
float Ts = 0.005;

unsigned long lastSample = 0;

int16_t sensorData1[bufSize];
int16_t sensorData2[bufSize];
int sampleIndex = 0;

struct crossCorrReturn {
  int16_t highr;
  int16_t highshift;
};

void setup() {
  Serial.begin(115200);

  analogReadResolution(12);   // ESP32 = 12 bit
  analogSetAttenuation(ADC_11db); // full 3.3V range

  pinMode(PIN1, INPUT);
  pinMode(PIN2, INPUT);

  // BLE Setup
  BLEDevice::init("ESP32_BLE");

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  pCharacteristic->setValue("0");

  pService->start();
  pServer->getAdvertising()->start();

  Serial.println("ESP32 BLE ready");
  lastSample = micros();
}

void loop() {

  unsigned long nowSample = micros();

  if (nowSample - lastSample >= sampleInterval) {
    lastSample += sampleInterval;

    int16_t currentData1 = analogRead(PIN1);
    int16_t currentData2 = analogRead(PIN2);

    sensorData1[sampleIndex] = currentData1;
    sensorData2[sampleIndex] = currentData2;

    sampleIndex++;

    if (sampleIndex >= bufSize) {

      crossCorrReturn result = crossCorr_calculate(sensorData1, sensorData2, bufSize, Ts);

      if (deviceConnected) {
        float delaySeconds = (float)result.highshift / 1000.0;
        pCharacteristic->setValue((uint8_t*)&delaySeconds, sizeof(delaySeconds));
        pCharacteristic->notify();
      }

      sampleIndex = 0;
    }
  }
}

crossCorrReturn crossCorr_calculate(int16_t x[], int16_t y[], int n, float Ts) {

  crossCorrReturn result;

  float mx = 0, my = 0;
  float sx = 0, sy = 0;
  float sxy, r;

  for (int i = 0; i < n; i++) {
    mx += x[i];
    my += y[i];
  }

  mx /= n;
  my /= n;

  for (int i = 0; i < n; i++) {
    sx += (x[i] - mx) * (x[i] - mx);
    sy += (y[i] - my) * (y[i] - my);
  }

  double denom = sqrt(sx * sy);

  int maxShift = 100;
  float highr = -1.0;
  float highshift = 0;

  for (int shift = -maxShift; shift <= maxShift; shift++) {

    sxy = 0;

    for (int i = 0; i < n; i++) {
      int j = i + shift;
      if (j < 0 || j >= n) continue;

      sxy += (x[i] - mx) * (y[j] - my);
    }

    r = sxy / denom;

    if (r > highr) {
      highr = r;
      highshift = shift * Ts;
    }
  }

  result.highr = (int16_t)(highr * 1000.0);
  result.highshift = (int16_t)(highshift * 1000.0);

  return result;
}