# SAFETRAILS Wire Protocol

Version 1.0

This document is the single source of truth for packet encoding across all
SAFETRAILS components:

- ESP32 firmware (C++ encoder/decoder)
- Tourist mobile app (Dart)
- Rescue dashboard + server (JavaScript)

There are **two encodings of the same logical packet**:

| Encoding | Where it is used                    | Notes                                |
|----------|-------------------------------------|--------------------------------------|
| JSON     | BLE link + USB serial + WebSocket   | Roomier links, human readable        |
| Compact  | LoRa radio frames                   | LoRa is bandwidth-constrained        |

Relay firmware performs protocol translation at the **BLE ↔ LoRa boundary**.
The tourist app and the dashboard only ever handle JSON.

---

## 1. Logical packet (JSON canonical form)

All fields use short names to stay small while remaining debuggable.

```json
{
  "v": 1,
  "type": "SOS",
  "prio": 3,
  "mid": "8F23A91",
  "src": "T102",
  "dst": "RCUE",
  "lat": 27.9881,
  "lon": 86.925,
  "ts": 1770000000,
  "hop": 0,
  "ttl": 8,
  "flags": 3,
  "path": ["RCUE"],
  "ck": "A1B2",
  "body": "I need emergency assistance"
}
```

### Field reference

| Key  | Type              | Meaning                                                                 |
|------|-------------------|--------------------------------------------------------------------------|
| `v`  | int               | Protocol version (1).                                                    |
| `type` | string         | See message types below.                                                 |
| `prio` | int 0..3        | 0=LOW, 1=MEDIUM, 2=HIGH, 3=CRITICAL. SOS implies 3.                     |
| `mid` | string (1..16)  | Unique message id. Charset `[A-Za-z0-9-]`. De-dup key `src+type+mid`.  |
| `src` | string (1..16)  | Sender id. Charset `[A-Za-z0-9_-]`. Tourists `T<num>`, relays `N<name>`, rescue `RCUE`. |
| `dst` | string (1..16)  | Receiver id, `RCUE`, or `*`. Charset `[A-Za-z0-9_*-]`.                 |
| `lat` | number \| "-"    | Decimal latitude (WGS84), ≤6 decimals. `"-"` when unknown.            |
| `lon` | number \| "-"    | Decimal longitude (WGS84), ≤6 decimals. `"-"` when unknown.           |
| `ts`  | long             | Unix epoch seconds (UTC).                                                |
| `hop` | int 0..15        | Hop count already traversed. Starts 0.                                   |
| `ttl` | int 0..15        | Remaining hops. Decremented at every relay. Dropped at 0.                |
| `flags` | int           | Bitmask, see below.                                                      |
| `path` | string[]        | Ordered list of node ids the packet has traversed (reverse route).      |
| `ck`  | string (4 hex)   | FNV-1a 16-bit checksum over canonical fields. See §5.                    |
| `body`| string          | Message text, optional, max 200 chars in JSON / 120 in compact. `BROAD` uses `title^message^area`. |

### Flags bitmask

| Bit | Value | Constant          | Meaning                                           |
|-----|-------|-------------------|---------------------------------------------------|
| 0   | 1     | `ACK_REQUIRED`    | Sender wants an acknowledgement.                  |
| 1   | 2     | `ACKED`           | Packet has been acknowledged upstream.            |
| 2   | 4     | `RELAYED`         | Packet passed through at least one relay.         |
| 3   | 8     | `BROADCAST`       | One-to-many message: every node must forward it.  |

An **ACK packet** carries the original `mid` (and `src` of the original packet
in `body`/or `dst`) so the originator can correlate delivery.

### Message types

| `type`      | Direction        | Purpose                                            |
|-------------|------------------|----------------------------------------------------|
| `SOS`       | tourist → rescue | Emergency distress call with GPS. ACK_REQUIRED.    |
| `ACK`       | rescue → tourist | Delivery acknowledgement for an `mid`.             |
| `RESCUE`    | rescue → tourist | One-to-one rescue message (ack optional).          |
| `BROAD`     | rescue → many    | Emergency broadcast. Flag `BROADCAST` set.         |
| `STATUS`    | node ↔ node      | Relay/gateway health: battery, RSSI, counters.     |
| `TRACK`     | tourist → rescue | Optional periodic position report. (not core)      |
| `PING`      | any → any        | Link probe.                                        |
| `PONG`      | any → any        | Link probe reply.                                  |

---

## 2. Compact LoRa frame

LoRa SX1278 with SF7 / BW125kHz / CR4/5 / CRC-on carries ~222 bytes payload;
SF12 only ~59 bytes. SAFETRAILS therefore uses a fixed-position, `|`-delimited
frame with a checksum and a configurable max body length.

```
ST|1|SOS|3|8F23A91|T102|RCUE|27.9881|86.9250|1770000000|0|8|3|RCUE|A1B2|I need emergency assistance
```

Position table:

| Pos | Field | Format                        | Notes                               |
|-----|-------|-------------------------------|-------------------------------------|
| 0   | sync  | `ST`                          | Frame sync prefix.                  |
| 1   | ver   | int                           | Protocol version (1).               |
| 2   | type  | `SOS/ACK/RESCUE/BROAD/STATUS/TRACK/PING/PONG` |                        |
| 3   | prio  | int 0..3                      |                                     |
| 4   | mid   | 1..16 chars                   |                                     |
| 5   | src   | 1..16 chars                   |                                     |
| 6   | dst   | 1..16 chars or `*`            |                                     |
| 7   | lat   | decimal or `-`                |                                     |
| 8   | lon   | decimal or `-`                |                                     |
| 9   | ts    | unix seconds                  |                                     |
| 10  | hop   | int                           |                                     |
| 11  | ttl   | int                           |                                     |
| 12  | flags | int 0..15                     |                                     |
| 13  | path  | `*` or ids joined by `,`      | Append each traversed node id.      |
| 14  | ck    | 4 hex chars                   | FNV-1a 16-bit over fields 0..13.    |
| 15  | body  | free text, no `|`             | `|` replaced with `;` at encode.    |

Rules:

- A relay **never** modifies an already-forwarded `mid`; modifications to
  `hop`/`ttl`/`path`/`flags` are allowed and the checksum is recomputed.
- Body must not contain `|`; encoders replace `|` with `;`.
- Compact frame is decoded from left to right, and **validation requires**
  that exactly 15 separators exist and `ck` matches (see §5).

### Practical LoRa payload budget

`ST|1|SOS|3|12345678|T102|RCUE|27.9881|86.9250|1770000000|0|8|3|RCUE|A1B2|` = **91 bytes** fixed.

| LoRa profile       | Max payload | Free for `body` |
|--------------------|-------------|-----------------|
| SF7, BW125, CR4/5  | ~222 bytes  | ~131            |
| SF9, BW125, CR4/5  | ~112 bytes  | ~21             |
| SF12, BW125, CR4/5 | ~59 bytes   | 0 (stripped)    |

Firmware automatically strips/truncates `body` to fit the configured profile.

---

## 3. BLE GATT layout

Relays advertise as **`SAFETRAILS_RELAY`** (local name). Every relay runs BOTH
roles:

- **Peripheral / GATT server** — phones (GATT clients) connect to it.
- **Central / GATT client** — connects to *other* relays to forward packets
  over BLE when the phone is out of LoRa range (application-level multi-hop).

### Service

```
UUID: 2f32f800-6a00-4f6a-9a5e-001122334455
Description: SAFETRAILS relay service
```

### Characteristics

| Name          | UUID (suffix of service) | Properties         | Purpose                                    |
|---------------|--------------------------|--------------------|--------------------------------------------|
| `SOS_TX`      | 2f32f801-…               | Write              | Phone → relay, SOS packets (JSON).         |
| `SOS_RX`      | 2f32f802-…               | Notify             | Relay → phone, SOS receipt + ACK.          |
| `ACL_TX`      | 2f32f803-…               | Write              | Phone → relay, acknowledgements (JSON).    |
| `RESCUE_RX`   | 2f32f804-…               | Notify             | Relay → phone, rescue messages.            |
| `BROADCAST_RX`| 2f32f805-…               | Notify             | Relay → phone, broadcasts.                 |
| `STATUS_RX`   | 2f32f806-…               | Read + Notify      | Relay → phone, status JSON + periodic.     |
| `DATA_RX`     | 2f32f807-…               | Notify             | Relay → phone, generic packet mirror (debug).|

The phone writes JSON to `SOS_TX` / `ACL_TX`; the relay writes JSON to
`SOS_RX` / `RESCUE_RX` / `BROADCAST_RX`. Relay-to-relay forwarding uses the
same two length-capped JSON characteristics through the `DATA_RX` mirror so a
central relay can push a full JSON packet.

Maximum characteristic value length: **200 bytes**.

### Connection & retries

- Phone: 3 attach attempts, 10 s attach timeout, 5 s write timeout.
- Relay central links: `BLE_LINK_KEEPALIVE_MS` (default 20 s) then disconnect
  to save power; re-established on demand.

---

## 4. Routing logic (explicit, application-level)

The phone has a **direct BLE link** only. Everything past it is application
routing performed by relays. There is no inherent multi-hop in BLE.

```
Tourist phone ──BLE──► Relay A ──BLE──► Relay B ──LoRa──► Gateway ──USB/host──► Dashboard
```

Relay receive path:

1. Validate (version, type, checksum, field bounds, `ts` fresh).
2. De-duplicate on `src:type:mid` in the seen-cache. Seen → drop.
3. If `dst == *` (broadcast) and flag `BROADCAST` → forward to next hop(s).
4. If this node is the destination (`dst` == self or gateway) → deliver up the
   upper layer; if `ACK_REQUIRED` → schedule an `ACK`.
5. Decrement `ttl`. If `ttl <= 0` and not destination → drop (EXPIRED).
6. Increment `hop`, append self id to `path`.
7. `RELAYED` flag set.
8. Choose next interface:
   - If node has LoRa and LoRa is believed reachable → forward compact frame on LoRa.
   - Otherwise → forward via BLE: pick best neighbor relay from the neighbor
     table, or broadcast the packet to every known relay link.
9. Update local message store table with new status/last device.

Drop reasons (mirrored in status): `SEEN`, `TTL_EXPIRED`, `INVALID`,
`BAD_CHECKSUM`, `STALE`, `EXPIRED`.

---

## 5. Integrity: FNV-1a 16-bit checksum

Compute over the canonical field string **before** the checksum position,
using the same delimiter as the encoding in use:

- Compact: `ST|1|SOS|3|8F23A91|T102|RCUE|27.9881|86.9250|1770000000|0|8|3|RCUE`
- JSON: same canonical string (fields joined with `|` in fixed order,
  skipping optional `lat/lon/path` gaps by using `-` markers).

```
h = 0x811c9dc5 (32-bit)
for each byte: h ^= b; h *= 0x01000193;
return (h >> 16) & 0xffff       // low 16 bits
```

Rendered as 4 lowercase hex chars. Lat/lon/path encoded with `-` for missing
values so the checksum input is deterministic across platforms.

---

## 6. Message lifecycle / delivery states

| State          | Meaning                                             |
|----------------|-----------------------------------------------------|
| `CREATED`      | Packet constructed in the app, not yet sent.        |
| `BLE_SENT`     | Packet written to a relay characteristic.           |
| `RELAYED`      | A relay forwarded it (mirrored by `RELAYED` flag).  |
| `LORA_SENT`    | A relay sent it on LoRa.                            |
| `RECEIVED`     | Destination (gateway) delivered it up.              |
| `ACKNOWLEDGED` | Originator received the `ACK` for `mid`.            |
| `FAILED`       | Sender gave up after retries / no link.             |
| `EXPIRED`      | TTL exhausted or time window passed.                |

---

## 7. Replay protection & freshness

- Relays reject packets whose `mid` is in the seen-cache (LRU ring buffer).
- Non-`TRACK` packets with `ts` older than `MSG_MAX_AGE_S` (default 300) or
  more than `MSG_FUTURE_SKEW_S` (default 60) in the future are dropped.
- After timeout a `mid` becomes eligible again (STALE expiry).