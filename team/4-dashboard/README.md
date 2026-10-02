# Part 4 — Web dashboard (desk) + release hosting

**Owner: desk** · Code: `D:\esp32\dashboard`

## Owns
Everything under `D:\esp32\dashboard`, **except** the release APK (see below).
This is the static desk UI that the Part 3 server serves on port 8080.

Key items:
- the static desk/dashboard files
- `SAFETRAILS-app-release.apk` — the hosted install file (~49.6 MB), the bulk of
  this folder's size

## Does not own
Dart, C++, or `server/index.js`. File a change request instead.

## Hosting note
The dashboard and the APK are served by **Part 3's server**, not by this folder.
The install link is:

```
http://<PC-LAN-IP>:8080/SAFETRAILS-app-release.apk
```
Currently `http://192.168.1.68:8080/...`. That IP is the **PC's**, and it changes
when the network changes. If the APK link stops working, check the PC's IP
before suspecting the file.

## Release coordination — read this
The APK is **built by Part 1** and **hosted here**. That makes it the one
artifact two parts touch, and the most common source of confusion:
- Part 1 cuts a release -> Part 1 replaces the file -> Part 1 tells Part 4.
- Do not rebuild or hand-edit the APK. Do not rename it.
- If a tester reports "the app still looks old", the staged APK is out of date,
  or they installed from an old link.

## Verify before you claim done
1. Open the dashboard from the **PC's LAN IP**, not `localhost`.
2. Confirm `/api/health` is `mode":"serial"` — otherwise you are reviewing
   simulator data and every conclusion is worthless.
3. Send a RESCUE and a BROAD from the desk and confirm they reach a connected
   phone (Part 1 will confirm the phone side).
4. Confirm the desk ACK clears the row.
5. Confirm the APK link downloads and the file size matches what Part 1 staged.

## Things that already bit us — do not undo
- **A missing ACK event made rows never clear.** The desk ACK now emits its event
  immediately on send rather than waiting for a poll.
- **Desk ACK and phone ACK share one dedup path**, which is exactly why the
  16-char mid limit and the `ACK-<mid>` reuse matter. See
  `..\0-contract\INTERFACES.md`.
- **Do not add a field the contract does not define.** The desk, the server and
  two firmwares all read the same packet shape.
