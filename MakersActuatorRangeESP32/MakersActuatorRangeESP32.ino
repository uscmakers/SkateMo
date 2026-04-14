#define PIN_SLIDE_POT_A 35

// Targets
#define RIGHT_TARGET 4000
#define LEFT_TARGET 750
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

String command = "";

enum State {STOP, LEFT, RIGHT, STRAIGHT};
State currentState = STOP;

// --- Variable to track the last time we printed to the Serial monitor ---
unsigned long lastPrintTime = 0; 

void setup() {
  Serial.begin(115200);

  pinMode(PIN_SLIDE_POT_A, INPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);

  ledcAttach(ENA, pwmFreq, pwmResolution);
  ledcWrite(ENA, motorSpeed);

  stopMotor();

  Serial.println("Commands: left, right, straight, stop");
}

void loop() {
  int pos = analogRead(PIN_SLIDE_POT_A);

  // --- Serial ---
  if (Serial.available()) {
    command = Serial.readStringUntil('\n');
    command.trim();

    if (command == "left") currentState = LEFT;
    else if (command == "right") currentState = RIGHT;
    else if (command == "straight") currentState = STRAIGHT;
    else if (command == "stop") currentState = STOP;
  }

  // --- Choose target ---
  int target = MID_TARGET;

  if (currentState == LEFT) target = LEFT_TARGET;
  else if (currentState == RIGHT) target = RIGHT_TARGET;
  else if (currentState == STRAIGHT) target = MID_TARGET;

  // --- Non-Blocking Serial Print (Prevents Flooding) ---
  if (millis() - lastPrintTime >= 250) {
    Serial.print("Pos: ");
    Serial.print(pos);
    Serial.print(" | Target: ");
    Serial.println(target);
    
    // Reset the timer
    lastPrintTime = millis();
  }

  // --- STOP OVERRIDE ---
  if (currentState == STOP) {
    stopMotor();
    delay(50);
    return;
  }

  // --- HARD SAFETY (no oscillation) ---
  if (pos >= RIGHT_LIMIT) {
    stopMotor();
    Serial.println("RIGHT LIMIT HIT");
    delay(100);
    return;
  }

  if (pos <= LEFT_LIMIT) {
    stopMotor();
    Serial.println("LEFT LIMIT HIT");
    delay(100);
    return;
  }

  // --- CONTROL ---
  // If current pos is smaller than target, move towards higher numbers (Right)
  if (pos < target - TOLERANCE) {
    moveForward();
  }
  // If current pos is larger than target, move towards lower numbers (Left)
  else if (pos > target + TOLERANCE) {
    moveBackward();
  }
  else {
    stopMotor();
  }

  delay(30);
}

// --- Motor ---

// Moves towards higher numbers (Right Target = 4000)
void moveForward() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
}

// Moves towards lower numbers (Left Target = 750)
void moveBackward() {
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
}

void stopMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
}