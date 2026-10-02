# SAFETRAILS

Offline emergency-communication prototype for tourists in remote Nepal.
A Flutter phone app talks to battery-powered **ESP32 relay nodes** (LoRa +
BLE) that forward distress calls to a **rescue dashboard** — with **no
Internet, no SIM, no cellular** anywhere in the chain. Two-way
acknowledgements, location sharing, and rescue-team broadcasts work purely
over short-range radio.

```
 tourist phone ──BLE──▶ relay (N-A) ──LoRa──▶ relay (N-B) ──BLE──▶ gateway (RCUE) ──USB──▶ rescue dashboard
                            ▌                                                          (Web Serial)
                            └── LoRa or multi-hop BLE store-and-forward ─▶ gateway
```

## Why not WiFi / LoRaWAN / BLE Mesh?

- **WiFi** is useless in a remote valley.
- **LoRaWAN** needs a commercial gateway/network — the rescue team *is* the gateway.
- **BLE mesh** (MeshModel) is infrastructure we can't rely on across two brands of
  cheap boards, so multi-hop is implemented **explicitly at the application layer** using
  the same packet format everywhere.

## Fast start (zero hardware)

The Node server contains an embedded **network simulator** that reproduces the
whole flow (tourist TRACK → SOS → gateway ACK → rescue → acknowledgement) with
no ESP32s at all:

```bash
cd server && npm install
npm run sim            # serves dashboard + simulator on http://localhost:8080
```

Open http://localhost:8080, press **Connect** (WebSocket mode). The simulator
emits a distress SOS ~6 s after boot; ACK it from the table.

**With hardware:** plug the ESP32 gateway into USB and select **Web Serial**
mode in the dashboard (Chrome/Edge). The same page drives the real radio mesh.

## Repo layout

```
docs/                  ARCHITECTURE.md, WIRING.md, TESTING.md
shared/protocol/       THE protocol (source of truth):
                         PROTOCOL.md            frame format, UUIDs, routing
                         packet.js              codec (dashboard + server)
                         test_packet.js         JS codec self-tests
                         check_cross_platform.py  canonical+cksum conformance
                         dart/                  Flutter package mirror of the codec
mobile/                Flutter app (phone) — BLE to relay, SOS/ack, GPS, UI
firmware/              ESP32 firmware (PlatformIO)
                         src/config.h              all build-time knobs
                         src/core/                 packet + router (pure C++, host-testable)
                         src/link/                 LoRaLink (SX1278 via RadioLib)
                         src/ble/                  BLE peripheral server + central mesh
                         src/app/                  relay engine + main() per variant
                         platformio.ini            relay / gateway / demo_relay / test_native
server/                Node: WS hub + simulator + optional serial bridge
dashboard/             Rescue web app (Web Serial + WebSocket, map, SOS list)
```

## The packet pipeline

Every message on every medium is the **same logical packet**:

- **JSON** over BLE writes / USB serial / WebSocket (for humans).
- **Compact** `|`-delimited frames over LoRa (for radio), checksummed with
  FNV-1a 16-bit over canonical fields.

`lat`/`lon` travel as verbatim strings, normalized to ≤6 decimals, so the
checksum is byte-identical across the JS, Dart, and C++ codecs
(`shared/protocol/check_cross_platform.py` proves it).

```text
ST|1|SOS|3|SOS-8F23A91|T102|RCUE|27.9881|86.925|1770000000|0|8|3|RCUE|eab3|I need emergency assistance
▓▓ ▓▓▓▓ ▓ ▓▓▓▓▓▓▓▓▓▓▓▓ ▓▓▓▓ ▓▓▓▓ ▓▓▓▓▓▓▓ ▓▓▓▓▓▓ ▓▓▓▓▓▓▓▓▓▓ ▓ ▓ ▓ ▓▓▓▓▓▓▓▓ ▓▓▓▓░░ └─ body
└─st└ver └─type └─mid    └src └dst └lat   └lon    └ts        └h└t└f└path   └ck     └─ checksum covers left side only
```

## Firmware builds

```bash
cd firmware && pio run -e relay        # traveler-facing relay node
pio run -e gateway                     # rescue gateway (USB serial out)
pio run -e demo_relay                  # BLE-only, no LoRa — multi-hop demo
pio test -e test_native                # protocol + router core tests
```

Profiles are selected by `platformio.ini` build flags; every radio parameter
(frequency, bandwidth, SF, power) lives in `src/config.h` and **must be
reviewed against local radio regulation before deployment**.

## Checksums & testing

```bash
node shared/protocol/test_packet.js          # JS codec vectors + tamper tests
python shared/protocol/check_cross_platform.py  # canonical/checksum parity
cd server && npm install && npm test         # end-to-end server + simulator smoke
```

Hardware procedures (BLE multi-hop, LoRa range, gateway wiring) are in
`docs/TESTING.md`.

## Security note

This is a **prototype**. There is no encryption on the radio links — anyone
with an SDR can read LoRa frames and anyone on BLE can read packets. Production
hardening would add per-deployment keys + a lightweight cipher over the body
field. Do not rely on this system for actual life-safety without review.