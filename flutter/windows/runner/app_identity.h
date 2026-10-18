#ifndef COOKDEX_APP_IDENTITY_H_
#define COOKDEX_APP_IDENTITY_H_

#ifdef COOKDEX_PRODUCTION
inline constexpr char kAppId[] = "com.sylph.cookdex";
inline constexpr wchar_t kAppName[] = L"cookdex";
inline constexpr wchar_t kCredentialTarget[] = L"com.sylph.cookdex/flutter-v1/gemini";
inline constexpr wchar_t kExportDirectory[] = L"cookdex-production-export";
#else
inline constexpr char kAppId[] = "com.sylph.cookdex.dev";
inline constexpr wchar_t kAppName[] = L"cookdex dev";
inline constexpr wchar_t kCredentialTarget[] = L"com.sylph.cookdex.dev/flutter-v1/gemini";
inline constexpr wchar_t kExportDirectory[] = L"cookdex-dev-export";
#endif

#endif
