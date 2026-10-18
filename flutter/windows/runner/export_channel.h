#ifndef RUNNER_EXPORT_CHANNEL_H_
#define RUNNER_EXPORT_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Native exports remain separate from the Flutter-owned recipe core.
class ExportChannel {
 public:
  ExportChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~ExportChannel();

 private:
  class ShareHost;
  std::unique_ptr<ShareHost> share_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_EXPORT_CHANNEL_H_
