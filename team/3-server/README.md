# Part 3 — Node server (the COM8 bridge)

**Owner: RCUE** · Code: `D:\esp32\server` · Entry point: `index.js`

## Owns
Everything under `D:\esp32\server`. Serial<->HTTP/WebSocket bridge and the
in-memory desk/dedup state.

## Does not own
Dart, C++, or dashboard code. File a change request instead.

## The one thing that matters
`index.js` **silently falls back to a simulator when `SERIAL_PORT` is not set.**
In that mode the dashboard shows invented traffic that looks completely real.
This has already cost debugging time twice.

```
$env:SERIAL_PORT="COM8"; $env:SERIAL_BAUD="115200"; node index.js
```
Always confirm after a restart:
```
GET http://localhost:8080/api/health   ->  {"ok":true,"mode":"serial",...}
```

Only one board can own COM8. The dashboard is alive only while the **receiver
(RCUE)** is plugged in.

## Interfaces exposed (see `..\0-contract\INTERFACES.md`)
- `GET /api/health`
- `POST /api/packet`
- `ws://<host>:8080` — dashboard feed, and `ack` / `rescue` / `broad` /
  `status_req` down to the gateway

## Verify before you claim done
1. `/api/health` says `mode":"serial"`.
2. A STATUS line from the gateway appears in the log within 30 s and shows
   `reach=1`.
3. Dashboard SOS from the phone appears, returns an ACK, and the row clears.
4. RESCUE and BROAD from the dashboard reach a connected phone.
5. **Check `clients=` in STATUS.** If it is `none`, the phone was not linked and
   the dashboard cannot deliver — that is not a server bug.

## Things that already bit us — do not undo
- **Desk ACK must reuse the original `mid`** as `ACK-<mid>`. The 16-char cap
  means it has to explicitly forget the dedup entry rather than use a fresh id,
  otherwise the ACK is dropped as a duplicate.
- **`notify ok` from the firmware is not proof of delivery.** The server's job is
  to report the truth; a `notify DROPPED` line means no phone was connected.
- **Stale BLE client entries** used to make the gateway look busy forever. Keep
  the phantom-client cleanup.
- The ACK event must reach the dashboard **immediately** on send, not on the
  next poll, or the desk sees rows that never clear.

## Useful while debugging
`D:\esp32\server_restart.log` is the live gateway log — the richest signal in
the project. It carries `[led]`, `notify`, `LoRa`, `reach`, `rssi`, `snr`,
`clients` and the STALE/FUTURE drop reasons. Point Part 2 at it rather than
re-instrumenting.

The root of `D:\esp32` also holds ~50 one-off diagnostic scripts (`probe*.py`,
`find_*.py`, `read_*.py`, `fix*.py`) left over from earlier sessions. They are
unowned clutter — ignore them, or delete them in a cleanup pass. Do not treat
them as the source of truth.
