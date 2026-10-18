/// All reader-facing help copy lives here. Update this alongside feature changes.
/// Google setup/data-use sources verified 2026-10-09; no API calls were made.
class HelpLink {
  const HelpLink(this.label, this.url);
  final String label;
  final String url;
}

class HelpSection {
  const HelpSection(
    this.id,
    this.title,
    this.paragraphs, {
    this.links = const [],
  });
  final String id;
  final String title;
  final List<String> paragraphs;
  final List<HelpLink> links;
}

const helpTitle = 'How cookdex works';
const helpIntroduction =
    'Your recipes, ready when you need them. Tap a section to learn more.';
const helpCopyAppInfo = 'Copy app info';
const helpAppInfoCopied = 'App info copied';
const helpAppInfoFailure = 'Could not copy app info. Please try again.';
const helpLinkFailure = 'Could not open the link. Please try again.';

const helpSections = <HelpSection>[
  HelpSection('start', 'Start here', [
    'Switching tabs keeps your place. Back closes temporary controls first, then returns from Shopping list or Settings to Recipes as you left it. From an open recipe it returns to the list; from the list it leaves selection mode, then clears an active search before leaving the app. The back gesture and back button work the same way.',
    'Ingredient and tag suggestions group similar names and use the most-used spelling. Saving tidies extra spaces. For new or renamed entries, review matching library spellings: keep a change checked to use it, uncheck it to keep your spelling, or go Back to edit. Amounts and notes stay as entered.',
    '1. Add a recipe. Start with Smart Import or Write a recipe in your empty recipe book. Once you have recipes, use the + button to add another.',
    'Use Favorites to show your starred recipes; its star fills when the filter is on. Tap the view icon to switch between Cards and Compact. Its icon shows the view you will switch to. Compact shows all tags on one line, with an ellipsis when they do not fit. On a narrow screen, slide the controls sideways to reach them.',
    'The Makes field accepts servings or a yield, such as 4 servings or 12 tortillas. People icons show servings; a box icon shows a yield. Scaling adjusts either. In a grid, cards share a height with up to two title lines and three title/description lines in total; extra tags appear as +N.',
    'In Settings > Appearance, choose System, Light or Dark under Theme. System follows your device. On Android 12 or later, Wallpaper colors follows the palette selected in your device’s Wallpaper & style settings in either theme. Colors refresh when you return to cookdex.',
    '2. Set up Smart Import if you want help reading recipe text, websites or photos. See Smart Import setup below.',
    '3. Pair your own devices in Settings > Sync > Add a device if you want the same recipe book on each one. Only pair devices that should share a library.',
  ]),
  HelpSection('adding', 'Adding recipes', [
    'Choose Write a recipe to enter the title, ingredients, steps and any notes yourself. You can edit a saved recipe from its menu. Tap where you want the cursor. When the keyboard offers Next, it moves to the next field. Drag the editor to hide the keyboard; tap a field to continue typing. Hold the handle beside Optional to reorder an ingredient.',
    'Drag an ingredient past a section heading to move it into that section, including an empty section or the unnamed group at the top. Its amount, unit and notes stay with it.',
    'Short step lead-ins ending in a colon appear in bold when reading or cooking. Editing keeps the original plain text.',
    'Tap the circle beside Ingredients to choose 0.5× through 5× in half steps. Swipe the options sideways; choosing one closes them. Tap outside or press Back to close without changing the scale. Cook mode and Add to shopping list use those amounts. Steps, times and temperatures stay as written. Reopening a recipe resets it to 1×.',
    'Amounts can be whole numbers, decimals, fractions or ranges such as 6–7 and 1/2–3/4. Put the smaller amount first. Ranges stay as amounts when you cook, share or add ingredients to the shopping list. When reading or cooking, amounts stand out gently and colored section headings keep ingredient groups easy to scan.',
    'Smart Import can start from pasted text, a secure (HTTPS) recipe link, or up to 8 photos. Links must stay secure through any redirects. If a site uses HTTP, copy and paste the recipe text instead. Take clear photos of the whole recipe, including any second page.',
    'On Android 10 or newer, Save photos to device saves full-resolution camera and gallery copies in the cookdex album when you save the recipe. It starts off and remembers your choice. Gallery originals stay untouched. Non-JPEG gallery photos are converted to JPEG at full resolution. Clearing the import saves nothing; unfinished private photo copies are removed at the next app launch.',
    'Open a cookdex .txt file or paste its text to import locally without AI. One recipe opens the editor; several open a checklist. Exact duplicates start unchecked, and same-name recipes are saved separately. You can review library spellings once for the selected recipes. A damaged block offers Try Smart Import; only that action sends it to Google. Text files must be 5 MB or less.',
    'On Android, open a .txt file with cookdex or share text, a link or photos from another app. The matching import tab opens. If you are editing, the share waits until you finish; your draft stays intact. Back from a share that opened cookdex returns to the sending app after any queued shares.',
    'Always review the recipe before saving. Check amounts, ingredient names and steps against the original. “AI guess” means the AI inferred something. “AI-written” means it wrote the steps. Both mean “double-check this”. Nothing from Smart Import saves until you choose Save.',
  ]),
  HelpSection(
    'smart',
    'Smart Import setup',
    [
      'AI import needs your own Gemini API key. A key is like a password that lets cookdex ask Google for help. You can get one for the free tier in Google AI Studio; keep it private.',
      '1. Open Google AI Studio using the button below. Sign in with your Google account and read and accept Google’s terms if asked.',
      '2. Open Dashboard > API Keys. New users may already have a default project and key. Otherwise choose Create API key and select a project. If an existing project is missing, open Dashboard > Projects > Import projects first, then return to API Keys.',
      '3. Copy the key. In cookdex, open Settings > Smart Import settings, paste it into Gemini key and choose Save. Keep the default model unless you have a reason to change it. Test key checks that it works.',
      'Set up the key separately on each device. The key stays on that device and is not included in recipe backups or sync. The free tier limits how many imports you can make per day and how quickly you can make them. Limits vary; see your current allowance in AI Studio. You do not need to enable paid billing to use an available free tier.',
      'Without a key, you can still write and edit recipes, cook, shop, share, back up and sync. Smart Import can read supported recipe text and recipe information built into some websites. Photos and AI help need a key. A link with Use AI for this link turned off does not send anything to Google; it still contacts the recipe website.',
      'When you use AI, cookdex sends the text or photos you selected, or the recipe link and securely downloaded page text, along with instructions and your tag names. It does not send your whole recipe book. AI link import needs cookdex to download the page securely first. If the site blocks the download, paste the recipe text instead. Check photos for anything private before importing.',
      'Google’s free-tier terms say submitted content and replies may be used to improve Google products and AI, and human reviewers may read them. Do not send personal, sensitive or confidential information. Different data-use rules apply in the European Economic Area, Switzerland and the UK, and to API projects with paid billing. Read the current terms below before using the service.',
    ],
    links: [
      HelpLink('Open Google AI Studio', 'https://aistudio.google.com/apikey'),
      HelpLink(
        'Google’s key setup guide',
        'https://ai.google.dev/gemini-api/docs/api-key',
      ),
      HelpLink(
        'Google’s terms and data use',
        'https://ai.google.dev/gemini-api/terms',
      ),
      HelpLink(
        'Google’s current limits',
        'https://ai.google.dev/gemini-api/docs/rate-limits',
      ),
    ],
  ),
  HelpSection('cooking', 'Cooking', [
    'Open a recipe and choose Cook. Previous and Next help you follow one step at a time. Tap ingredients to check them off as you use them; this does not change the recipe.',
    'Cook mode keeps the screen awake while it is open. Leave Cook mode when you are finished. If cookdex cannot keep the screen on, it tells you.',
  ]),
  HelpSection('shopping', 'Shopping list', [
    'The small line under an ingredient shows its recipe names. Scaled quantities are already included in the ingredient amount.',
    'Open a recipe’s menu and choose Add to shopping list. You can choose which ingredients to add. You can also type items straight into the Shopping list.',
    'Tap an item to check it off. The menu lets you check all, uncheck all or remove checked items. Watch for Undo if you change your mind.',
    'Long-press an item (or right-click it) and choose Delete to remove it. Tap Undo to bring it back. Swiping across an item does not delete it.',
    'Unchecked items are grouped in aisle order. Each category heading shows how many items are still unchecked and stays at the top while you scroll through that category. In the shopping menu, choose Categories to add, rename, delete or reorder categories. Empty groups stay hidden. Other is the fallback group; you can rename or reorder it, but it cannot be deleted.',
    'Hold a drag handle to reorder items within a category, move items between visible categories or reorder categories in their list. Long-press an item and choose Move to category to change its aisle. cookdex remembers that ingredient name for next time. New items go to the end; checked items keep their place when unchecked.',
    'Common ingredients find an aisle automatically, entirely on your device. Unknown names go to Other until you move them. Recipe water and ice are skipped; you can still add them by hand.',
    'Your shopping list stays on this device. It does not sync with your other devices. Settings can keep the shopping screen awake while you use it.',
  ]),
  HelpSection('sync', 'Sync', [
    'In Sync settings, Sync now is beside the current status. Add a device is at the bottom of Paired devices.',
    'To pair, choose Invite a device on one device and Join a device on the other. On Android, use Scan QR code or paste the invitation; on Windows, paste it. Each invitation works once and expires after ten minutes. Keep it private.',
    'QR scanning uses the camera and reads the code on your device. It does not upload camera images or send scanner diagnostics. If Camera access is unavailable, go back and paste the invitation instead.',
    'After successful pairing, a copied invitation cannot reconnect. If setup does not finish, try again with a fresh invitation. Pairing sets up the connection; it does not exchange recipes itself. Normal sync follows pairing.',
    'If the final reply is interrupted, Sync settings shows Unfinished pairing. Try Sync now to finish connecting, or try a fresh invitation. To remove it, open that device and choose Forget setup. This also removes any previous pairing with that device; your recipes stay on each device.',
    'After the sync security update, pair your devices again. Your recipes and other settings are unchanged. Got it dismisses the reminder in Sync settings.',
    'Sync connects your own devices on the same Wi-Fi. There is no cookdex account or cloud recipe storage. On Android, keep cookdex on screen. On Windows, keep it open; it can be minimized.',
    'Paired devices share one recipe book. Recipes already on either device join that book, and later edits and deletions reach every paired device. Only pair devices that should share a library. To give recipes to a friend, open a recipe’s menu and choose Share, then Send as message, Send as .txt file, Copy text or Save .txt file. Choose Select to pick several recipes first. Select all selects the currently shown recipes. You can share the selection or add it all to shopping at 1×. Shared text leaves out favorites, device details and shopping state.',
    'Red · Sync failure: something needs your attention. Open Sync settings for the reason and what to do next. A device that is off or away is not a failure.',
    'Red · Update needed: follow the message to update this device or the other device, then retry. All devices need a compatible cookdex version to sync.',
    'Yellow · Sync conflict: the same recipe changed differently on two devices, or one device deleted it while another edited it. Tap the status to compare the numbered versions. Use version keeps the version you choose; Use deletion removes it; Keep all keeps separate recipe copies. Your choice then reaches the other devices.',
    'Muted neutral · Not synced: some changes are waiting to reach a paired device. Open cookdex on each device on the same Wi-Fi and give it time to catch up.',
    'Soft green · Synced: every paired device has all of this device’s changes. While a new save is travelling, a brief neutral Syncing label gives it a few seconds to reach your devices.',
    'Grey · Sync off: sync is switched off or there are no paired devices. Tap the status to open Sync settings.',
  ]),
  HelpSection('backups', 'Backups', [
    'If recipes cannot be read safely, cookdex sets them aside and keeps your readable recipes available. Sync pauses until those recipes are restored or discarded. On Recipes, choose Review options for help. Restore a known-good recipe ZIP or recover the previous save in Backup & restore to try to recover them. Discard permanently deletes them, cannot be undone, and sends those deletions to paired devices when sync resumes.',
    'A new recipe ZIP or readable cookbook leaves out set-aside recipes and tells you how many were omitted. Keep older backups until you have recovered everything you need.',
    'Snapshots in Settings > Backup & restore saves local recipe ZIPs automatically while cookdex is open: at most once a day when recipes or category setup changed, and before a ZIP restore, discarding set-aside recipes or the first sync with a newly paired device. Snapshot failures do not stop saving or syncing; repeated failures show a quiet notice.',
    'Snapshots keeps up to seven daily and four weekly copies within 256 MiB, pruning the oldest first. The last copy stays available when nothing changes. The newest pre-restore copy is protected until another snapshot succeeds, even if it exceeds the cap. Unreadable recipes are omitted and counted; resolve conflicts before a complete snapshot can be saved.',
    'Open Snapshots to review and restore a copy, or export its ZIP. Restore adds missing recipes and updates matching recipes only when the backup is newer; it never deletes recipes. Turn off sync or forget a troublesome device before recovery. Snapshots stay on this device and disappear if its app data is lost or cleared, so keep exported copies somewhere safe too.',
    'Recipes live only on your devices. Make a backup now and then, especially before changing devices, and keep it somewhere safe outside the app.',
    'In Settings > Backup & restore, choose Download recipe ZIP. Restore recipe ZIP brings recipes from a backup into cookdex. Save readable cookbook gives you a copy you can read outside the app.',
    'If your recipe book is empty, Restore a backup takes you straight to choosing a recipe ZIP. You can review it before restoring.',
    'A recipe ZIP contains recipes and your shopping category setup: aisle order, custom categories and remembered placements. Restore replaces that setup on this device when the ZIP includes it; older ZIPs leave your setup alone. It does not contain your Gemini key, paired devices, shopping list items or other settings. Sync helps devices share changes, including deletions; it is not a replacement for a separate backup.',
    'Clean up recipes previews corrections before you apply them, including clear older quantity ranges kept in preparation notes when the amount is empty. Saving an edited recipe can recover these ranges too; uncertain wording stays in the note. Recipes with unresolved conflicts are skipped during cleanup. Cleanup saves ordinary recipe changes that can sync; restoring a ZIP does not silently clean up recipes. Update all your devices before sharing ZIPs that contain quantity ranges.',
  ]),
  HelpSection('limits', 'Not yet', [
    'A few things are still on the way:',
    '• Steps cannot have section headings yet.\n• Cook mode has no timers.\n• Android sync stops when cookdex is no longer on screen.',
  ]),
  HelpSection('feedback', 'Problems and feedback', [
    'If something looks wrong, send the person who gave you cookdex a screenshot and a short note about what you were doing and what you expected. Copy app info below and include it in your message. It contains the installed app version and build, device and Android or Windows version.',
    'Check the screenshot for anything you do not want to share. Do not send your Gemini key or a pairing invitation.',
  ]),
];
