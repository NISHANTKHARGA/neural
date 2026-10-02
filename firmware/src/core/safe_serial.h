#pragma once

#include <Arduino.h>
#include <stdarg.h>

#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

// ---------------------------------------------------------------------------
// Line-safe serial output for app-printed packets.
//
// The gateway's packet JSON and any remaining esp_log output come from
// different tasks. Uncoordinated they can interleave byte-by-byte on UART0 and
// truncate the JSON lines the PC server ingests (a truncated line fails the
// dashboard's JSON.parse and the incident is silently dropped). App prints of
// packet JSON hold one recursive mutex so each line is written atomically.
//
// NOTE: this deliberately does NOT hook esp_log_set_vprintf. Funnelling ALL
// esp_log through a mutex deadlocks when the UART event task tries to log
// while the loop task holds the mutex mid-print (event task can't service the
// TX). Instead the firmware builds with NimBLE logging compiled out and
// CORE_DEBUG_LEVEL=ERROR, so esp_log stays minimal and can't collide.
// ---------------------------------------------------------------------------
namespace safetrails {

class SafeSerial {
 public:
  static SafeSerial& instance() {
    static SafeSerial s;
    return s;
  }

  SemaphoreHandle_t mutex() { return mux_; }

  void println(const char* s) {
    take();
    Serial.println(s);
    give();
  }

  void print(const char* s) {
    take();
    Serial.print(s);
    give();
  }

  void printf(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    char buf[768];
    vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    take();
    Serial.print(buf);
    give();
  }

 private:
  SafeSerial() { mux_ = xSemaphoreCreateRecursiveMutex(); }

  void take() { xSemaphoreTakeRecursive(mux_, portMAX_DELAY); }
  void give() { xSemaphoreGiveRecursive(mux_); }

  SemaphoreHandle_t mux_;
};

}  // namespace safetrails