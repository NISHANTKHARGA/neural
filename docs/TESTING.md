# SAFETRAILS — Testing Guide

## 1. Pure-software (no hardware)

| What                                | How                                                                 | Expect                                              |
|-------------------------------------|---------------------------------------------------------------------|-----------------------------------------------------|
| JS codec self-test                  | `node shared/protocol/test_packet.js`                               | `test_packet.js OK`                                |
| Cross-platform checksum conformance | `python shared/protocol/check_cross_platform.py`                    | 3 × `[PASS]`, `OK: … conform …`                    |
| Server + simulator end-to-end       | `cd server && npm install && npm test`                              | TRACK→SOS→ACK→RESCUE→manual-ACK, `smoke test OK`   |
| Firmware core (host-native)         | `cd firmware && pio test -e test_native`                            | All Unity assertions green                          |

The firmware core (`src/core/packet.*`, `src/core/router.*`) is plain C++ with
no Arduino dependencies precisely so the routing/protocol logic can be unit
tested on a laptop. PlatformIO's `native` environment compiles it with Unity.

## 2. Hardware bring-up (one gateway, Web Serial)

1. `cd firmware && pio run -e gateway && pio run -t upload -e gateway`
2. Open the dashboard (`cd server && npm run sim`), pick **Web Serial**
   115200 baud, press Connect, choose the board's COM port.
3. The gateway prints `[gateway] READY`; the dashboard shows the connection
   going **on**.
4. In the dashboard, send a **Broadcast** and a **Rescue** — the gateway LED
   blinks on TX and the packets appear in the log.
5. Open a serial terminal (115200) on the same port — you should see the same
   JSON packet lines the dashboard received (everything round-trips the real
   gateway code, not the simulator).

## 3. BLE multi-hop demo (no LoRa)

Two `demo_relay` boards + the phone app:

1. Flash relay **N-B** as `pio run -e demo_relay` and relay **N-A** the same,
   but with `-DST_NODE_ID="\"N-A\""` (already the default) — put the boards
   ~2 m apart so each sees the other in its BLE scan.
2. Boot the Flutter app, scan, connect to either relay, trigger an SOS.
3. Expected: the app's SOS is written to the connected relay, TTL-decremented,
   then forwarded over BLE to the second relay (`[mesh] forwarding to …` in
   the serial log), which re-broadcasts it to the app.
4. Because the phone's `T102` id is linked to the connected relay, the route
   home for ACKs still reaches the app — the ARP-like `src→handle` registry
   forwards packets "to the tourist attached to this node".

## 4. LoRa range / link test (relay + gateway)

1. Any `relay` node and a `gateway`, both with SX1278 on the VSPI pins in
   `src/config.h` / `docs/WIRING.md`.
2. Place them apart, open dashboard (WebSocket mode via `npm run sim`), then
   `pio run -t monitor -e gateway` to watch the gateway's serial.
3. Send a **Rescue** from the dashboard → expect `[lora] up: …` at boot and
   packet JSON on the gateway serial when a relay forwards.
4. Watch the `STATUS` heartbeat: every 30 s each node emits a `STATUS` packet;
   check the `rssi`/`snr` fields in the body for link health:
   `node=N-A role=relay lora=1 rssi=-82.5 snr=8.6 …`.
5. Known real-world gotcha: the default radio config (915 MHz) must match your
   region and hardware. See **Radio region checklist** below.

## 5. Radio region checklist (mandatory before any over-the-air test)

| Parameter           | Default | Notes                                              |
|---------------------|---------|----------------------------------------------------|
| `ST_LORA_FREQ_MHZ`  | 915.0   | 433 / 868 / 915 — verify local ISM rules + module  |
| `ST_LORA_PWR_DBM`   | 20      | Up to +20 dBm; many regions cap at 14 dBm          |
| `ST_LORA_SF`        | 7       | Higher SF = range, lower throughput                |
| `ST_LORA_BW_KHZ`    | 125     |                                                     |
| `ST_LORA_CR`        | 5       | 4/5 coding rate                                     |
| `ST_LORA_SYNC_WORD` | 0x12    | Change per deployment to isolate networks           |

## 6. Troubleshooting

- **`[lora] init failed: 22`** — SPI pins/bus wrong, or radio not wired
  (`docs/WIRING.md`). Verify `ST_LORA_*` pins in `src/config.h`.
- **Dashboard Web Serial won't connect** — Chrome/Edge only; the page must be
  served over `http://localhost` (secure context). Use the Node server.
- **`[meson] no peer` / no BLE forwarding** — relays only forward to relays
  advertising `SAFETRAILS_RELAY` in BLE range and seen within
  `ST_MESH_PEER_TTL_MS` (90 s). Park a `demo_relay` next to the source.
- **Packets dropped as `SEEN`** — correct: the seen-cache suppresses
  duplicates for 10 minutes (`ST_SEEN_TTL_MS`). Mid collisions after reboot
  with an unsynced clock can look like drops; deploy with NTP on the gateway.
- **`STALE` drops** — a node's realtime clock is wrong (no SNTP). STATUS/PING/
  PONG are exempt; for SOS ensure the phone's clock is accurate.
- **Dashboards connected over WS show nothing** — in serial mode the dashboard
  only shows packets the gateway actually prints; confirm the COM port and that
  `[gateway] READY` appears.