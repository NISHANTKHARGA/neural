# SAFETRAILS System Architecture

**Offline Emergency Communication Network for Tourists** — remote-area rescue
communication for Nepal where cellular/Internet coverage does not exist.

```
┌────────────────────┐        BLE        ┌─────────────────┐
│  TOURIST PHONE     │ ────────────────► │  SAFETRAILS     │
│  (Flutter app)     │                   │  RELAY (ESP32)  │
│  GPS + BLE client  │ ◄──────────────── │  BLE peri+cent  │
└────────────────────┘      notify       │  LoRa if fitted  │
                                        └────────┬────────┘
                                                │ LoRa (SX1278)
                                 ┌──────────────┴───────────────┐
                                 │                              │
                        ┌────────▼────────┐             ┌──────▼───────┐
                        │ RELAY (ESP32)   │  BLE mesh   │ RELAY (ESP32)│
                        │ BLE peri+cent   │◄──────────► │ BLE peri+cent│
                        │ LoRa optional   │             │ LoRa+GATEWAY │
                        └─────────────────┘             └──────┬───────┘
                                                               │ USB serial
                                                        ┌──────▼───────┐
                                                        │ RESCUE       │
                                                        │ DASHBOARD    │
                                                        │ (web + API)  │
                                                        └──────────────┘
```

## Design principles

1. **Offline-first.** GPS (GNSS satellites), BLE, LoRa and all routing work
   with zero Internet. Map tiles/geocoding are the only things that need data.
2. **Explicit multi-hop.** BLE gives a single point-to-point link. SAFETRAILS
   relays implement application-level store-and-forward routing with
   `hop/ttl/path`, duplicate suppression and a seen-cache.
3. **Adaptive path selection.** A relay uses LoRa when it has a LoRa link to a
   gateway; otherwise it forwards over the BLE relay mesh until a LoRa-capable
   node is reached.
4. **Protocol translation at the edge.** JSON over BLE/serial (roomy links),
   compact fixed-field frames over LoRa (bandwidth constrained).
5. **Two-way.** SOS up, ACK + rescue message + emergency broadcast down.

## Component map

| Layer        | Technology                       | Offline |
|--------------|----------------------------------|---------|
| Tourist app  | Flutter, `flutter_blue_plus`, `geolocator` | Yes |
| Relay node   | ESP32 + SX1278/RA-02 LoRa, NimBLE (dual-role BLE) | Yes |
| Gateway node | ESP32 + LoRa, USB serial to host | Yes |
| Dashboard    | Web app (Web Serial or WebSocket) + Leaflet map | Partial (tiles/geocoding optional) |
| Server       | Node.js bridge, optional sync    | Optional |

## Data & control plane

- **Packet format:** `shared/protocol/PROTOCOL.md` (JSON + compact LoRa). One
  canonical packet driven by `v,type,prio,mid,src,dst,lat,lon,ts,hop,ttl,flags,path,ck,body`.
- **Routing:** firmware `routing` module executes validate → de-dup → TTL →
  forward LoRa-or-BLE per paragraph 4 of the protocol spec.
- **Persistence:** dashboard/server cache messages to `messages/` (JSONL) so a
  temporary loss of connection never loses an SOS. Sync happens when
  connectivity returns.

## Directory layout

```
/mobile                 Flutter tourist application
/firmware               ESP32/Arduino firmware (PlatformIO)
  /src                  shared firmware core (protocol, routing, ble, lora)
  /relay                traveler relay main
  /gateway              rescue gateway main
  /demo_relay           BLE-only forwarding demo node
  /test                 native host unit tests (protocol + router)
/dashboard              Rescue dashboard (static web app)
/server                 Node.js serial bridge + WebSocket + simulator + API
/shared                 Cross-language definitions
  /protocol             PROTOCOL.md + printable UUID table + JSON schema
docs/                   Architecture, wiring, testing, troubleshooting
README.md               Getting started
```

## Variants

| Build        | BLE server | BLE client | LoRa | Serial out | Use                                    |
|--------------|-----------|-----------|------|------------|----------------------------------------|
| `relay`      | yes       | yes       | yes  | debug      | Traveler-facing relay with LoRa uplink  |
| `gateway`    | yes       | yes       | yes  | **yes**    | Rescue gateway bridging LoRa → host     |
| `demo_relay` | yes       | yes       | no   | debug      | BLE-mesh demo node (proves multi-hop)  |

`HAS_LORA` is a compile-time flag: with it off the routing engine is pure BLE
store-and-forward.