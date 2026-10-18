# cookdex

A simple, local-first recipe book with a shopping list that actually adds things up. Android and Windows.

No account. No ads. No tracking. Your recipes live on your devices.

<!-- Screenshots go here -->

## Features

- **Add recipes your way**: type them in, paste them, or use **Smart Import** to turn pasted text, a link, or a photo of a handwritten recipe card into a clean recipe (uses your own Gemini API key).
- **Recipe sections**: keep the marinade, sauce, and main dish separate in the recipe.
- **Smart shopping list**: add ingredients from any recipe, with quantities combined and items sorted into store categories.
- **Favorites, tags, search, and card or compact views.**
- **Cook mode and scaling**: adjust servings, check off ingredients, and keep the screen awake while cooking.
- **Share recipes**: send one recipe or a selection as readable text, or import shared recipe files.
- **Sync between your own devices** over your home Wi-Fi. Encrypted, no cloud, no account.
- **Backups**: automatic snapshots on each device, plus ZIP backup/restore and a readable cookbook export.

## Privacy

cookdex only goes online when you do one of these:

- **Sync** with your own paired devices on the same network.
- **Import from a link.** cookdex downloads the recipe page itself, HTTPS sites only.
- **Use Smart Import.** The text, photo, or page you're importing is sent to Google Gemini using your own API key.

There's no analytics, crash reporting, or advertising code.

**About Gemini's free tier:** if you use a free Gemini API key, Google may use what you send to improve its products, and human reviewers may read it. A paid Gemini key avoids this, and so does living in the EEA, UK, or Switzerland. Don't Smart Import anything you'd consider private on a free key. See [Google's current terms](https://ai.google.dev/gemini-api/terms).

Your Gemini key is stored securely on your device (Android Keystore / Windows Credential Manager). It's never included in backups or sync.

## Install

### Android

Most phones from the last several years are supported (64-bit ARM).

1. Download the latest `cookdex-x.y.z-build.apk` from [Releases](https://github.com/cookdex/cookdex/releases).
2. Open it. If Android asks, allow your browser or Files app to install unknown apps.
3. If Play Protect warns about an unrecognized app or offers to scan it, that's normal for any app that isn't from the Play Store. Let it scan, then install.

**Updating:** install the newer APK over the top. Your recipes stay put.
**Automatic updates:** add `https://github.com/cookdex/cookdex` to [Obtainium](https://github.com/ImranR98/Obtainium) and it will notify you about new releases and install them.

### Windows (64-bit)

1. Download `cookdex-windows-x.y.z-build.zip` from [Releases](https://github.com/cookdex/cookdex/releases).
2. Unzip it somewhere permanent, like `Documents\cookdex`. Keep all the files together.
3. Run cookdex from that folder. If Windows says "Windows protected your PC," click **More info → Run anyway**. That happens because the app isn't code-signed.

**Updating:** replace the folder with the new one. Your recipes are stored separately in your Windows user data, so they aren't affected.

## Verifying downloads

<!-- release-certificate -->
Android release certificate SHA-256: `2e432b0d778212330f2b9d5dc830cda5b13d18d67489d52334c41af872e56cd5`
<!-- /release-certificate -->

## Using cookdex

### Smart Import

Get a Gemini API key from [Google AI Studio](https://aistudio.google.com/) and paste it into cookdex's settings. Photo import works on Android only for now.

### Syncing your devices

- Both devices need cookdex open on the same Wi-Fi. On Android, the app has to be on screen.
- Pair once: create an invitation on one device, then scan its QR code (or paste it) on the other.
- On Android 17 and later, allow the local network permission when asked. Sync needs it.
- **Only pair devices you own.** A paired device can change or delete any recipe.

### Backups

- Each device keeps automatic snapshots: one per day for a week, then one per week for a month. Find them in **Settings → Backup & restore → Snapshots**.
- Snapshots live on that device. Export a ZIP backup now and then and keep it somewhere else.
- Sync is not a backup. A deletion on one device syncs to the others.

## Known limitations

- Sync only works while both apps are open on the same network.
- Smart Import from photos is Android-only.
- Some recipe sites can't be imported from a link, including sites without HTTPS. Copy and paste the recipe text instead.
- No iPhone or web version.

## Built with AI

cookdex was built by a non-developer using AI coding tools: mostly OpenAI's Codex, with Claude for planning. The ideas, testing, and decisions are human. The code has had an AI-assisted security review with the findings fixed, but no professional audit.

## Feedback and security issues

- **Bugs and ideas:** open an [Issue](https://github.com/cookdex/cookdex/issues).
- **Security problems:** please report them privately using **Report a vulnerability** on the repo's Security tab, not as a public issue.

## Building from source

See [Development](docs/DEVELOPMENT.md) for the pinned Windows toolchain, dependency setup, host tests and Android/Windows dev builds. Dev builds use a standard Android debug key; no maintainer signing keys or Gemini account are needed.

```powershell
. ./flutter/scripts/env.ps1
./flutter/scripts/build.ps1 -Platform android -Mode release -StandardDebugKey
```

Populate dependency caches first as described in the guide. The APK is `flutter/build/app/outputs/flutter-apk/app-release.apk`. Dev builds have a separate app identity and sync only with other dev builds.

## License

MIT. See [LICENSE](LICENSE).
