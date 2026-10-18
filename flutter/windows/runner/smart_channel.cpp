#include "app_identity.h"
#include "smart_channel.h"
#include "http_request.h"
#include <flutter/standard_method_codec.h>
#include <wincred.h>
#include <winhttp.h>
#include <algorithm>
#include <regex>
#include <string>
#include <vector>
#include <stdexcept>

namespace {
using V = flutter::EncodableValue;
using M = flutter::EncodableMap;
constexpr auto kTarget = kCredentialTarget;
std::string Field(const flutter::MethodCall<V>& call, const char* key) {
  const auto* map = call.arguments() ? std::get_if<M>(call.arguments()) : nullptr;
  if (!map) return {};
  const auto found = map->find(V(key));
  if (found == map->end()) return {};
  const auto* value = std::get_if<std::string>(&found->second);
  return value ? *value : std::string();
}
struct Settings { std::string model = "gemini-3.5-flash-lite"; std::string key; };
Settings Read() {
  PCREDENTIALW credential = nullptr;
  if (!CredReadW(kTarget, CRED_TYPE_GENERIC, 0, &credential)) {
    if (GetLastError() == ERROR_NOT_FOUND) return {};
    throw std::runtime_error("The saved Gemini settings could not be read.");
  }
  std::string value(reinterpret_cast<char*>(credential->CredentialBlob), credential->CredentialBlobSize);
  CredFree(credential);
  const auto split = value.find('\n');
  if (split == std::string::npos) throw std::runtime_error("The saved Gemini settings are invalid.");
  return {value.substr(0, split), value.substr(split + 1)};
}
void Write(const Settings& settings) {
  std::string data = settings.model + "\n" + settings.key;
  CREDENTIALW credential{};
  credential.Type = CRED_TYPE_GENERIC;
  credential.TargetName = const_cast<wchar_t*>(kTarget);
  credential.CredentialBlobSize = static_cast<DWORD>(data.size());
  credential.CredentialBlob = reinterpret_cast<LPBYTE>(data.data());
  credential.Persist = CRED_PERSIST_LOCAL_MACHINE;
  if (!CredWriteW(&credential, 0)) throw std::runtime_error("Gemini settings could not be saved securely.");
  SecureZeroMemory(data.data(), data.size());
}
V Request(const std::vector<uint8_t>& body, const std::atomic<unsigned>& generation, unsigned token) {
  auto settings = Read();
  if (settings.key.empty()) throw std::runtime_error("Save a Gemini key first.");
  std::wstring headers = L"Content-Type: application/json\r\nx-goog-api-key: " + std::wstring(settings.key.begin(), settings.key.end());
  struct Wipe {
    Settings& settings; std::wstring& headers;
    ~Wipe() { SecureZeroMemory(headers.data(), headers.size() * sizeof(wchar_t)); SecureZeroMemory(settings.key.data(), settings.key.size()); }
  } wipe{settings, headers};
  auto reply = HttpRequest(L"generativelanguage.googleapis.com", INTERNET_DEFAULT_HTTPS_PORT,
      true, L"/v1beta/interactions", headers, body, [&] { return generation != token; });
  auto& response = reply.body;
  size_t at = 0;
  while ((at = response.find(settings.key, at)) != std::string::npos) { response.replace(at, settings.key.size(), "[redacted key]"); at += 14; }
  response = std::regex_replace(response, std::regex("AIza[0-9A-Za-z_-]+"), "[redacted key]");
  SecureZeroMemory(settings.key.data(), settings.key.size());
  return V(M{{V("status"), V(static_cast<int>(reply.status))}, {V("bytes"), V(std::vector<uint8_t>(response.begin(), response.end()))}});
}
}
SmartChannel::SmartChannel(flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<V>>(messenger, "com.sylph.cookdex.dev/import", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this, window](const auto& call, auto result) {
    const auto method = call.method_name();
    try {
      if (method == "cancel") { ++generation_; result->Success(); return; }
      if (method == "settings") {
        auto settings = Read();
        result->Success(V(M{{V("hasKey"), V(!settings.key.empty())}, {V("model"), V(settings.model)}}));
      } else if (method == "saveSettings" || method == "removeKey") {
        auto settings = Read();
        if (method == "removeKey") settings.key.clear();
        else {
          const auto model = Field(call, "model"), key = Field(call, "key");
          if (!std::regex_match(model, std::regex("[A-Za-z0-9._-]{1,120}")) || key.size() > 1024 || std::any_of(key.begin(), key.end(), [](unsigned char c) { return c < 33 || c > 126; })) throw std::runtime_error("Check the key and model.");
          settings.model = model;
          if (!key.empty()) settings.key = key;
        }
        Write(settings); SecureZeroMemory(settings.key.data(), settings.key.size()); result->Success();
      } else if (method == "providerRequest") {
        const auto* body = call.arguments() ? std::get_if<std::vector<uint8_t>>(call.arguments()) : nullptr;
        if (!body || body->size() >= 16 * 1024 * 1024) throw std::runtime_error("Import request is too large.");
        if (busy_.exchange(true)) { result->Error("busy", "A request is already running."); return; }
        if (worker_.joinable()) worker_.join();
        auto reply = std::shared_ptr<flutter::MethodResult<V>>(std::move(result));
        const auto token = generation_.load();
        worker_ = std::thread([this, window, reply, body = *body, token]() {
          V value; std::string error;
          try { value = Request(body, generation_, token); }
          catch (const std::exception& e) { error = e.what(); }
          if (!closed_) {
            auto callback = new std::function<void()>([reply, value, error]() { if (error.empty()) reply->Success(value); else reply->Error("import", error); });
            if (!PostMessageW(window, kReply, 0, reinterpret_cast<LPARAM>(callback))) delete callback;
          }
          busy_ = false;
        });
      } else result->NotImplemented();
    } catch (const std::exception& e) { result->Error("settings", e.what()); }
  });
}
void SmartChannel::Reply(LPARAM value) { std::unique_ptr<std::function<void()>> callback(reinterpret_cast<std::function<void()>*>(value)); (*callback)(); }
SmartChannel::~SmartChannel() {
  closed_ = true; ++generation_;
  channel_->SetMethodCallHandler(nullptr);
  if (worker_.joinable()) worker_.join();
  MSG message{};
  while (PeekMessageW(&message, window_, kReply, kReply, PM_REMOVE)) {
    delete reinterpret_cast<std::function<void()>*>(message.lParam);
  }
}
