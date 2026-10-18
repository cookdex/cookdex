#pragma once
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <memory>
#include <thread>
#include <atomic>
#include <mutex>
#include <functional>

class SmartChannel {
 public:
  SmartChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~SmartChannel();
  static constexpr UINT kReply = WM_APP + 91;
  static void Reply(LPARAM value);
 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::thread worker_;
  std::atomic<bool> busy_{false};
  std::atomic<bool> closed_{false};
  std::atomic<unsigned> generation_{0};
  HWND window_;
};
