const int IN1=5;
const int IN2=4;
const int ENA=6;
const int IN3=8;
const int IN4=7;
const int ENB=9;
void setup() {
 pinMode(IN1, OUTPUT);
 pinMode(IN2, OUTPUT);
 pinMode(ENA, OUTPUT);

 pinMode(IN4, OUTPUT);
  pinMode(IN3, OUTPUT);
 pinMode(ENB, OUTPUT);
}
void loop() {
Motor1_Brake();
Motor2_Brake();
delay(100);
Motor1_Forward(200);
Motor2_Forward(200);
delay(1000);
Motor1_Brake();
Motor2_Brake();
delay(100);
Motor1_Backward(200);
Motor2_Backward(200);
delay(1000);
}
void Motor1_Forward(int Speed)
{
 digitalWrite(IN1,HIGH);
 digitalWrite(IN2,LOW);
 analogWrite(ENA,Speed);
}

void Motor1_Backward(int Speed)
{
 digitalWrite(IN1,LOW);
 digitalWrite(IN2,HIGH);
 analogWrite(ENA,Speed);
}
void Motor1_Brake()
{
 digitalWrite(IN1,LOW);
 digitalWrite(IN2,LOW);
}
void Motor2_Forward(int Speed)
{
 digitalWrite(IN3,HIGH);
 digitalWrite(IN4,LOW);
 analogWrite(ENB,Speed);
}

void Motor2_Backward(int Speed)
{
 digitalWrite(IN3,LOW);
 digitalWrite(IN4,HIGH);
 analogWrite(ENB,Speed);
}
void Motor2_Brake()
{
 digitalWrite(IN3,LOW);
 digitalWrite(IN4,LOW);
}