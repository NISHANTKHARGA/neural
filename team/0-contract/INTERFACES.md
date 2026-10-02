# Part 0 — Shared interfaces (owned by nobody)

These are the values that all four parts agree on. Each one is written **four
times** — in Dart, in C++, in JavaScript and in C — so a change in one place
without the other three is the single most damaging mistake in this project.

Values below are the current, verified truth. Source of each is given so you can
confirm rather than trust.

## 1. Packet JSON (the wire format for everything)

Produced by `firmware/src/core/packet.cpp`, consumed by
`mobile/lib/state/*.dart` and `server/index.js`.

```
type    string   SOS | RESCUE | BROAD | ACK | STATUS
mid     string   unique id, HARD CAP OF 16 CHARACTERS (silently truncated)
src     string   sender node id
dst     string   destination node id, or "*" for broadcast
ts      int64    unix seconds
hop     int      hops travelled
ttl     int      remaining hops (7 = fresh, decrements as it is relayed)
prio    int      lower is more urgent
flags   int      bitfield
body    string   free text; carries the link-health line for STATUS
```

Rules that bite:

- **`mid` is capped at 16 chars.** The desk ACK reuses the original mid as
  `ACK-<mid>`; appending anything else overflows. That is why a desk ACK has to
  explicitly forget the dedup entry instead of using a fresh id.
- **`ts` older than 300 s is dropped as `STALE`; more than 60 s in the future is
  dropped as `FUTURE`.** Nodes have no SNTP — they sync from each other, so the
  clocks agreeing is a hard requirement, not a nicety.
- **`ttl` 7 / `hop` 1..3** in normal operation.

## 2. Node ids

| Id | Meaning |
|----|---------|
| `RCUE` | rescue gateway / receiver (the one on COM8) |
| `N-A`  | relay / transmitter (LoRa, own power) |
| `T102` | tourist handset |

Also used as `ST_NODE_ID`, `ST_TOURIST_ID` in `firmware/src/config.h`.

## 3. BLE GATT UUIDs

Source: `mobile/lib/ble/ble_relay_connection.dart`, mirrored in
`firmware/src/config.h` / `ble_server.cpp`. All share the suffix
`6a00-4f6a-9a5e-001122334455`.

| Endpoint | UUID tail | Direction |
|----------|-----------|-----------|
| service  | `2f32f800` | — |
| sosTx    | `2f32f801` | phone -> node |
| sosRx    | `2f32f802` | node -> phone |
| rescueRx | `2f32f804` | node -> phone |
| broadcastRx | `2f32f805` | node -> phone |
| statusRx | `2f32f806` | node -> phone |

Advertise name: **`SAFETRAILS_RELAY`** (matched by prefix).

Two hard-won constraints:

- **The advertisement deliberately carries no 128-bit service UUID.** It
  overflowed the 31-byte legacy advertising payload and stopped advertising
  entirely. Nodes are found by **name**. A scanner filtering on the service
  UUID will therefore not see them.
- **MTU must be negotiated to 517.** Packets are 188–325 bytes; the default
  MTU of 23 rejects every one of them. `NimBLEDevice::setMTU(517)` in
  `ble_server.cpp`.

## 4. LoRa radio

433 MHz, BW 125 kHz, SF7, CR 4/5, sync `0x12`, TX power 20 dBm. Both boards
must match exactly. Compact frames are truncated to `ST_LORA_MAX_PAYLOAD`;
oversize JSON is dropped rather than fragmented.

## 5. Server HTTP + WebSocket

Source: `server/index.js`.

| Endpoint | Purpose |
|----------|---------|
| `GET /api/health` | returns `{"ok":true,"mode":"serial","uptimeSec":N}` |
| `POST /api/packet` | inject a packet (used by the phone's online transport) |
| `ws://<host>:8080` | dashboard live feed, and commands down to the gateway |

WebSocket commands down to the gateway are `{"cmd":"..."}`:

| cmd | effect |
|-----|--------|
| `ack` | desk acknowledges a row |
| `rescue` | send a RESCUE message |
| `broad` | send a BROADCAST |
| `status_req` | force a STATUS now |

`mode` in `/api/health` must read `serial`. If it reads `simulator`, the
dashboard is displaying invented traffic.
