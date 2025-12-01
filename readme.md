# Radar Lock

Ultrasonic + servo “radar” that is triggered by a loud sound (clap) or a push button, sweeps to search for an object with an HC-SR04 ultrasonic sensor, verifies the detection, then locks & tracks the nearest target. Serial telemetry is emitted for logging/plotting.

- Arduino sketch: `radar/radar.ino`  
- Processing sketch (visualization): `radarlock.pde`  
  - **Remember:** update the serial port inside `radarlock.pde` to match your Arduino port (e.g., `COM3`, `/dev/ttyACM0`, etc.).

---

## Features

- Start radar via:
  - Loud sound detected by the sound sensor (clap trigger), or  
  - Start/stop push button.
- Servo sweep: scans from 0° to 180° to search for objects within a configurable distance.
- Candidate verification:
  - Multiple ultrasonic samples to filter noise before locking.
- Target lock and tracking:
  - Scans a small angular window around the locked angle to continuously follow the closest object.
- UART telemetry:
  - Simple CSV-like output: `MODE,ANGLE,DISTANCE` for plotting or logging.
  - MODE codes:  
    - `S` = Search sample  
    - `V` = Verify  
    - `T` = Track sample  
    - `L` = Locked position

---

## Pinout / Wiring

> **Important:** All grounds must be common (Arduino GND ↔ sensor GND ↔ servo GND).

### Servo

- Signal → `D11` (`SERVO_PIN`)  
- Vcc → `+5V` (or external stable 5V supply)  
- GND → `GND` (common ground)

### Ultrasonic Sensor (HC-SR04)

- TRIG → `D13` (`TRIG_PIN`)  
- ECHO → `D12` (`ECHO_PIN`)  
- Vcc → `+5V`  
- GND → `GND`

### Sound Sensor (Digital Output)

- DO → `D2` (`SOUND_PIN`) — used with `attachInterrupt()`  
- Vcc → `+5V`  
- GND → `GND`  

If your sound module’s digital output is active LOW, change:

