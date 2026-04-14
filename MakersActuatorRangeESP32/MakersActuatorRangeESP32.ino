#define PIN_SLIDE_POT_A 35

// Targets
#define RIGHT_TARGET 4000
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

  // --- Non-Blocking Serial Print ---
  if (millis() - lastPrintTime >= 250) {
    Serial.print("Pos: ");
    Serial.print(pos);
    Serial.print(" | Target: ");
    Serial.println(target);
    
    lastPrintTime = millis();
  }

  // --- STOP OVERRIDE ---
  if (currentState == STOP) {
    stopMotor();
    delay(30);
    return;
  }

  // --- HARD SAFETY FIX ---
  // Default state allows movement in both directions
  bool allowMoveRight = true; 
  bool allowMoveLeft = true;  

  if (pos >= RIGHT_LIMIT) {
    allowMoveRight = false; // Block moving further right
  }
  
  if (pos <= LEFT_LIMIT) {
    allowMoveLeft = false;  // Block moving further left
  }

  // --- CONTROL ---
  // If current pos is smaller than target AND we aren't at the right limit
  if (pos < target - TOLERANCE && allowMoveRight) {
    moveRight();
  }
  // If current pos is larger than target AND we aren't at the left limit
  else if (pos > target + TOLERANCE && allowMoveLeft) {
    moveLeft();
  }
  else {
    stopMotor();
  }

  delay(30);
}

// --- Motor ---

// Move Right (Increases pos towards 4000)
void moveRight() {
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
}

// Move Left (Decreases pos towards 750)
void moveLeft() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
}

void stopMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
}