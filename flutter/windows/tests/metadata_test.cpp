#include "../runner/runtime_version.h"
#include "../runner/app_identity.h"
#include <iostream>

// Host-only resource reader: never launches cookdex, opens stores or binds sync.
int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  try {
    const auto version = ReadRuntimeVersion(argv[1]);
    try {
      ReadRuntimeVersion(L"cookdex-nonexistent-version-resource.exe");
      return 3;
    } catch (const std::exception&) {}
    const std::string identity(kAppId);
    std::wcout << kCredentialTarget << L"\n"
               << std::wstring(identity.begin(), identity.end()) << L"\n"
               << std::wstring(version.begin(), version.end()) << L"\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what();
    return 1;
  }
}
