# Part 2 — ESP32 firmware (relay + gateway)

**Owner: N-A** · Code: `D:\esp32\firmware` · Boards: `relay` (N-A) and `gateway` (RCUE)

## Owns
Everything under `D:\esp32\firmware`, plus the root build/flash scripts
`build_relay.py`, `build_gw.py`, `flash_com8.py`, `flash_gw8.py`.

Key files:
- `src/config.h` — node ids, LoRa params, `ST_LED_*`, time/TTL limits
- `src/core/packet.cpp` — JSON encode/decode, 16-char mid cap
- `src/core/router.cpp` — routing, dedup, STALE/FUTURE rejection
- `src/ble/ble_server.cpp` — GATT server, MTU 517, notification delivery
- `src/ble/ble_mesh.cpp` — phone-as-relay forwarding, per-peer backoff
- `src/app/relay_engine.cpp` — LED scheduler, LoRa/BLE TX, STATUS heartbeat
- `src/app/relay_main.cpp` / `gateway_main.cpp` / `demo_relay_main.cpp`

## Does not own
Dart, Node.js, or dashboard code. File a change request instead.

## Ship process
```
python build_relay.py          # or: -m platformio run -e relay
python build_gw.py             # or: -m platformio run -e gateway
```
Then flash the one board you changed:
```
python flash_com8.py           # relay  (N-A)
python flash_gw8.py            # gateway (RCUE) + LittleFS web UI
```
Size guard: relay sits ~53% of flash, gateway ~92%. The gateway is close to the
limit — new features need `build_gw.py` to succeed, not "should fit".

## Verify before you claim done
1. **Stop the server first.** It holds COM8 and the flash fails with
   `Access is denied` otherwise.
2. **Download mode**: hold `BOOT`, tap `EN`, release `BOOT`. Plugging the cable
   in alone does nothing — the board just boots normally.
3. Confirm on the serial log you see your new `[...]` line and the right
   `advertising as SAFETRAILS_RELAY`.
4. Restart the server with `SERIAL_PORT=COM8` and check
   `http://localhost:8080/api/health` reports `"mode":"serial"`.
5. Check STATUS in the log: `lora=1 reach=1 adv=1` and no new
   `notify DROPPED` / `notify FAILED` lines.

## Things that already bit us — do not undo
- **Do not "simplify" the LED indicator.** One scheduler owns every blink so a
  transmit burst is never truncated by an arriving packet, and alarm blinks
  defer to real traffic. RX = one `120 ms` flash, TX = `3x120 ms` with `90 ms`
  gaps.
- **`ST_LED_ACTIVE_LOW 1`.** Common ESP32 devkit onboard LEDs are active-low;
  the first build used active-high and the lights were invisible.
- **`ST_LED_TX_GPIO -1` is intentional** — we use the built-in GPIO2 only.
- **Do not trust `notify ok`.** It once logged success with `mtu=0` while no
  phone was connected. The honest logs are `notify DROPPED ... (no phone
  connected)` and `notify FAILED ... payloadMax=`. Keep those.
- **Do not remove the per-peer BLE backoff** in `ble_mesh.cpp`
  (5/10/20/40/60 s). Without it one unreachable phone floods the log.
- **The STATUS heartbeat is the de-facto time beacon.** It is sent straight over
  LoRa every 30 s and nodes adopt the clock from `src==RCUE`. There is no SNTP
  in the firmware — remove or retarget that heartbeat and clocks silently
  diverge, after which packets get rejected as `STALE` or `FUTURE`.
- **The gateway advertises with no 128-bit UUID on purpose.** Adding it back
  overflows the 31-byte advertising payload and the board stops being visible.

## Board roles
- **Gateway / receiver `RCUE`** — on the PC's COM8, talks to the server. Has SNTP
  via the server path.
- **Relay / transmitter `N-A`** — own power supply, no PC connection needed in
  normal operation.
