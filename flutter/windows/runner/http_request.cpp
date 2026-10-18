#include "app_identity.h"
#include "http_request.h"
#include <windows.h>
#include <winhttp.h>
#include <condition_variable>
#include <mutex>
#include <stdexcept>

namespace {
struct Internet {
  HINTERNET handle;
  explicit Internet(HINTERNET h) : handle(h) {
    if (!h) throw std::runtime_error("Could not connect securely.");
  }
  ~Internet() { WinHttpCloseHandle(handle); }
};
struct Completion {
  std::mutex mutex;
  std::condition_variable wake;
  DWORD event = 0;
  DWORD count = 0;
  bool closed = false;
  static void CALLBACK Notify(HINTERNET, DWORD_PTR context, DWORD status,
                              void*, DWORD length) {
    if (!context) return;
    auto& state = *reinterpret_cast<Completion*>(context);
    std::lock_guard guard(state.mutex);
    if (status == WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING) state.closed = true;
    else { state.event = status; state.count = length; }
    state.wake.notify_all();
  }
};
class AsyncRequest {
 public:
  Completion completion;
  HINTERNET handle;
  explicit AsyncRequest(HINTERNET value) : handle(value) {
    if (!handle) throw std::runtime_error("Could not create secure request.");
    DWORD_PTR context = reinterpret_cast<DWORD_PTR>(&completion);
    if (!WinHttpSetOption(handle, WINHTTP_OPTION_CONTEXT_VALUE, &context, sizeof(context)) ||
        WinHttpSetStatusCallback(handle, Completion::Notify,
          WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE | WINHTTP_CALLBACK_FLAG_HEADERS_AVAILABLE |
          WINHTTP_CALLBACK_FLAG_READ_COMPLETE | WINHTTP_CALLBACK_FLAG_REQUEST_ERROR |
          WINHTTP_CALLBACK_FLAG_HANDLES, 0) == WINHTTP_INVALID_STATUS_CALLBACK) {
      WinHttpCloseHandle(handle);
      throw std::runtime_error("Could not configure secure request.");
    }
  }
  ~AsyncRequest() {
    // Only the worker calls WinHTTP, and every operation is asynchronous. Close
    // cancels pending I/O, then retain context and read buffers through the last
    // callback. Never close a synchronous request from a competing thread.
    WinHttpCloseHandle(handle);
    std::unique_lock guard(completion.mutex);
    completion.wake.wait(guard, [&] { return completion.closed; });
  }
  DWORD Wait(DWORD expected, const std::function<bool()>& cancelled,
             std::chrono::steady_clock::time_point end) {
    std::unique_lock guard(completion.mutex);
    for (;;) {
      if (cancelled()) throw std::runtime_error("Request cancelled.");
      if (std::chrono::steady_clock::now() >= end)
        throw std::runtime_error("Google's request timed out.");
      if (completion.event) {
        const DWORD event = completion.event;
        completion.event = 0;
        if (event != expected) throw std::runtime_error("Google's secure connection failed or was interrupted.");
        return completion.count;
      }
      completion.wake.wait_for(guard, std::chrono::milliseconds(50));
    }
  }
};
}

HttpReply HttpRequest(const wchar_t* host, unsigned short port, bool secure,
                      const wchar_t* path, const std::wstring& headers,
                      const std::vector<uint8_t>& body,
                      const std::function<bool()>& cancelled,
                      std::chrono::milliseconds deadline) {
  const auto end = std::chrono::steady_clock::now() + deadline;
  if (cancelled()) throw std::runtime_error("Request cancelled.");
  Internet session(WinHttpOpen(kAppName, WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
      WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, WINHTTP_FLAG_ASYNC));
  WinHttpSetTimeouts(session.handle, 30000, 30000, 30000, 90000);
  Internet connection(WinHttpConnect(session.handle, host, port, 0));
  // These buffers outlive the request, including cancellation callbacks.
  char buffer[65536];
  AsyncRequest request(WinHttpOpenRequest(connection.handle, L"POST", path, nullptr,
      WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, secure ? WINHTTP_FLAG_SECURE : 0));
  DWORD disable = WINHTTP_DISABLE_REDIRECTS;
  if (!WinHttpSetOption(request.handle, WINHTTP_OPTION_DISABLE_FEATURE, &disable, sizeof(disable)))
    throw std::runtime_error("Could not configure secure request.");
  if (!WinHttpSendRequest(request.handle, headers.c_str(), static_cast<DWORD>(headers.size()),
      const_cast<uint8_t*>(body.data()), static_cast<DWORD>(body.size()),
      static_cast<DWORD>(body.size()), reinterpret_cast<DWORD_PTR>(&request.completion)))
    throw std::runtime_error("Could not send secure request.");
  request.Wait(WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE, cancelled, end);
  if (!WinHttpReceiveResponse(request.handle, nullptr))
    throw std::runtime_error("Could not receive secure response.");
  request.Wait(WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE, cancelled, end);
  DWORD status = 0, size = sizeof(status);
  if (!WinHttpQueryHeaders(request.handle, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX, &status, &size, WINHTTP_NO_HEADER_INDEX))
    throw std::runtime_error("Could not read Google's response.");
  DWORD expected_size = 0;
  size = sizeof(expected_size);
  const bool has_size = WinHttpQueryHeaders(request.handle,
      WINHTTP_QUERY_CONTENT_LENGTH | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX, &expected_size, &size, WINHTTP_NO_HEADER_INDEX) != FALSE;
  if (!has_size && GetLastError() != ERROR_WINHTTP_HEADER_NOT_FOUND)
    throw std::runtime_error("Google's response has an invalid length.");
  if (has_size && expected_size > 2 * 1024 * 1024)
    throw std::runtime_error("Google's reply exceeds 2 MiB.");
  std::string response;
  for (;;) {
    if (!WinHttpReadData(request.handle, buffer, sizeof(buffer), nullptr))
      throw std::runtime_error("Google's response was interrupted.");
    const auto count = request.Wait(WINHTTP_CALLBACK_STATUS_READ_COMPLETE, cancelled, end);
    if (!count) break;
    if (response.size() + count > 2 * 1024 * 1024)
      throw std::runtime_error("Google's reply exceeds 2 MiB.");
    response.append(buffer, count);
  }
  if (has_size && expected_size != response.size())
    throw std::runtime_error("Google's response was interrupted.");
  return {status, response};
}
