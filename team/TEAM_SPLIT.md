# SAFETRAILS — 4-member work split

Four people, four parts. Each part is owned end-to-end by one person: they ship
changes, verify them, and are the only ones who touch those files.

| # | Part | Member | Real path (do not move) | Size |
|---|------|--------|------------------------|------|
| 1 | Mobile app | **T102** | `D:\esp32\mobile` | 79 files |
| 2 | ESP32 firmware | **N-A** | `D:\esp32\firmware` | 27 files |
| 3 | Node server | **RCUE** | `D:\esp32\server` | 5 files |
| 4 | Web dashboard | **desk** | `D:\esp32\dashboard` | 4 files |

Shared reference material lives in `D:\esp32\docs` (`ARCHITECTURE.md`,
`WIRING.md`, `TESTING.md`) and is owned by **nobody** — anyone may improve it,
but nobody "owns" it and it must not be used to block another part.

## Why nothing was moved

The build and flash tooling hardcodes absolute paths
(`flash_com8.py` runs `python -m platformio` with `cwd=D:\esp32\firmware`,
`flash_gw8.py` likewise, `build_apk.py` targets `D:\esp32\mobile`). Relocating
the trees breaks every script and the currently-working system. The split is
therefore an **ownership map**, not a physical move. If you want real
per-member repositories, that is a separate piece of work — do it with the
scripts updated in the same commit.

## The one rule that matters

The four parts only communicate through the interfaces in
`0-contract\INTERFACES.md`. **Nobody changes a UUID, a field name, a port, a
radio setting or a packet size without telling the other three.** Those values
are duplicated in four languages (Dart, C++, JavaScript, C) and changing one
side silently breaks the other three.

## Working agreements

- Merge small and often. A part that has been dark for two days is the reason
  integration day goes badly.
- Every change ships with the verification from its part's README. "It works on
  my machine" is not verification.
- If you need a change in someone else's part, file it — do not edit it.
  Cross-part edits are how duplicate/conflicting copies appear.

## Hardware rules (everyone)

- **Only the receiver (RCUE) lives on the PC's USB/COM8.** The transmitter
  runs on its own power. The dashboard reads the receiver's serial, so the
  dashboard is only alive while the receiver is plugged in.
- **Before flashing anything**, stop the server. It holds COM8 open and the
  flash fails with `Access is denied` otherwise.
- **To put a board into download mode**: hold `BOOT`, tap `EN`, release `BOOT`.
  Plugging in the cable alone is not enough.
- After flashing a board, the server must be restarted with `SERIAL_PORT=COM8`
  set. Without it the server silently runs in `simulator` mode and shows
  **fake data** on the dashboard. Check `/api/health` says `"mode":"serial"`.
