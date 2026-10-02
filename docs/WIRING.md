# SAFETRAILS Hardware Wiring & Bill of Materials

## BOM

| Qty | Part                       | Notes                                        |
|-----|----------------------------|----------------------------------------------|
| 2   | ESP32 DevKit (WROOM-32)    | Required — ESP8266 has **no BLE**.           |
| 2   | SX1278 / RA-02 LoRa module | 915/868/433 MHz variants available           |
| 2   | SMA 433/868/915 antenna    | Match the module frequency                   |
| 2   | Breadboard                 | Half-size or larger                          |
| ~20 | Jumper wires               | M/M                                        |
| 2   | 100 nF cap (optional)      | LoRa module power filtering                  |
| 2   | Red LED + 220 Ω (optional) | Indicator for RX/SOS flashing                |
| 2   | Buzzer (optional)          | Alert on incoming broadcast                  |

> LoRa ISM band differs by region — configure `LORA_FREQUENCY` to your region
> (see `firmware/src/config.h` and README §“Regional configuration”).

## ESP32 dev kit – LoRa (SX1278 RA-02) pin map

RA-02 pin labels: `VCC GND NSS SCK MISO MOSI RST DIO0 DIO1 DIO2`.

| LoRa module   | ESP32 DevKit pin |
|---------------|------------------|
| VCC           | 3V3              |
| GND           | GND              |
| SCK           | GPIO18 (SPI2/VSPI)   |
| MISO          | GPIO19 (SPI2)        |
| MOSI          | GPIO23 (SPI2)        |
| NSS  (CS)     | GPIO5               |
| RST           | GPIO15              |
| DIO0 (interrupt) | GPIO21           |
| DIO1          | (not connected)     |
| DIO2          | (not connected)     |

> Verified 2-board test pair, RA-02 + plain ESP32 devkits:
> `SCK=D18 MISO=D19 MOSI=D23 NSS=D5 RST=D15 DIO0=D21`. No DIO1/DIO2 are
> wired on this pair. Pins are centralised in
> `firmware/src/config.h` (`ST_LORA_*`); if your board differs, remap there.

> Pins are centralised in `firmware/src/config.h`. If your SPI bus uses
> `VSPI` (default) keep these. Any conflicting GPIOs in your board can be
> remapped there in one place.

### Power notes

- RA-02 current draw peaks ~120 mA during TX. Feed from the ESP32 3V3 rail for
  a bench prototype; for field deployment use a 3.3 V LDO or LiPo + boost and
  decouple with a 100 nF cap at the LoRa VCC pin.
- Keep jumper wires short on SPI lines (SCK/MOSI/MISO) to avoid noise.

## ESP32 – status LED / buzzer

| Function      | GPIO  |
|---------------|-------|
| LED_GPIO      | GPIO2 |
| BUZZER_GPIO   | GPIO4 |

## Node A (traveler relay)

```
Phone <=BLE=> ESP32A <=SPI=> LoRaA   (uplink to gateway)
```

## Node B (rescue gateway)

```
ESP32B <=SPI=> LoRaB
ESP32B ==USB serial==> Host computer (dashboard)
```

## ESP8266 note

ESP8266 does **not** support BLE. If you keep an ESP8266 board from an earlier
LoRa-only test, it may only be used as a LoRa *peripheral* by adapting the
`demo_lora_8266/` example included in the repo; the final hybrid BLE+LoRa
prototype requires ESP32 on both nodes. The demo relay (`demo_relay`) is ESP32.

## Minimal two-LoRa smoke test (no phone)

1. Flash `gateway` build to Node B, open its serial monitor.
2. Flash `relay` build to Node A.
3. Node A's PING shell command / auto-status should be visible on Node B's
   serial monitor, and “LoRa link OK” in the dashboard when connected.

See `docs/TESTING.md` for the full hardware test procedure.