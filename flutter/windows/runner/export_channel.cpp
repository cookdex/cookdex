#include "app_identity.h"
#include "export_channel.h"

#include <flutter/standard_method_codec.h>
#include <roapi.h>
#include <shobjidl_core.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.h>

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <optional>
#include <string>
#include <vector>

namespace {
constexpr size_t kMaxBytes = 64 * 1024 * 1024;
using Transfer = winrt::Windows::ApplicationModel::DataTransfer::DataTransferManager;
using StorageFile = winrt::Windows::Storage::StorageFile;
using StorageItem = winrt::Windows::Storage::IStorageItem;

std::string Argument(const flutter::MethodCall<flutter::EncodableValue>& call,
                     const char* key) {
  if (!call.arguments()) return {};
  const auto* map = std::get_if<flutter::EncodableMap>(call.arguments());
  if (!map) return {};
  const auto found = map->find(flutter::EncodableValue(key));
  if (found == map->end()) return {};
  const auto* value = std::get_if<std::string>(&found->second);
  return value ? *value : std::string();
}

std::wstring Wide(const std::string& value) {
  const auto wide = winrt::to_hstring(value);
  return std::wstring(wide.c_str(), wide.size());
}

bool ValidFilename(const std::wstring& value, bool zip = false) {
  return !value.empty() && value.size() <= 180 &&
         value.size() >= 4 && value.substr(value.size() - 4) == (zip ? L".zip" : L".txt") &&
         value.find_first_of(L"<>:\"/\\|?*") == std::wstring::npos &&
         std::none_of(value.begin(), value.end(), [](wchar_t c) { return c < 32; });
}

std::wstring UniqueName() {
  GUID guid;
  winrt::check_hresult(CoCreateGuid(&guid));
  wchar_t buffer[40] = {};
  if (!StringFromGUID2(guid, buffer, 40)) throw winrt::hresult_error(E_FAIL);
  return buffer;
}

void WriteText(const std::wstring& path, const std::string& text) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr,
                            CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) throw winrt::hresult_error(HRESULT_FROM_WIN32(GetLastError()));
  bool written = true;
  size_t offset = 0;
  while (offset < text.size()) {
    const DWORD size = static_cast<DWORD>(std::min<size_t>(text.size() - offset, 65536));
    DWORD count = 0;
    if (!WriteFile(file, text.data() + offset, size, &count, nullptr) || count != size) {
      written = false;
      break;
    }
    offset += count;
  }
  const bool flushed = written && FlushFileBuffers(file);
  const bool closed = CloseHandle(file);
  if (!written || !flushed || !closed) {
    DeleteFileW(path.c_str());
    throw winrt::hresult_error(E_FAIL, L"Could not write the text file.");
  }
}

std::wstring CacheFile(const std::wstring& filename, const std::string& text) {
  wchar_t temporary[MAX_PATH + 1] = {};
  const DWORD length = GetTempPathW(MAX_PATH + 1, temporary);
  if (!length || length > MAX_PATH) throw winrt::hresult_error(E_FAIL);
  const auto root = std::filesystem::path(temporary) / kExportDirectory;
  std::filesystem::create_directories(root);
  // Cache is exclusively generated share text; leave current grants usable.
  const auto expiry = std::filesystem::file_time_type::clock::now() - std::chrono::hours(24 * 7);
  std::error_code error;
  for (const auto& entry : std::filesystem::directory_iterator(root, error)) {
    if (entry.is_directory(error) && !entry.is_symlink(error) &&
        entry.last_write_time(error) < expiry && !error) {
      std::filesystem::remove_all(entry.path(), error);
    }
    error.clear();
  }
  const auto directory = root / UniqueName();
  std::filesystem::create_directory(directory);
  const auto path = directory / filename;
  WriteText(path.wstring(), text);
  return path.wstring();
}

bool SaveText(HWND owner, const std::wstring& filename, const std::string& text, bool zip = false) {
  winrt::com_ptr<IFileSaveDialog> dialog;
  winrt::check_hresult(CoCreateInstance(CLSID_FileSaveDialog, nullptr,
      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(dialog.put())));
  const COMDLG_FILTERSPEC type[] = {{zip ? L"Recipe ZIP" : L"Text file", zip ? L"*.zip" : L"*.txt"}};
  winrt::check_hresult(dialog->SetFileTypes(1, type));
  winrt::check_hresult(dialog->SetDefaultExtension(zip ? L"zip" : L"txt"));
  winrt::check_hresult(dialog->SetFileName(filename.c_str()));
  DWORD options = 0;
  winrt::check_hresult(dialog->GetOptions(&options));
  winrt::check_hresult(dialog->SetOptions(options | FOS_FORCEFILESYSTEM | FOS_OVERWRITEPROMPT | FOS_NOCHANGEDIR));
  const HRESULT shown = dialog->Show(owner);
  if (shown == HRESULT_FROM_WIN32(ERROR_CANCELLED)) return false;
  winrt::check_hresult(shown);
  winrt::com_ptr<IShellItem> selected;
  winrt::check_hresult(dialog->GetResult(selected.put()));
  PWSTR raw = nullptr;
  winrt::check_hresult(selected->GetDisplayName(SIGDN_FILESYSPATH, &raw));
  const std::wstring path(raw);
  CoTaskMemFree(raw);
  const auto temporary = path + L".cookdex-" + UniqueName() + L".tmp";
  WriteText(temporary, text);
  if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    DeleteFileW(temporary.c_str());
    throw winrt::hresult_error(E_FAIL, L"Could not save the text file.");
  }
  return true;
}
std::optional<std::vector<uint8_t>> OpenFile(HWND owner, bool zip) {
  winrt::com_ptr<IFileOpenDialog> dialog;
  winrt::check_hresult(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(dialog.put())));
  const COMDLG_FILTERSPEC type[] = {{zip ? L"Recipe ZIP" : L"Text file", zip ? L"*.zip" : L"*.txt"}};
  winrt::check_hresult(dialog->SetFileTypes(1, type));
  winrt::check_hresult(dialog->SetOptions(FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST | FOS_NOCHANGEDIR));
  auto shown = dialog->Show(owner);
  if (shown == HRESULT_FROM_WIN32(ERROR_CANCELLED)) return std::nullopt;
  winrt::check_hresult(shown);
  winrt::com_ptr<IShellItem> selected;
  winrt::check_hresult(dialog->GetResult(selected.put()));
  PWSTR raw = nullptr;
  winrt::check_hresult(selected->GetDisplayName(SIGDN_FILESYSPATH, &raw));
  const std::filesystem::path path(raw);
  CoTaskMemFree(raw);
  std::ifstream file(path, std::ios::binary);
  if (!file) throw winrt::hresult_error(E_FAIL);
  std::vector<uint8_t> bytes;
  char buffer[65536];
  while (file.read(buffer, sizeof(buffer)) || file.gcount()) {
    if (bytes.size() + static_cast<size_t>(file.gcount()) > (zip ? 36414454u : 5u * 1024 * 1024)) throw winrt::hresult_error(E_FAIL);
    bytes.insert(bytes.end(), buffer, buffer + file.gcount());
  }
  if (file.bad()) throw winrt::hresult_error(E_FAIL);
  return bytes;
}
}  // namespace

class ExportChannel::ShareHost {
 public:
  explicit ShareHost(HWND window) : window_(window), runtime_(SUCCEEDED(RoInitialize(RO_INIT_SINGLETHREADED))) {}
  ~ShareHost() {
    try {
      if (manager_ && token_.value) manager_.DataRequested(token_);
    } catch (...) {
      // Window shutdown must still release the WinRT apartment.
    }
    manager_ = nullptr;
    if (runtime_) RoUninitialize();
  }

  void Open(const std::string& text, const std::string& title,
            const std::wstring& path) {
    if (!Transfer::IsSupported()) throw winrt::hresult_error(E_NOTIMPL);
    auto interop = winrt::get_activation_factory<Transfer, IDataTransferManagerInterop>();
    if (manager_ && token_.value) manager_.DataRequested(token_);
    winrt::check_hresult(interop->GetForWindow(window_, winrt::guid_of<Transfer>(), winrt::put_abi(manager_)));
    token_ = manager_.DataRequested([text, title, path](auto const&, auto const& args) {
      auto request = args.Request();
      request.Data().Properties().Title(winrt::to_hstring(title.empty() ? "Recipe" : title));
      request.Data().RequestedOperation(winrt::Windows::ApplicationModel::DataTransfer::DataPackageOperation::Copy);
      if (path.empty()) {
        request.Data().SetText(winrt::to_hstring(text));
        return;
      }
      auto deferral = request.GetDeferral();
      try {
        // Resolve files asynchronously; waiting on the STA would deadlock.
        StorageFile::GetFileFromPathAsync(path).Completed([request, deferral](auto const& operation, auto const&) {
          try {
            auto files = winrt::single_threaded_vector<StorageItem>();
            files.Append(operation.GetResults());
            request.Data().SetStorageItems(files);
          } catch (...) {
            request.FailWithDisplayText(L"Could not read the shared text file.");
          }
          deferral.Complete();
        });
      } catch (...) {
        request.FailWithDisplayText(L"Could not read the shared text file.");
        deferral.Complete();
      }
    });
    winrt::check_hresult(interop->ShowShareUIForWindow(window_));
  }

 private:
  HWND window_;
  bool runtime_;
  Transfer manager_{nullptr};
  winrt::event_token token_{};
};

ExportChannel::ExportChannel(flutter::BinaryMessenger* messenger, HWND window)
    : share_(std::make_unique<ShareHost>(window)),
      channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "com.sylph.cookdex.dev/export", &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler([this, window](const auto& call, auto result) {
    const auto text = Argument(call, "text");
    if (text.size() > kMaxBytes) { result->Error("limit", "Text export exceeds 64 MiB."); return; }
    const auto method = call.method_name();
    try {
      if (method == "pickRecipeZip" || method == "pickText") {
        auto bytes = OpenFile(window, method == "pickRecipeZip");
        if (!bytes) result->Success();
        else result->Success(flutter::EncodableValue(*bytes));
      } else if (method == "saveZip") {
        const auto filename = Wide(Argument(call, "filename"));
        if (!ValidFilename(filename, true)) { result->Error("filename", "Invalid backup filename."); return; }
        const auto* map = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        const auto found = map ? map->find(flutter::EncodableValue("bytes")) : flutter::EncodableMap::const_iterator();
        const auto* bytes = map && found != map->end() ? std::get_if<std::vector<uint8_t>>(&found->second) : nullptr;
        if (!bytes || bytes->size() > 36414454u) { result->Error("limit", "Invalid backup size."); return; }
        const bool saved = SaveText(window, filename, std::string(bytes->begin(), bytes->end()), true);
        result->Success(flutter::EncodableValue(saved ? "saved" : "cancelled"));
      } else if (method == "shareText") {
        share_->Open(text, Argument(call, "title"), L"");
        result->Success(flutter::EncodableValue("opened"));
      } else if (method == "shareFile" || method == "saveText") {
        const auto filename = Wide(Argument(call, "filename"));
        if (!ValidFilename(filename)) { result->Error("filename", "Invalid export filename."); return; }
        if (method == "shareFile") {
          const auto path = CacheFile(filename, text);
          share_->Open("", Argument(call, "filename"), path);
          result->Success(flutter::EncodableValue("opened"));
        } else {
          const bool saved = SaveText(window, filename, text);
          result->Success(flutter::EncodableValue(saved ? "saved" : "cancelled"));
        }
      } else {
        result->NotImplemented();
      }
    } catch (const winrt::hresult_error& error) {
      const bool unavailable = (method == "shareText" || method == "shareFile") &&
          (error.code() == E_NOTIMPL || error.code() == REGDB_E_CLASSNOTREG);
      result->Error(unavailable ? "unavailable" : "export", "Could not complete the text export.");
    } catch (...) {
      result->Error("export", "Could not complete the text export.");
    }
  });
}

ExportChannel::~ExportChannel() { channel_->SetMethodCallHandler(nullptr); }
