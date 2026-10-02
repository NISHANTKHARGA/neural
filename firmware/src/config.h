#pragma once

// --------------------------------------------------------------------------
// SAFETRAILS firmware configuration.
// Build variants override the ST_* macros via platformio build_flags.
// Region-specific LoRa parameters MUST be reviewed before deployment.
// --------------------------------------------------------------------------

// Identity
#ifndef ST_NODE_ID
#define ST_NODE_ID "N-A"
#endif

// Role: 0 = relay node, 1 = rescue gateway
#ifndef ST_ROLE_GATEWAY
#define ST_ROLE_GATEWAY 0
#endif

// 0 = BLE-store-and-forward only (no radio), 1 = LoRa fitted
#ifndef ST_HAS_LORA
#define ST_HAS_LORA 1
#endif

// --------------------------------------------------------------------------
// LoRa (SX1278 / RA-02) — SPI2/VSPI wiring. See docs/WIRING.md.
// Verified 2-board wiring: SCK=D18 MISO=D19 MOSI=D23 NSS=D5 RST=D15 DIO0=D21.
// RadioLib Module pins: (CS, DIO0, RST, DIO1, DIO2) — -1 = not connected.
// --------------------------------------------------------------------------
#ifndef ST_LORA_CS
#define ST_LORA_CS 5
#endif
#ifndef ST_LORA_DIO0
#define ST_LORA_DIO0 21
#endif
#ifndef ST_LORA_RST
#define ST_LORA_RST 15
#endif
#ifndef ST_LORA_DIO1
#define ST_LORA_DIO1 -1   // not wired on this board pair.
#endif
#ifndef ST_LORA_DIO2
#define ST_LORA_DIO2 -1   // unused.
#endif
// VSPI default pins used by RadioLib SPI init
#ifndef ST_LORA_SCK
#define ST_LORA_SCK 18
#endif
#ifndef ST_LORA_MISO
#define ST_LORA_MISO 19
#endif
#ifndef ST_LORA_MOSI
#define ST_LORA_MOSI 23
#endif

// ---- Radio parameters (REGION LOCKED: change per local regulation) --------
#ifndef ST_LORA_FREQ_MHZ
#define ST_LORA_FREQ_MHZ 433.0f   // 433 / 868 / 915 MHz - verify your hardware+radio law (SX1278 = 433 band)
#endif
#ifndef ST_LORA_BW_KHZ
#define ST_LORA_BW_KHZ 125.0f
#endif
#ifndef ST_LORA_SF
#define ST_LORA_SF 7              // 7..12
#endif
#ifndef ST_LORA_CR
#define ST_LORA_CR 5              // 4/5
#endif
#ifndef ST_LORA_PWR_DBM
#define ST_LORA_PWR_DBM 20        // 2..20
#endif
#ifndef ST_LORA_SYNC_WORD
#define ST_LORA_SYNC_WORD 0x12
#endif
#ifndef ST_LORA_PREAMBLE
#define ST_LORA_PREAMBLE 8
#endif
#ifndef ST_LORA_MAX_PAYLOAD
#define ST_LORA_MAX_PAYLOAD 120   // bytes per compact frame (body budget)
#endif

// A LoRa node is an "available path" only if it received a frame recently.
// (Radio reachability heuristic — see docs/TESTING LoRa range test.)
#ifndef ST_LORA_REACHABLE_WINDOW_MS
#define ST_LORA_REACHABLE_WINDOW_MS 120000
#endif

// --------------------------------------------------------------------------
// BLE
// --------------------------------------------------------------------------
#ifndef ST_BLE_ADV_NAME
#define ST_BLE_ADV_NAME "SAFETRAILS_RELAY"
#endif
#ifndef ST_BLE_ADV_INTERVAL_MS
#define ST_BLE_ADV_INTERVAL_MS 200
#endif
#ifndef ST_BLE_CONNECT_TIMEOUT_MS
#define ST_BLE_CONNECT_TIMEOUT_MS 8000
#endif
// Max size accepted per characteristic write (bytes).
#ifndef ST_BLE_CHAR_MAX
#define ST_BLE_CHAR_MAX 200
#endif

// Neighbour (mesh) maintenance
#ifndef ST_MESH_SCAN_PERIOD_MS
#define ST_MESH_SCAN_PERIOD_MS 20000
#endif
#ifndef ST_MESH_PEER_TTL_MS
#define ST_MESH_PEER_TTL_MS 90000
#endif

// --------------------------------------------------------------------------
// Hardware IO
// --------------------------------------------------------------------------
// On-board / status LED (most ESP32 devkits: GPIO2) and an optional passive
// buzzer. Buzzers are active-low modules; set ST_BUZZER_GPIO to -1 if none.
#ifndef ST_LED_GPIO
#define ST_LED_GPIO 2
#endif
// Polarity of the LED on ST_LED_GPIO. The common ESP32 devkit wires the
// on-board LED anode to 3V3 through a resistor, so the pin must go LOW to
// light it -- driving it "active-high" left the LED permanently lit and the
// transmit burst invisible. Set to 0 for an active-high LED.
#ifndef ST_LED_ACTIVE_LOW
#define ST_LED_ACTIVE_LOW 1
#endif
#ifndef ST_BUZZER_GPIO
#define ST_BUZZER_GPIO 4
#endif

// --------------------------------------------------------------------------
// Tourist SOS button (relay node only).
// Most ESP32 devkits expose a BOOT button on GPIO0 (active-low, INPUT_PULLUP)
// — press it to raise an SOS without a phone. Release before power-on, or the
// board boots into download mode. Set to -1 to disable.
// --------------------------------------------------------------------------
#ifndef ST_SOS_BUTTON_GPIO
#define ST_SOS_BUTTON_GPIO 0
#endif
// The tourist this node represents/talks for (id used on the dashboard).
#ifndef ST_TOURIST_ID
#define ST_TOURIST_ID "T102"
#endif
// Position used when the SOS button is pressed (no GPS fitted on the node).
#ifndef ST_SOS_DEMO_LAT
#define ST_SOS_DEMO_LAT "27.9881"
#endif
#ifndef ST_SOS_DEMO_LON
#define ST_SOS_DEMO_LON "86.9250"
#endif
#ifndef ST_SOS_BODY
#define ST_SOS_BODY "SOS - tourist needs help"
#endif
#ifndef ST_SOS_DEBOUNCE_MS
#define ST_SOS_DEBOUNCE_MS 800
#endif
// Length of the LED/buzzer alarm pulse when a reply or SOS arrives.
#ifndef ST_ALARM_MS
#define ST_ALARM_MS 700
#endif
// Status-LED pulse lengths for plain radio traffic (not the alarm).
//
// TX and RX are deliberately *different patterns*, not just different lengths:
// a single long flash and a single short flash look identical to an operator
// watching from a metre away, which made "did my node send it?" unanswerable.
// Now a receive is one short flash and a transmit is a repeating burst.
//   RX : 1 x ST_LED_FLASH_MS
//   TX : ST_LED_TX_REPEATS x ST_LED_FLASH_MS, ST_LED_GAP_MS apart
#ifndef ST_LED_FLASH_MS
#define ST_LED_FLASH_MS 120
#endif
#ifndef ST_LED_GAP_MS
#define ST_LED_GAP_MS 90
#endif
#ifndef ST_LED_TX_REPEATS
#define ST_LED_TX_REPEATS 3
#endif
// Legacy lengths kept so older build flags still resolve.
#ifndef ST_LED_RX_BLINK_MS
#define ST_LED_RX_BLINK_MS ST_LED_FLASH_MS
#endif
#ifndef ST_LED_TX_BLINK_MS
#define ST_LED_TX_BLINK_MS ST_LED_FLASH_MS
#endif
// Optional dedicated "sent" LED, separate from the shared status LED above.
// Leave at -1 to show the TX burst on ST_LED_GPIO itself (the usual devkit
// blue LED). Set to a free output GPIO (e.g. 18) if the board has a second
// LED you want reserved purely for transmissions.
#ifndef ST_LED_TX_GPIO
#define ST_LED_TX_GPIO -1
#endif
// Cooldown between automatic mesh time-sync steps (see relay_engine.cpp).
#ifndef ST_TIME_SYNC_MIN_GAP_MS
#define ST_TIME_SYNC_MIN_GAP_MS 10000
#endif

// --------------------------------------------------------------------------
// Routing / reliability
// --------------------------------------------------------------------------
#ifndef ST_INITIAL_TTL
#define ST_INITIAL_TTL 8
#endif
#ifndef ST_MSG_MAX_AGE_S
#define ST_MSG_MAX_AGE_S 300
#endif
#ifndef ST_FUTURE_SKEW_S
#define ST_FUTURE_SKEW_S 60
#endif
#ifndef ST_SEEN_TTL_MS
#define ST_SEEN_TTL_MS 600000
#endif
#ifndef ST_STORE_KEEP_MS
#define ST_STORE_KEEP_MS 3600000
#endif
#ifndef ST_STATUS_PERIOD_MS
#define ST_STATUS_PERIOD_MS 30000
#endif

// After a BLE client connects, wait this long before pushing a STATUS so the
// phone has time to discover services + enable notifications, then hears
// immediately whether the linked relay's LoRa is up (vs waiting a full period).
#ifndef ST_STATUS_CONNECT_PUSH_DELAY_MS
#define ST_STATUS_CONNECT_PUSH_DELAY_MS 1500
#endif

// Serial (gateway only): line-delimited JSON packets in/out.
#ifndef ST_SERIAL_BAUD
#define ST_SERIAL_BAUD 115200
#endif

// --------------------------------------------------------------------------
// Embedded rescue web (gateway only): the gateway hosts its own WiFi hotspot
// and serves the dashboard + WebSocket hub from flash, so it works with just
// power — no PC required. Rescuers join this AP and open http://192.168.4.1.
// --------------------------------------------------------------------------
#ifndef ST_AP_SSID
#define ST_AP_SSID "SAFETRAILS-RESCUE"
#endif
#ifndef ST_AP_PASS
#define ST_AP_PASS "sagarmatha"
#endif
#ifndef ST_AP_CHANNEL
#define ST_AP_CHANNEL 6
#endif
// WebSocket port for the embedded hub (HTTP stays on :80).
#ifndef ST_WS_PORT
#define ST_WS_PORT 81
#endif