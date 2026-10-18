/// Selected together with native identity and Rust sync by scripts/build.ps1.
const isDevelopment = bool.fromEnvironment('COOKDEX_DEV', defaultValue: true);
const appId = isDevelopment ? 'com.sylph.cookdex.dev' : 'com.sylph.cookdex';
const appName = isDevelopment ? 'cookdex dev' : 'cookdex';
