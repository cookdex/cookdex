/// All reader-facing help copy lives here. Update this when typical users need new guidance.
/// Google setup/data-use sources verified 2026-10-18; no API calls were made.
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
  HelpSection('start', 'Getting started', [
    'cookdex keeps your recipes on your own devices. There\'s no account and no cloud.',
    '1. Add a recipe. Choose Write a recipe to type one in, or Smart Import to read one from text, a website or photos. Once you have recipes, use the + button to add more.',
    '2. Set up Smart Import if you want help reading recipes. It\'s optional; everything else works without it. See Setting up Smart Import.',
    '3. Pair your other devices if you want the same recipe book on each one. See Syncing your devices.',
    'To find recipes, use search, tags and the Favorites filter. The view button switches between Cards and Compact.',
  ]),
  HelpSection('adding', 'Adding and editing recipes', [
    'Choose Write a recipe to add your own, or open a recipe\'s menu to edit it.',
    '• Amounts can be whole numbers, fractions, decimals or ranges like 6–7. Tap to taste above the keyboard when no exact amount is needed.',
    '• Makes can be servings or a yield, like 4 servings or 12 tortillas.',
    '• For cans and jars, put the size in the unit, like 1 (16 oz) jar salsa. The size then shows everywhere, including your shopping list, and stays the same when you scale.',
    '• Group ingredients under section headings like Sauce or Topping. Hold an ingredient\'s drag handle and move it past a heading to put it in that section.',
    '• Start a step with a short label and a colon, like "Make the sauce:", and the label shows in bold when you read or cook.',
    '• As you type, cookdex suggests ingredient names and tags you\'ve used before. When you save, it may offer to match a new spelling to one you already use. Uncheck anything you want to keep as you typed it.',
  ]),
  HelpSection('import', 'Smart Import', [
    'Smart Import turns recipe text, a website link, or up to 8 photos of a recipe into a recipe you can edit. Photos and AI help need a Gemini key; see Setting up Smart Import.',
    '• For photos, take clear shots of the whole recipe, including any second page.',
    '• If a website won\'t import, copy and paste the recipe text instead.',
    '• Always check the recipe against the original before saving. "AI guess" and "AI-written" mark parts the AI filled in, so double-check those. Nothing is saved until you choose Save.',
    '• On Android, Save photos to device keeps copies of your photos in a cookdex album when you save the recipe. Handy for keeping the original cards.',
    'Without a key, Smart Import can still read cookdex recipe files and the recipe details some websites include.',
  ]),
  HelpSection(
    'smart',
    'Setting up Smart Import',
    [
      'Smart Import\'s AI help uses your own Gemini API key. A key is like a password that lets cookdex ask Google for help, so keep it private.',
      '1. Open Google AI Studio with the button below and sign in with your Google account.',
      '2. Open API Keys and create a key, or copy the one that\'s already there.',
      '3. In cookdex, open Settings > Smart Import settings, paste the key and choose Save. Test key checks that it works.',
      'The key stays on this device and isn\'t included in backups or sync, so set it up on each device where you want Smart Import. The free tier limits how many imports you can do each day.',
      'When you use AI, cookdex sends Google only what you\'re importing (the text, photos or web page) plus your tag names, never your whole recipe book. On the free tier, Google may use what you send to improve its products, and people at Google may read it. Don\'t import anything private, and check photos before you send them. Paid keys and some regions have different rules; see Google\'s terms.',
    ],
    links: [
      HelpLink('Open Google AI Studio', 'https://aistudio.google.com/apikey'),
      HelpLink(
        'Google\'s key setup guide',
        'https://ai.google.dev/gemini-api/docs/api-key',
      ),
      HelpLink(
        'Google\'s terms and data use',
        'https://ai.google.dev/gemini-api/terms',
      ),
    ],
  ),
  HelpSection('cooking', 'Cooking', [
    'Open a recipe and choose Cook. Previous and Next take you through one step at a time. Tap ingredients to check them off as you go; this doesn\'t change the recipe. The screen stays awake while Cook mode is open.',
    'To make more or less, tap the 1× circle beside Ingredients and choose anything from 0.5× to 5×. Cook mode and Add to shopping list use the new amounts. Steps, times and temperatures stay as written, so adjust those yourself. Reopening the recipe sets it back to 1×.',
  ]),
  HelpSection('shopping', 'Shopping list', [
    'Open a recipe\'s menu and choose Add to shopping list, then pick the ingredients you need. You can also type items straight into the list.',
    '• Tap an item to check it off. The menu can check all, uncheck all or remove checked items.',
    '• Long-press an item to delete it or move it to another category. cookdex remembers where you put it next time.',
    '• Items are grouped by store aisle. Common ingredients find their aisle automatically; anything else goes to Other until you move it.',
    '• The same ingredient from different recipes is combined; different package sizes stay separate. The small line under each item shows which recipes it came from.',
    '• Drag the handles to reorder items and categories. In the menu, Categories lets you add, rename, delete and reorder aisles.',
    'The shopping list stays on this device and doesn\'t sync. Settings can keep the screen awake while you shop.',
  ]),
  HelpSection('sharing', 'Sharing recipes', [
    'To share a recipe, open its menu and choose Share. You can send it as a message or a .txt file, copy the text, or save a .txt file. To share several at once, long-press a recipe, choose Select, pick the others, then choose Share.',
    'Shared recipes are plain text anyone can read, even without cookdex. Your favorites and shopping list aren\'t included.',
    'To add a recipe someone sent you, open the .txt file with cookdex, or paste its text into Smart Import. No AI is needed. If the file has several recipes, you\'ll get a checklist, and recipes you already have start unchecked.',
    'On Android, you can also share text, links or photos from other apps straight into cookdex.',
  ]),
  HelpSection('sync', 'Syncing your devices', [
    'Sync keeps the same recipe book on all your own devices over your home Wi-Fi. There\'s no account, and nothing is stored in the cloud.',
    '1. On one device, open Settings > Sync > Add a device and choose Invite a device.',
    '2. On the other device, do the same but choose Join a device, then scan the QR code (Android) or paste the invitation. Each invitation works once and expires after ten minutes, so keep it private.',
    'To sync, both devices need cookdex open on the same Wi-Fi. On Android, keep it on screen. On Windows, it can be minimized.',
    'Only pair your own devices: edits and deletions reach every paired device. To give recipes to someone else, use Share instead.',
    'What the sync status means:',
    '• Synced: everything is up to date.',
    '• Not synced: changes are waiting. Open cookdex on both devices on the same Wi-Fi.',
    '• Sync conflict: a recipe changed differently on two devices. Tap the status to choose what to keep.',
    '• Update needed: one of your devices needs a newer version of cookdex.',
    '• Sync failure: open Sync settings to see what\'s wrong.',
    '• Sync off: sync is turned off, or no devices are paired.',
    'If pairing gets interrupted, try Sync now, or pair again with a fresh invitation.',
  ]),
  HelpSection('backups', 'Backups', [
    'Your recipes live only on your devices, so keep a backup somewhere safe, especially before you change phones.',
    '• Snapshots: while cookdex is open, it saves a copy once a day when something has changed, keeping about a week of daily copies and a month of weekly ones. Find them in Settings > Backup & restore > Snapshots. Restoring a snapshot adds missing recipes and never deletes any. Snapshots stay on this device, so they\'re lost if the app is removed.',
    '• Recipe ZIP: in Settings > Backup & restore, Download recipe ZIP saves a full backup you can keep anywhere, and Restore recipe ZIP brings it back. It includes your recipes and shopping categories, but not your Gemini key, paired devices or shopping list.',
    '• Readable cookbook: Save readable cookbook makes a copy you can read outside the app.',
    'Sync isn\'t a backup. If you delete a recipe on one device, it\'s deleted on all of them.',
    'If cookdex ever says some recipes can\'t be read, choose Review options on the Recipes screen, and try restoring a recent backup before discarding anything.',
  ]),
  HelpSection('appearance', 'Appearance and settings', [
    '• Theme: in Settings > Appearance, choose System, Light or Dark.',
    '• Wallpaper colors: on Android 12 or later, cookdex can match its colors to your wallpaper.',
    '• Screen awake: Cook mode keeps the screen on automatically, and Settings can do the same for the shopping list.',
    '• About: cookdex on GitHub has updates and the download page, and Share cookdex sends the download link to a friend on Android, or copies it on Windows.',
  ]),
  HelpSection('limits', 'Coming later', [
    '• Section headings for steps',
    '• Timers in Cook mode',
    '• Syncing in the background on Android. For now, keep cookdex on screen while it syncs.',
  ]),
  HelpSection(
    'feedback',
    'Problems and feedback',
    [
      'If something looks wrong, take a screenshot and write a short note about what you were doing and what you expected. Tap Copy app info below and paste it into your message; it shows your app version and device.',
      'Send it to the person who gave you cookdex, or report it on GitHub.',
      'Check the screenshot for anything private first, and never send your Gemini key or a pairing invitation.',
    ],
    links: [
      HelpLink(
        'Report a problem on GitHub',
        'https://github.com/cookdex/cookdex/issues',
      ),
    ],
  ),
];
