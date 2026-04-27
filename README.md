# SkateMo — A Self‑Driving Skateboard

SkateMo (Skateboard + Waymo) is a self-driving skateboard where **the phone is the brain**.

Instead of putting heavy compute and expensive sensors on the board, SkateMo uses a smartphone’s:
- **Camera** (primary perception sensor)
- **On-device processing** (planning + decision-making)
- **UI + connectivity** (operator controls, debugging, mode switching)

The skateboard itself is the real-time “muscle”: an ESP32-based controller that turns the phone’s decisions into precise steering and throttle outputs.

## The Big Idea

SkateMo is built around a clean split:

### Phone (Autonomy + Intelligence)
The phone runs the full autonomy stack:
- Computer vision from the phone camera (lane/feature detection, obstacle cues, target tracking, etc.)
- Motion planning (what the board *should* do next)
- Control decisions (desired steering direction and drive intent)
- App UI (modes, start/stop, debugging views)

### Board (Real-Time Control + Actuation)
The board runs the low-level, timing-critical control:
- Receives commands over **Bluetooth Low Energy (BLE)**
- Drives the **ESC** using servo-style PWM pulses
- Controls **steering actuation** using a motor + position feedback (potentiometer)
- Executes a small state machine so commands translate into consistent movement

This makes the system feel like a product: the phone provides intelligence and iteration speed, while the board provides repeatable control.

## App-Centric Architecture

The SkateMo app isn’t a “remote”—it’s the autonomy runtime.

### What the app does
- **Perception:** processes camera frames on-device
- **Decision making:** turns perception into motion intent
- **Command streaming:** sends frequent control intents over BLE
- **Operator experience:** provides the interface to run the board and visualize what the system “sees”

A typical loop looks like:
1. Capture camera frame
2. Infer driving cues (direction / confidence)
3. Choose motion intent (steer + drive state)
4. Send intent to the board via BLE
5. Repeat

### BLE command interface (current firmware pattern)
Current firmware supports a simple, app-friendly command set:
- `left`
- `right`
- `straight`
- `stop`

These commands map directly into a motion state machine on the ESP32. This approach is intentionally easy to iterate on: you can change autonomy logic in the app without reflashing the board firmware every time.

## Control System (Board Firmware)

### Steering: closed-loop positioning
Steering is position-controlled using analog feedback:
- A potentiometer provides steering position (ADC)
- Firmware drives the steering motor until it reaches a target window for left/right/straight
- A tolerance band makes steering “snap” into stable positions rather than oscillating

### Drive: ESC PWM output
Drive is controlled through an ESC:
- PWM generated via ESP32 LEDC at a standard ESC-friendly rate (e.g., 50 Hz)
- Pulse width set in microseconds (typical 1000–2000 µs)
- Ramping logic smooths transitions so drive changes feel controlled

## Implementation highlight

An integrated sketch combining BLE + steering + ESC control lives here:

- `ESP32Integrated/ESP32Integrated.ino`  
  https://github.com/uscmakers/SkateMo/blob/main/ESP32Integrated/ESP32Integrated.ino

Notable characteristics:
- BLE device name: `ESP32_Motor_Controller`
- BLE write events update the motion state (`STOP`, `LEFT`, `RIGHT`, `STRAIGHT`)
- Steering reaches its target before drive is enabled for consistent execution

## Tech stack

### Phone (autonomy layer)
- Smartphone app (on-device compute + camera perception)
- BLE client connectivity to the board
- Real-time UI for autonomy + control visualization

### Board (actuation layer)
- ESP32 firmware (Arduino framework)
- C/C++
- ESP32 BLE stack (`BLEDevice`, services/characteristics/callbacks)
- ESC control via PWM/LEDC
- Steering actuator control + ADC feedback
