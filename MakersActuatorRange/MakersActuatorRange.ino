#define PIN_SLIDE_POT_A A0

// Position targets
#define RIGHT_TARGET 850
#define LEFT_TARGET 275
#define MID_TARGET 600   // straight

// Safety limits (optional)
#define RIGHT_LIMIT 950
#define LEFT_LIMIT 100

#define TOLERANCE 25   // deadband to prevent jitter

// Motor pins
const int IN1 = 5;
const int IN2 = 4;
const int ENA = 6;

String command = "";

// Current mode
enum State {STOP, LEFT, RIGHT, STRAIGHT};
State currentState = STOP;

void setup() {
  Serial.begin(9600);

  pinMode(PIN_SLIDE_POT_A, INPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
  pinMode(ENA, OUTPUT);

  analogWrite(ENA, 200); // speed (0–255)

  stopMotor();

  Serial.println("Type: left, right, straight, stop");
}

void loop() {
  int poten_read = analogRead(PIN_SLIDE_POT_A);

  // Debug print
  Serial.print("Pot: ");
  Serial.println(poten_read);

  // --- Handle Serial Input ---
  if (Serial.available()) {
    command = Serial.readStringUntil('\n');
    command.trim();

    if (command == "left") {
      currentState = LEFT;
    } 
    else if (command == "right") {
      currentState = RIGHT;
    } 
    else if (command == "straight") {
      currentState = STRAIGHT;
    } 
    else if (command == "stop") {
      currentState = STOP;
    }
  }

  // --- Determine target ---
  int target = poten_read; // default (no movement)

  if (currentState == LEFT) {
    target = LEFT_TARGET;
  } 
  else if (currentState == RIGHT) {
    target = RIGHT_TARGET;
  } 
  else if (currentState == STRAIGHT) {
    target = MID_TARGET;
  }

  // --- Control Logic ---
  if (currentState == STOP) {
    stopMotor();
  } 
  else {
    if (poten_read < target - TOLERANCE) {
      moveRight();   // adjust direction if needed
    } 
    else if (poten_read > target + TOLERANCE) {
      moveLeft();
    } 
    else {
      stopMotor();   // within range
    }
  }

  // --- Safety Clamp ---
  if (poten_read > RIGHT_LIMIT) {
    moveLeft();
  }
  if (poten_read < LEFT_LIMIT) {
    moveRight();
  }

  delay(50); // small delay for stability
}

// --- Motor Functions ---
void moveLeft() {
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
}

void moveRight() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, HIGH);
}

void stopMotor() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
}