# Part 1 — Mobile app (Flutter)

**Owner: T102** · Code: `D:\esp32\mobile`

## Owns
Everything under `D:\esp32\mobile`. Flutter/Dart only.

Key files:
- `lib/ble/ble_relay_connection.dart` — scanning, MTU, GATT subscriptions, parsing
- `lib/link/link_controller.dart` — link selection, force relay hop, peer forwarding
- `lib/screens/home_screen.dart` — UI, link status, force-hop toggle, diagnostics
- `lib/state/sos_controller.dart` — inbound ACK correlation
- `lib/state/alert_controller.dart` — RESCUE/BROAD ingestion + dedup

## Does not own
Firmware, server, or the dashboard. File a change request instead of editing.

## Ship process
```
cd D:\esp32\mobile
flutter analyze --no-pub          # must be clean
flutter build apk --release
```
The release APK is staged to `D:\esp32\dashboard\SAFETRAILS-app-release.apk`
(~49.6 MB). Note this file lives in **Part 4's** folder — do not hand-edit it,
and tell Part 4 when you cut a new one.

## Verify before you claim done
1. Install on a real phone. **The phone must be on the same WiFi as the PC and
   use the PC's LAN IP, never `localhost`** — `localhost` on a phone is the
   phone.
2. Home screen must show **`BLE · Relay connected`**, not `connecting`.
3. Force relay hop **OFF** links to `RCUE`. **ON** links to `N-A`.
4. From the dashboard send RESCUE and BROAD; both must appear in the app.
5. Confirm ACK returns to the row and the row clears.

## Things that already bit us — do not undo
- **Do not gate force-hop scanning behind a cooldown.** When Force hop ON is
  selected it must rescan immediately (400 ms) and blacklist the gateway's
  device id, otherwise it just re-links to `RCUE` and appears broken.
- **Do not set a single red error for a healthy search.** "Searching for relay
  N-A…" and "gateway only, no relay in range" are informational states, not
  failures. Only a real BLE error is red.
- **Do not raise the MTU requirement.** Packets do not fit under 23 bytes.
- Scan **by name** (`SAFETRAILS_RELAY`). Filtering on the service UUID finds
  nothing — the node advertisement intentionally has no 128-bit UUID.

## Inbound wiring already in place
`main.dart` connects `relay.packets` to both `SosController.watchInbound()` and
`AlertController.absorb()`, and `BleRelayConnection` subscribes to `sosRx`,
`rescueRx`, `broadcastRx`, `statusRx`. If an inbound message is missing, look
here **before** suspecting the gateway — and confirm with the gateway log that
`clients=<your id>` was present at send time.
