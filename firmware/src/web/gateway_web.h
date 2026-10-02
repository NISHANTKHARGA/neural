#pragma once

// --------------------------------------------------------------------------
// GatewayWeb — makes the rescue gateway a self-contained command hub.
//
//   1. Boots a WiFi soft-AP (ST_AP_SSID / ST_AP_PASS).
//   2. Serves the dashboard assets (index.html / style.css / app.js /
//      shared/protocol/packet.js) from LittleFS over HTTP :80.
//   3. Runs a WebSocket hub on ST_WS_PORT speaking the SAME protocol as the
//      Node server (server/index.js): hello + packet/replay events down,
//      ack/rescue/broad/status_req commands up.
//   4. Appends every terminated packet to a flash log so incidents survive
//      reboots and gaps where nobody was connected.
//
// Serial output is left intact: if a PC later attaches, the existing Node
// bridge still works — the gateway simply serves both audiences.
// --------------------------------------------------------------------------

#include <Arduino.h>
#include <functional>
#include <string>
#include <vector>

#include <WiFi.h>
#include <WebServer.h>
#include <WebSocketsServer.h>

class GatewayWeb {
 public:
  // Receives a complete command JSON line (WebSocket -> gateway engine).
  std::function<void(const std::string& line)> onCommand;

  bool begin(const char* apSsid, const char* apPass, int channel, uint16_t wsPort);
  void loop();

  // A packet that terminated at the gateway: push it to every connected
  // dashboard, and (when `persist`) also write it to the flash log so
  // incidents survive reboots. `jsonLine` is the codec's canonical JSON.
  // STATUS heartbeats are broadcast live (dashboard node liveness) but NOT
  // persisted — only SOS/RESCUE/ACK/BROAD are real incidents.
  void onPacket(const std::string& jsonLine, bool persist = true);

  size_t clientCount() { return ws_.connectedClients(); }

 private:
  WebServer http_{80};
  WebSocketsServer ws_{1337};

  std::vector<std::string> history_;
  size_t historyCap_ = 80;      // lines kept in RAM for replay
  size_t logMax_ = 48 * 1024;   // /incidents.log rotation threshold

  void serveFile(const char* fsPath, const char* mime);
  void loadHistory();
  void appendLog(const std::string& line);
  void replayTo(uint8_t clientNum);
  void fire(WebSocketsServer& srv, uint8_t num, WStype_t type,
            uint8_t* payload, size_t length);
};