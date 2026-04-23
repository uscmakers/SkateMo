# SkateMo

## Unified ESP32 BLE + Actuator + ESC sketch

- New sketch: `BLEActuatorEscUnified/BLEActuatorEscUnified.ino`
- Combines BLE command handling, closed-loop steering actuator control (potentiometer feedback + H-bridge), and ESC throttle output via `ESP32Servo` (`writeMicroseconds`).
- Keeps BLE UUIDs from `BLEMotorCombined` and sends command ACK as `0x80 | cmd`.
- Uses safe ESC defaults (`1000–2000 us`) with startup arming and BLE-disconnect fail-safe to minimum throttle.
- Default ESC signal pin is GPIO14 (chosen to avoid conflicts with GPIO35/25/26/27 used by steering control).
