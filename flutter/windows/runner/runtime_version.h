#ifndef COOKDEX_RUNTIME_VERSION_H_
#define COOKDEX_RUNTIME_VERSION_H_
#include <windows.h>
#include <string>
#include <vector>
#include <stdexcept>

// Reads the installed executable's version resource, never a source constant.
inline std::string ReadRuntimeVersion(const std::wstring& path) {
  DWORD unused = 0;
  const DWORD size = GetFileVersionInfoSizeW(path.c_str(), &unused);
  if (!size) throw std::runtime_error("Installed version unavailable.");
  std::vector<BYTE> bytes(size);
  if (!GetFileVersionInfoW(path.c_str(), 0, size, bytes.data()))
    throw std::runtime_error("Installed version unavailable.");
  VS_FIXEDFILEINFO* info = nullptr;
  UINT length = 0;
  if (!VerQueryValueW(bytes.data(), L"\\", reinterpret_cast<void**>(&info), &length) ||
      length < sizeof(VS_FIXEDFILEINFO) || info->dwSignature != 0xfeef04bd)
    throw std::runtime_error("Installed version unavailable.");
  return std::to_string(HIWORD(info->dwFileVersionMS)) + "." +
      std::to_string(LOWORD(info->dwFileVersionMS)) + "." +
      std::to_string(HIWORD(info->dwFileVersionLS)) + "+" +
      std::to_string(LOWORD(info->dwFileVersionLS));
}

inline std::string InstalledVersion() {
  std::vector<wchar_t> path(32768);
  const DWORD length = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!length || length >= path.size())
    throw std::runtime_error("Installed executable path unavailable.");
  return ReadRuntimeVersion(std::wstring(path.data(), length));
}
#endif
