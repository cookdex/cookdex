# cookdex
 
A simple, local-first recipe book with a shopping list that actually adds things up. Android and Windows.
 
No account. No ads. No tracking. Your recipes live on your devices.
 
**[Download the latest release](https://github.com/cookdex/cookdex/releases/latest)**
 
<table>
  <tr>
    <td align="center"><img src="https://github.com/user-attachments/assets/90d5cefa-2d36-40ee-b3d3-fc5ff0af29d0" width="180" alt="Recipes list in Cards view"><br><sub>Your recipes</sub></td>
    <td align="center"><img src="https://github.com/user-attachments/assets/c263088b-00ea-4d0d-b4fb-eaa400a4cf56" width="180" alt="A recipe with ingredient sections, scaled to 2×"><br><sub>A recipe at 2×</sub></td>
    <td align="center"><img src="https://github.com/user-attachments/assets/4563a4c7-0380-4774-b18c-3d213e6dd591" width="180" alt="Cook mode with the current step highlighted"><br><sub>Cook mode</sub></td>
    <td align="center"><img src="https://github.com/user-attachments/assets/dee3aec9-089f-4949-b088-3a335ee2ec37" width="180" alt="Shopping list grouped by aisle, with amounts combined across recipes"><br><sub>Shopping list</sub></td>
  </tr>
</table>

## Features
 
- **Add recipes your way.** Type them, paste them, or let Smart Import read a website, a YouTube video, photos of a recipe card or pasted text.
- **Smart Create.** Turn a craving, the ingredients you have or photos of your kitchen into meal ideas, then get the full recipe.
- **A shopping list that adds things up.** Amounts combine across recipes, items sort by store aisle, and each item shows which recipes need it.
- **Cook mode.** Check off ingredients, follow the highlighted step, scale from 0.5× to 5×, and keep the screen awake.
- **Find anything.** Search that handles typos, accents and plurals, plus tags, favorites, and card or compact views.
- **Keep it organized.** Ingredient sections like Sauce or Topping, bold step labels, sources that credit a website, cookbook or family member, and tools to rename or merge ingredients and tags.
- **Your devices, your data.** Encrypted Wi-Fi sync between your own devices, automatic snapshots, recipe ZIP backups, Android backup and phone transfer, and a readable cookbook export.
- **Share recipes.** Send a cookdex recipe file or plain text, and add recipes people send you.

## See it in action
 
<table>
  <tr>
    <td align="center"><img src="https://github.com/user-attachments/assets/99d1457e-34f9-4f49-8ffc-a21e56b4efda" width="240" alt="Smart Create turning a craving into a saved recipe"><br><sub><b>Smart Create</b><br>From a craving to a saved recipe</sub></td>
    <td align="center"><img src="https://github.com/user-attachments/assets/5944870e-5b15-4083-8083-82bfb000809a" width="240" alt="Smart Import reading both sides of a handwritten recipe card"><br><sub><b>Smart Import</b><br>Both sides of a recipe card</sub></td>
    <td align="center"><img src="https://github.com/user-attachments/assets/9be7e3cf-de4f-4f5d-a12c-6970e415ca0d" width="240" alt="Doubling a recipe, adding it to the shopping list and checking items off"><br><sub><b>Shopping list</b><br>Double it, add it, check it off</sub></td>
  </tr>
</table>
<sub>Gemini waits are shortened to about one second.</sub>
 
## Smart features
 
Smart Import’s AI help and Smart Create use your own Gemini API key from Google. Gemini has a free tier.
 
<table>
  <tr>
    <td align="center"><img src="https://github.com/user-attachments/assets/bbfcd601-307e-4a6a-ad74-a35a91f7f2d9" width="240" alt="Smart Import review screen with AI guesses marked"><br><sub>Smart Import marks what the AI guessed</sub></td>
    <td align="center"><img src="https://github.com/user-attachments/assets/0b37dfb9-8586-4c37-849d-187e1ce09e9b" width="240" alt="Smart Create ideas with one idea open"><br><sub>Smart Create ideas</sub></td>
  </tr>
</table>

- **Smart Import** reads websites, YouTube videos and Shorts, up to 8 photos of a recipe, or pasted text. It marks anything the AI estimated or wrote, so you can check it before saving. Without a key, it still reads cookdex files and the recipe details many websites include.
- **Smart Create** suggests dishes from your ingredients, kitchen photos or a craving. Each idea shows what you have, what you’d need to buy and estimated calories per serving. Pick one, and Gemini writes the full recipe for you to review.
- **Getting a key:** create one in [Google AI Studio](https://aistudio.google.com/apikey), then add it in Settings > Smart features > Gemini key. Google requires you to be 18 or older to use the Gemini API.
- **On the free tier,** Google may use what you send to improve its products, and people may review it, so don’t send anything personal. On a paid plan, Google says it doesn’t use your requests to improve its products. See [Google’s Gemini API terms](https://ai.google.dev/gemini-api/terms).

## Privacy
 
cookdex collects no data for itself: there’s no account, analytics, crash reporting or advertising code. Your recipes stay on your devices. Information leaves your device only when a feature needs it:
 
- **Smart Import and Smart Create** send what you give them to Google’s Gemini, using your key.
- **Importing a website or YouTube video** downloads that page. If a site blocks cookdex and Use AI for this link is on, Gemini opens the page instead.
- **Sync** goes directly to your paired devices over your local network, encrypted.
- **Update checks**, if you turn them on, ask GitHub for the latest release.
- **Android backup**, when it’s on and your phone has a screen lock, keeps an encrypted copy in your Google account.
Your Gemini key is stored in Android Keystore or Windows Credential Manager. It’s never included in backups, exports or sync, and neither are your sync pairings. In the app, How cookdex works lists exactly what each feature sends.
 
## Install
 
### Android
 
1. Download the APK from the [latest release](https://github.com/cookdex/cookdex/releases/latest).
2. Open it, and allow installing from your browser or Files app when Android asks.
3. Play Protect may show a warning because cookdex isn’t from Google Play. Choose the option to install anyway.
To get updates automatically, you can track releases with [Obtainium](https://github.com/ImranR98/Obtainium).
 
### Windows (64-bit)
 
<img src="https://github.com/user-attachments/assets/f7aaa028-ab75-4bc4-b64c-664733cf81ab" width="720" alt="cookdex on Windows, showing a recipe with its steps, notes and source">

1. Download the Windows ZIP from the [latest release](https://github.com/cookdex/cookdex/releases/latest).
2. Right-click it, choose Extract All, and extract it to a folder you’ll keep.
3. In the extracted folder, double-click Create shortcut.cmd to make a cookdex shortcut, or run cookdex.exe directly.
Windows SmartScreen may warn you because cookdex isn’t code-signed. Choose More info, then Run anyway.
 
### Updating
 
- **Android:** install the new APK over the old one. Your recipes and settings stay.
- **Windows:**
  1. Close cookdex, download the new ZIP and choose Extract All.
  2. Extract it to the folder that holds your current cookdex folder, so the old and new versions sit side by side.
  3. In the new folder, double-click Create shortcut.cmd to point your shortcut at the new version. If you copied the shortcut to your desktop, replace that copy too.
  4. Open cookdex and check the version in Settings > About. Your recipes and settings live with your Windows account, not in the app folder, so once they show up you can delete the old folder.
- **If you sync,** update every paired device. They stay paired, and a device on an older version shows Update needed until it’s updated too.
Downloading a recipe ZIP before an update is a good habit.
 
## Using cookdex
 
How cookdex works, in Settings, covers everything in detail. The essentials:
 
- **Syncing your devices:** both devices need cookdex open on the same Wi-Fi. Pair once by scanning a QR code (Android) or pasting an invitation. On Android 17 and later, allow the local network permission. Only pair devices you own: edits and deletions reach every paired device.
- **Backups:** cookdex keeps daily snapshots for a week and weekly ones for a month, in Settings > Backup & restore > Snapshots. For a copy you control, download a recipe ZIP. Sync isn’t a backup: a deletion on one device syncs to the others.
- **Moving to a new phone:** download a recipe ZIP on the old phone first. Install cookdex on the new one; Android may bring your data along from its backup. If it doesn’t, restore the ZIP or pair with a device that has your recipes. Then add your Gemini key and pair your devices again.

## Known limitations
 
- Sync only works while cookdex is open on both devices, on the same network. On Android, keep it on screen.
- The AI features need your own Gemini key.
- Gemini can watch YouTube videos up to 15 minutes long. Longer videos import only from a recipe written in the description or a linked recipe page.
- cookdex can’t import from TikTok, Instagram, Threads, Facebook, X, Reddit or Pinterest.
- Some recipe sites block imports. With Use AI for this link on, Gemini can often open them anyway.
- Smart Import from photos is Android-only.
- There’s no iPhone or web version.

## Built with AI
 
cookdex was built by a non-developer using AI coding tools: mostly OpenAI’s Codex, with Claude for planning and reviews. The ideas, testing and decisions are human. The code has had an AI-assisted security review with the findings fixed, but no professional audit.
 
## Feedback and security issues
 
Found a bug or have an idea? [Open an issue](https://github.com/cookdex/cookdex/issues). Copy app info, at the end of How cookdex works, adds your app version and device to your report.
 
Please report security problems privately through the repository’s [Security tab](https://github.com/cookdex/cookdex/security), not in a public issue.

## Verifying downloads

<!-- release-certificate -->
Android release certificate SHA-256: `2e432b0d778212330f2b9d5dc830cda5b13d18d67489d52334c41af872e56cd5`
<!-- /release-certificate -->

## Building from source

See [Development](docs/DEVELOPMENT.md) for the pinned Windows toolchain, dependency setup, host tests and Android/Windows dev builds. Dev builds use a standard Android debug key; no maintainer signing keys or Gemini account are needed.

```powershell
. ./flutter/scripts/env.ps1
./flutter/scripts/build.ps1 -Platform android -Mode release -StandardDebugKey
```

Populate dependency caches first as described in the guide. The APK is `flutter/build/app/outputs/flutter-apk/app-release.apk`. Dev builds have a separate app identity and sync only with other dev builds.

## License

MIT. See [LICENSE](LICENSE).
