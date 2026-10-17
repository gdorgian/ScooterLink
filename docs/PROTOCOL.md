# Honda RoadSync BLE protocol (PCX 2025)

Notes on how a phone talks to the Bluetooth unit ("BTU") of the Honda PCX 2025 TFT dash.
Worked out from how the official RoadSync Android app talks to the scooter and from logging
the traffic, for interoperability. Everything marked ✅ is confirmed on a real PCX125 (2025);
the rest is unverified.

## Transport

Bluetooth Low Energy. The phone is the central. The unit advertises as `HONDA BTU XXXX`
with the Vehicle Information service. iOS negotiated a 512-byte write MTU ✅.

| Service | UUID |
|---|---|
| Security | `592C1017-9C7B-4A35-ABA6-F268592FB8FC` |
| Data communication | `8536E103-6771-4D4B-9702-287CB5E1340F` |
| Assignment | `F0746E98-61D6-4570-BE7E-7635C65C21CB` |
| Vehicle information | `4D87B1EA-528B-4798-B002-E2E1442A2E86` |
| Firmware update (DFU) | `0EA1BD92-5C48-41AD-9B8F-70DA1BD08F35` (**never write**) |

| Characteristic | UUID | Properties (PCX) |
|---|---|---|
| Security.ControlPoint | `4FA28B27-6938-48F8-980E-7C7C9ACC6C1E` | write |
| Security.DataSource | `EBB3656F-03A5-44CE-A22C-70CFCCF5E247` | read |
| Security.Status | `A65B7152-589E-4933-A426-8F729BFAD439` | read |
| Data.ControlPoint | `D2E23443-F1AD-4293-A70B-A9FD163F7B00` | write-without-response, notify (receipts) |
| Data.Buttons (function source) | `6C060578-D1D9-460A-B86F-EB97F01B2227` | notify |
| Data.DrivingInfo | `BB1D5836-BF35-11ED-AFA1-0242AC120002` | *not present on the PCX* |
| Assignment.Control | `4F5FBE6B-474B-4820-833F-95BFBF525D9F` | write-without-response, notify |
| VehicleInfo: VehicleType, DisplayCapability, SwitchType, CategoryId, SeriesCode, DestinationId | `5738696D-…`, `0AD39E0B-…`, `DDD14E97-…`, `3F033888-…`, `5074E0E8-…`, `55F7910B-…` | read |

PCX125 2025 values ✅: type `01`, display capability `07`, switch type `00`, category `01`,
series code `AE 05`, destination `00`. The unit also exposes the standard Battery service
(`2A19` notifies `0x64` every 10 s), which is handy as a wake-up tick.

## 1. Key exchange (first pairing) ✅

1. Read **Security.Status**: `01` = the unit already holds a key, `00` = no key.
2. With no key: generate an RSA-1024 key pair (e = 65537). Write
   `02 ‖ modulus` (big-endian, no leading zero byte, 128 bytes) to **Security.ControlPoint**.
3. Read **Security.DataSource** (128 bytes) and decrypt it with **raw RSA** (no padding) using the
   private key. Of the 128 plaintext bytes, `[0..110)` is padding, `[110..126)` is the **AES-128 key**,
   and `[126..128)` is a CRC-16 of the key.
4. CRC-16: reflected polynomial `0xA001`, initial value 0, written little-endian (CRC-16/ARC).

The unit keeps **one** key. If another phone/app already paired, delete the pairing on the
dash first.

## 2. Validation (every connection) ✅

- Plaintext: `03 ‖ CRC16(03)` (3 bytes, CRC little-endian).
- Write `01 00 ‖ AES-128-ECB-PKCS7(key, plaintext)` to Security.ControlPoint.
- Read Security.DataSource, drop the first 2 bytes and AES-decrypt the rest. The first byte `01` means OK,
  followed by a 4-byte little-endian counter.

## 3. Assignments (every connection) ✅

Enable notifications on **Assignment.Control**. Then write each registration and wait for its
result notification `[command, requestId lo, requestId hi, status, errorPosition?]`.
Status `1` = OK, `13` = already registered (fine), `11` = invalid ID, `12` = invalid parameters.

Request IDs are 16-bit, written low byte first.

- Function: `01 ‖ id ‖ function ‖ 02` for previous/next/back/select/mute/menu/mode-phone/mode-scooter.
- Volume up / down: `01 ‖ id ‖ 05|06 ‖ 01 07 80|81 00`.
- Colour slot: `02 ‖ id ‖ slot ‖ R G B`. RoadSync registers slots 2–18 (0 = white, 1 = black).
- End: `03`. The PCX never sent a notification for this ✅.

Registrations reset when the ignition is turned on. The **first** RGB registered for a slot after
ignition-on sticks; later writes return `13` and are ignored ✅.

## 4. Phone screen ✅

Write `0A ‖ requestId` (REQUEST_SAB_MODE) to **Data.ControlPoint**. The receipt
`0A ‖ requestId ‖ 01` arrives as a notification, and the dash then reports the mode change as a
button event (`09`). In scooter mode the dash keeps most buttons for its own menus and only
forwards Mute and Mode.

The official app normally relies on the rider pressing the Mode switch and sends this request only
for events like incoming calls. Sending it right after setup works on a clean pairing ✅.

## 5. Button events ✅

Each press is one byte on **Data.Buttons**:

| Byte | Button | | Byte | Button |
|---|---|---|---|---|
| `01` | Previous | | `06` | Volume − (not on PCX) |
| `02` | Next | | `07` | Mute |
| `03` | Back | | `08` | Menu |
| `04` | Select | | `09` | Mode → phone screen |
| `05` | Volume + (not on PCX) | | `0A` | Mode → scooter screen |

Holding a button auto-repeats about every 0.2–0.4 s ✅.

## 6. Drawing on the dash (experimental, unverified ⚠️)

Commands on Data.ControlPoint start with `command ‖ requestId`. The receipt is
`[command, requestId, status, errorPosition?]`, where status `1` means OK.

| Command | Meaning |
|---|---|
| `01` | screen (menu `01` / live `02` body) |
| `02` | pop-up |
| `03` | active indicators |
| `0A` | request phone screen |
| `0B` | firmware update: **never send** |

Live-screen layout:
`01 ‖ id ‖ headerBg ‖ text(header) ‖ 02 ‖ bodyBg ‖ leftAction ‖ rightAction ‖ contentBg ‖ contentIcon[‖ tint] ‖ text(line1) ‖ text(line2)`,

- `text(s)` = `len ‖ utf8 ‖ colour`, or `00` when empty. Lines hold up to 30 characters.
- An action is `00`, or `frameIcon ‖ frameTint ‖ icon ‖ iconTint ‖ bg`.
- The dash has ~130 built-in icons (play `03`, pause `04`, next `05` inside a live-screen action; turn arrows, lanes, weather…). There are no bitmaps.

> ⚠️ After one session that registered colour slots **19–21** and sent a drawn live screen, the
> PCX stopped switching to the phone screen (even via the Mode switch) across ignition cycles.
> Deleting and redoing the pairing fixed it. Change one thing per test.

## Not possible on stock iOS (tried)

- Switching AirPods noise control from an app. The private `AVOutputDevice` setter returns success
  but does nothing, and `BluetoothManager` sees no devices.
- Reading "now playing" for other apps. Sending play/pause/next/previous through MediaRemote
  does work ✅.
