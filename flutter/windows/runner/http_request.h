#pragma once
#include <chrono>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

struct HttpReply {
  unsigned status;
  std::string body;
};

// Native-only transport. The platform channel supplies a fixed HTTPS endpoint;
// a loopback endpoint is used by the standalone cancellation tests.
HttpReply HttpRequest(const wchar_t* host, unsigned short port, bool secure,
                      const wchar_t* path, const std::wstring& headers,
                      const std::vector<uint8_t>& body,
                      const std::function<bool()>& cancelled,
                      std::chrono::milliseconds deadline = std::chrono::seconds(180));
