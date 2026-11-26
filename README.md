<div align="center">

<img src="docs/icon.png" width="96" alt="Deskwalk" />

# Deskwalk

**Drive your WalkingPad from the Mac menu bar.**
Start walking from a launcher shortcut, see your steps in the menu bar, and send every session to Apple Health.

![macOS](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6-f05138?logo=swift&logoColor=white)
![Bluetooth LE](https://img.shields.io/badge/Bluetooth-LE-0082fc?logo=bluetooth&logoColor=white)

</div>

## ✨ Features

**Walk**

- 🚶 **Menu bar**: steps and speed while the belt runs, the icon greys out when the pad is out of reach
- ▶️ **Go / Stop** from the menu, or from any launcher through a URL
- 🎚️ **Default speed**: pick a speed once, Go starts at it every time (1 to 6 km/h)
- 📊 **Session** in the menu: minutes, distance, steps

**Connect**

- 🔗 **URL scheme**: `walkpad://go`, `walkpad://stop`, `walkpad://speed/3.5`
- ❤️ **Apple Health**: each session lands in iCloud Drive as JSON, an iPhone Shortcut logs it to Health
- 🔌 **Launch at login**: one tick in the menu

**App**

- 🪶 One Swift file, no Xcode project, no dependency
- 🔵 Talks to the pad directly over Bluetooth LE, no pairing

## 🚀 Run it

```sh
git clone https://github.com/mathieuletyrant/deskwalk-app.git
cd deskwalk-app
./build.sh
```

`build.sh` runs the self-test, builds `WalkPad.app`, signs it ad hoc, installs it in `~/Applications` and opens it. Allow Bluetooth on the first launch.

> [!IMPORTANT]
> The pad accepts **one** Bluetooth connection. Quit KS Fit on your phone (or turn the phone's Bluetooth off), or the Mac never finds it.

Supported: WalkingPad **A1, R1, C2, P1** (the KingSmith `FE00` protocol). The app connects to the first device whose name contains `walkingpad` or starts with `KS-`.

## ⌨️ Launchers

Anything that opens a URL works: Raycast, Alfred, Shortcuts, a terminal.

```sh
open walkpad://go          # manual mode, start the belt, then the default speed
open walkpad://speed/4     # change speed now
open walkpad://stop
```

## ❤️ Apple Health

macOS has no Health store, so the iPhone writes it. When the belt stops after a minute or more, Deskwalk saves the session to **iCloud Drive → Shortcuts → WalkPad** as `<timestamp>.json`:

```json
{
  "start": "2026-11-26T10:00:00+01:00",
  "end": "2026-11-26T10:45:00+01:00",
  "durationMin": 45,
  "distanceKm": 2.31,
  "steps": 4210
}
```

Build an iPhone Shortcut:

1. **Get Contents of Folder**: `Shortcuts/WalkPad`
2. **Repeat with Each**, then **Get Dictionary from Input**
3. **Log Health Sample**: Steps = `steps`, from `start` to `end`
4. **Log Health Sample**: Walking + Running Distance = `distanceKm` km, from `start` to `end`
5. **Delete Files**: the item, without confirmation

Then a personal automation (e.g. _When charger is connected_, _Run Immediately_) runs it on its own.

## 🛠️ Develop

```sh
swiftc main.swift -o /tmp/walkpad && /tmp/walkpad --selftest   # protocol self-test
./build.sh                                                     # build, install, relaunch
```

```
main.swift   the whole app: WalkingPad protocol, BLE client, session export, menu bar
icon.swift   renders docs/icon.png, turned into AppIcon.icns by build.sh
Info.plist   bundle: menu bar only, Bluetooth usage, walkpad:// scheme
```

The protocol comes from [ph4-walkingpad](https://github.com/ph4r05/ph4-walkingpad): 6-byte frames `F7 A2 <cmd> <value> <crc> FD` written to `FE02`, status frames `F8 A2 …` notified on `FE01`, one command every 0.7 s.
