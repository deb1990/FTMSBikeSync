# FTMSBikeSync

A Garmin Connect IQ full-screen Data Field for **fēnix 7/8 series** watches that connects to any FTMS-compatible indoor exercise bike over Bluetooth and displays live metrics during your activity.

## Features

- Connects to any FTMS smart bike (Wahoo, Schwinn, Stages, etc.) via BLE
- Displays live **Power**, **Speed**, **Cadence**, **Distance**, and **Heart Rate**
- HR section background changes colour based on your Garmin HR zones
- Writes metrics to the FIT file using standard field IDs — compatible with **Strava** and **Garmin Connect**
- Auto-scans on activity start, remembers last connected device
- Auto-reconnects if the connection drops mid-ride
- Connection status indicator in the timer label

## Layout

```
┌─────────────────────────┐
│           HR            │  ← Zone-coloured background
│           142           │    (gray / blue / green / orange / red)
├───────────┬─────────────┤
│  DIST km  │  SPD km/h   │
│   12.34   │    28.4     │
├───────────┼─────────────┤
│  PWR W    │  CAD rpm    │
│    247    │     85      │
├─────────────────────────┤
│        TIMER ●          │  ← ● green=connected, yellow=scanning
│        00:00            │
└─────────────────────────┘
```

## Supported Devices

All devices require BLE central mode (the app uses `BleDelegate` for FTMS scanning).

| Device                  | Product ID          |
| ----------------------- | ------------------- |
| fēnix 7                 | `fenix7`            |
| fēnix 7S                | `fenix7s`           |
| fēnix 7X                | `fenix7x`           |
| fēnix 7 Pro             | `fenix7pro`         |
| fēnix 7S Pro            | `fenix7spro`        |
| fēnix 7X Pro            | `fenix7xpro`        |
| fēnix 7 Pro (no Wi-Fi)  | `fenix7pronowifi`   |
| fēnix 7X Pro (no Wi-Fi) | `fenix7xpronowifi`  |
| fēnix 8 43mm            | `fenix843mm`        |
| fēnix 8 47mm            | `fenix847mm`        |
| fēnix 8 Pro 47mm        | `fenix8pro47mm`     |
| fēnix 8 Solar 47mm      | `fenix8solar47mm`   |
| fēnix 8 Solar 51mm      | `fenix8solar51mm`   |
| fēnix E                 | `fenixe`            |

## Requirements

- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) 3.2.0+
- A Garmin developer key
- A supported fēnix 7 or fēnix 8 series watch running Connect IQ 3.2.0 or later
- An FTMS-compatible indoor bike (BLE service UUID `0x1826`)

## Building

```bash
# Install SDK and generate a developer key first
# https://developer.garmin.com/connect-iq/sdk/

monkeyc -f monkey.jungle -o FTMSBikeSync.prg -y ~/developer_key -d fenix7pro
```

For a release package (to submit to the Connect IQ store):

```bash
monkeyc -f monkey.jungle -o FTMSBikeSync.iq -y ~/developer_key -r -e
```

## Simulator Testing

Set `USE_MOCK_DATA = true` in `source/FTMSDataField.mc` before running in the simulator. The simulator does not support BLE and will crash if this flag is `false`.

```bash
monkeyc -f monkey.jungle -o FTMSBikeSync.prg -y ~/developer_key -d fenix7pro
monkeydo FTMSBikeSync.prg fenix7pro
```

Remember to set it back to `false` before deploying to the watch.

## Deploying to Watch

1. Set `USE_MOCK_DATA = false` in `source/FTMSDataField.mc`
2. Build the `.prg` file
3. Enable developer mode on the watch: Settings → About → tap version 7 times
4. Connect via USB (MTP) and copy the `.prg` to `GARMIN/Apps/`
5. Start an activity and select FTMSBikeSync as your data field

## FIT File Fields

Metrics are recorded using standard FIT field IDs for maximum compatibility:

| Field    | ID  | Unit | Notes        |
| -------- | --- | ---- | ------------ |
| Cadence  | 4   | rpm  |              |
| Distance | 5   | m    | stored ×100  |
| Speed    | 6   | m/s  | stored ×1000 |
| Power    | 7   | W    |              |

## Project Structure

```
FTMSBikeSync/
├── manifest.xml              # App manifest (permissions, devices)
├── monkey.jungle             # Build config
├── source/
│   ├── FTMSApp.mc            # App entry point
│   ├── FTMSDataField.mc      # UI layout and FIT recording
│   ├── FTMSBleDelegate.mc    # BLE connection and state machine
│   └── FTMSParser.mc         # FTMS Indoor Bike Data byte parser
└── resources/
    ├── strings/strings.xml   # App name and UI strings
    ├── bitmaps.xml           # Launcher icon reference
    └── images/launcher.png   # 70×70 launcher icon
```

## FTMS Protocol

The app connects to BLE service `0x1826` (Fitness Machine Service) and subscribes to characteristic `0x2AD2` (Indoor Bike Data) notifications.

Byte parsing follows the FTMS specification:

- Flags: `uint16` little-endian
- Speed: bit 0 present, `uint16`, 0.01 km/h per LSB
- Cadence: bit 2 present, `uint16`, 0.5 rpm per LSB
- Distance: bit 4 present, `uint24`, 1 m per LSB
- Power: bit 6 present, `sint16`, 1 W per LSB

## License

MIT
