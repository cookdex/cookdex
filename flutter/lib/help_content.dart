/// All reader-facing help copy lives here. Update this when typical users need new guidance.
/// Google setup/data-use sources verified 2026-11-12.
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
    this.groups = const [],
    this.links = const [],
  });
  final String id;
  final String title;
  final List<String> paragraphs;
  final List<HelpGroup> groups;
  final List<HelpLink> links;
}

class HelpGroup {
  const HelpGroup(this.title, this.paragraphs, {this.links = const []});
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
const dataHelpTitle = 'What’s kept and what’s sent';
const googleDataTerms = HelpLink(
  'Google’s Gemini API terms',
  'https://ai.google.dev/gemini-api/terms',
);
const dataHelp = HelpSection(
  'data',
  dataHelpTitle,
  [
    'cookdex collects no data for itself. There’s no account, advertising, analytics or tracking, and reading and cooking stay on your device. Here’s when cookdex uses a connection or makes a copy.',
    '• Smart Import with AI, Smart Create and Test key contact Google’s Gemini. cookdex reads its own recipe files locally.',
    '• Importing from a website or YouTube downloads the page from that site.',
    '• Sync sends recipe changes to your paired devices over an encrypted local connection.',
    '• Checking for updates asks GitHub for the latest version.',
    '• On Android 9 or later, backup can keep an encrypted copy in your Google account if backup is on and you have a screen lock.',
  ],
  groups: [
    HelpGroup('On your device', [
      'Your library holds your recipes, with their ingredients, tags, notes, sources and favorites. It also keeps your shopping list, aisles and the aisle you chose for each ingredient. Recipe history, conflicts, the previous save and snapshots help recover changes.',
      'cookdex also remembers your latest search, filters, sort order, reading places, appearance settings, spellings kept separate, Smart feature choices and update-check history. Pairing saves device names, IDs, local addresses, pairing keys and sync status.',
      'Editor drafts and Smart Import drafts started in cookdex can survive a restart, including pasted text, links and prepared photos. Android keeps full-size import photos temporarily. On Android 10 or later, Save photos to device puts copies in Pictures/cookdex when you save the recipe. Smart Create ideas and kitchen photos are kept for the current session.',
      'Last Smart Import and Last Smart Create keep a record of the latest recorded AI work for each feature: the time, model, instructions, replies and checks. A reply can repeat your recipe or ingredients. The next recorded request for that feature replaces its record.',
      'Your library and drafts are ordinary files in cookdex’s storage. Android Keystore protects the saved Gemini key on Android, and Credential Manager on Windows. cookdex sends the key only to Google, over an encrypted connection.',
    ]),
    HelpGroup('What Smart Import sends', [
      '• Text: cookdex reads its own recipe files itself. Other text you paste or open goes to Gemini if you have a key. Without one, cookdex reads it on your device. Choosing Try Smart Import on a part cookdex couldn’t read sends just that part.',
      '• Websites: your device downloads the page, so the site sees the page address and your internet address. With Use AI for this link off, cookdex reads the built-in recipe details itself. With it on, Gemini gets the final page address, the built-in recipe details and the page’s readable text, which can include writing outside the recipe.',
      '• Blocked websites: if a public recipe site blocks your device and Use AI for this link is on, cookdex sends the link to Google so Gemini can try opening the page itself.',
      '• Photos: Gemini gets copies of the photos you choose, resized as needed and saved as fresh JPEGs without location or camera details. Anything visible in a photo is still visible to Google.',
      '• YouTube: your device opens the video page. Gemini gets the title and whole description to look for a written recipe or a recipe link, plus the video address for a written recipe. For a linked recipe, cookdex downloads that page and sends its contents, its final address and the video title. To watch a confirmed public video, Gemini gets the video link, title, whole description and any confirmed ingredient lines. If cookdex can’t confirm the video is public and you choose Watch anyway, Gemini gets only the video link and watching instructions.',
      'When Gemini reads a written or photographed recipe, it also gets cookdex’s instructions and suggested tags, including your library’s tag names. Your saved recipes and shopping list are never attached.',
    ]),
    HelpGroup('What Smart Create sends', [
      '• Checking kitchen photos sends the prepared photos, the ingredients you typed and your staples.',
      '• Asking for ideas sends your confirmed ingredients, foods to use first, staples, foods to avoid, other preferences, mood, meal, effort, servings and, when you start with ingredients or photos, your item limit, plus earlier idea titles to avoid repeats.',
      '• Getting a recipe sends the chosen idea with its ingredients, servings, mood, foods to avoid, other preferences and your library’s tag names.',
      '• Each request also includes cookdex’s instructions and your model choices.',
      'Test key asks Gemini to reply “OK” using your Smart Import model. It sends no recipes, photos, drafts or tags. Saving or removing the key happens only on your device.',
    ]),
    HelpGroup(
      'How Google uses what you send',
      [
        'cookdex asks Google not to store each request, but Google’s terms still apply.',
        '• Free tier: Google may use what you send and its replies to improve its products, and people may review them. Leave out anything personal or confidential.',
        '• Paid projects: Google says it doesn’t use your requests or its replies to improve its products. It may keep them temporarily for safety or legal purposes.',
        '• In the European Economic Area, Switzerland and the United Kingdom, the paid data-use terms apply even on the free tier.',
      ],
      links: [googleDataTerms],
    ),
    HelpGroup('Other connections and copies', [
      '• Sync exchanges recipe changes, favorites and deletions with your paired devices over an encrypted local connection. Finding devices uses device IDs on your network.',
      '• Check for updates asks GitHub for the latest release. GitHub sees your internet address and an update request. The version comparison happens on your device. Opening a source, help or download link takes you to that site in your browser or its associated app.',
      '• Share hands the recipe text or file, including notes and source, to the app you choose. Sharing a file makes a temporary local copy.',
      '• Save list as text exports shopping items, checkmarks, amounts and recipe names. Copy AI prompt copies only the instructions and suggested tags, and makes no AI request.',
      '• Snapshots and recipe ZIPs contain your recipes, favorites and aisle setup, without your Gemini key, pairings, drafts or shopping list. A readable cookbook is a text file. Anyone with these files can read them.',
      '• Android backup and direct phone transfer can copy your recipes, shopping list, aisles and everyday settings. They leave out your Gemini key, pairings, drafts, snapshots, Last Smart Import, Last Smart Create and import photos.',
    ]),
    HelpGroup('Removing your data', [
      '• Choose Clear draft in Smart Import, or Discard in the editor.',
      '• In Smart Import settings, open Last Smart Import and choose Clear record. Smart Create settings has the same for Last Smart Create.',
      '• In Sync settings, Forget device removes a pairing.',
      '• In Gemini key settings, Remove key deletes the saved key from this device.',
      'Deleting a recipe can leave earlier copies in history, snapshots, exports and backups. On Android, clear cookdex’s storage in Android Settings or uninstall it to remove its private data from that phone.',
      'On Windows, deleting the program folder leaves your library, settings and saved key behind. Close cookdex. In %LOCALAPPDATA%, open com.sylph.cookdex (com.sylph.cookdex.dev for cookdex dev) and delete its flutter-v1 folder. In Credential Manager > Windows Credentials, remove the matching entry ending in /flutter-v1/gemini.',
      'Windows keeps temporary shared recipe files in the cookdex-production-export folder under %TEMP% (cookdex-dev-export for cookdex dev). Delete these, exported files and saved photos separately. Copies you shared with other people or apps can still be there.',
    ]),
  ],
);

const helpSections = <HelpSection>[
  HelpSection('start', 'Getting started', [
    'cookdex keeps your recipe book on your own devices. There’s no account, and reading, cooking and editing work offline.',
    '1. Add your first recipe with Write a recipe, Smart Import or Smart Create. Smart Import can read a website, a YouTube video or text, and on Android it can also read recipe photos. Smart Create suggests dishes from what you have.',
    '2. For AI help reading recipes and suggesting dishes, add a Gemini key. See Your Gemini key.',
    '3. To keep the same recipe book on your other devices, pair them. See Syncing your devices.',
    'cookdex collects no data for itself, and there are no ads, analytics or tracking. Nothing leaves your device unless you use a feature that needs it, like Smart Import or sync, or have Android backup turned on. See What’s kept and what’s sent.',
  ]),
  HelpSection('adding', 'Adding and editing recipes', [
    'To edit a recipe, open it, tap the three-dot menu (⋮) and choose Edit. In wider Android layouts and on Windows, you can also tap the pencil.',
    'Long-press a recipe in your list for quick actions: Edit, Share, Add to list and Favorite. To delete several recipes, long-press one, choose Select, pick the others, then choose Delete. cookdex saves a snapshot first, in case you want them back.',
    'While editing:',
    '• Paste ingredients reads one ingredient per line and separates amounts, units, names and prep notes. Paste steps recognizes numbered or bulleted steps, paragraphs and plain lines. Choose Review, check the rows, then Apply to add them to your recipe.',
    '• Amounts can be whole numbers, fractions, decimals or ranges like 6–7. Mixed numbers like 1½, 1 1/2 and 1 and 1/2 all work. Tap to taste above the keyboard when there’s no exact amount.',
    '• For cans and jars, put the size in the unit, like 1 (16 oz) jar salsa. The size then shows everywhere, including your shopping list, and stays the same when you scale.',
    '• Makes can be servings or a yield, like 4 servings or 12 tortillas.',
    '• Group ingredients under headings like Sauce or Topping. Tap + Section, name it, then choose Add at end, or Choose spot to tap where the new section starts.',
    '• Hold a section’s drag handle to move the whole group. Hold an ingredient’s handle to move it into or out of a section.',
    '• In a section’s menu, Remove section moves its ingredients into the group above when there is one. Delete section deletes the heading and its ingredients.',
    '• Start a step with a short label and a colon, like “Make the sauce:”, and the label shows in bold when you read or cook.',
    '• Use Source to credit where a recipe came from, like a person, a cookbook or a website. A full web address starting with http or https opens when you tap it.',
    '• As you type, cookdex suggests ingredient names and tags you’ve used before. When you save, it may offer to match a new spelling to one you already use. Uncheck anything you want to keep as typed.',
  ]),
  HelpSection(
    'import',
    'Smart Import',
    [
      'Smart Import turns a website, YouTube video or pasted text into a recipe you check before saving. On Android it can also read up to 8 recipe photos. Without a Gemini key, it can read cookdex recipe files and the recipe details many websites include. Photos, videos and AI help need a key. See Your Gemini key.',
      'On Android, you can also share a page, text or photos from another app straight to cookdex.',
      'Always check the recipe against the original before saving. “AI guess” and “AI-written” mark the parts the AI estimated, filled in or rewrote.',
      'When you start in Smart Import, your link, text and photos stay as a draft, even after a restart, until you save the imported recipe or choose Clear draft.',
    ],
    groups: [
      HelpGroup('Websites', [
        '• With Use AI for this link off, cookdex reads the recipe details built into the page. Turn it on for pages without them, or when the result looks incomplete.',
        '• If a public recipe site blocks cookdex and Use AI for this link is on, Gemini tries opening the page itself. If the link still won’t import, choose Paste text for a copied recipe. On Android, you can also choose Use photos for screenshots.',
      ]),
      HelpGroup('YouTube', [
        '• For a public YouTube video or Short, Gemini checks the title and whole description first. It can use a written recipe there or a recipe page linked in the description.',
        '• If those don’t give a full recipe, Gemini can watch videos up to 15 minutes long using a Google feature still in preview. If cookdex can’t confirm the length or whether the video is public, it offers Watch anyway. Check amounts marked AI guess.',
        '• For a longer video with enough written ingredients, Gemini can fill in missing directions, marked AI-written. Fill in missing amounts before saving.',
        '• To change the model that watches videos, open Smart Import settings > Advanced.',
      ]),
      HelpGroup('Photos', [
        '• Include every page of the recipe. Hold a thumbnail and drag it to put the pages in order.',
        '• On Android 10 or later, Save photos to device keeps copies in Pictures/cookdex when you save the recipe. A recipe named Grandma’s chili gives you Grandma’s chili - card 1.jpg, then Grandma’s chili - card 2.jpg for a second photo. To keep the full-size originals, save the recipe before restarting cookdex.',
      ]),
      HelpGroup('Text', [
        '• cookdex reads its own recipe files on your device. For other text, Gemini reads it if you have a key. Without one, cookdex tries to read it locally, which works best with neatly laid-out recipes.',
        '• To use another AI app instead, choose Copy AI prompt, give that app the prompt and your recipe, then paste its answer into Text.',
      ]),
      HelpGroup('Social apps', [
        'cookdex can’t import from TikTok, Instagram, Threads, Facebook, X, Reddit or Pinterest. Paste the recipe text or, on Android, use screenshots. In Pinterest, tap Visit to open the recipe site, then share that page to cookdex.',
      ]),
    ],
  ),
  HelpSection(
    'create',
    'Smart Create',
    [
      'Smart Create suggests dishes from what you have, what you’re in the mood for, or both. It needs a Gemini key.',
      '1. On What you have, list ingredients, add kitchen photos, or say what you’re in the mood for. Options sets the meal, effort and servings.',
      '2. With ingredients or photos, Check lets you review ingredients and staples, tap foods to use up first, and include uncertain finds. A mood on its own goes straight to ideas.',
      '3. Get ideas shows what you can make now and what needs a few more ingredients.',
      '4. Get the recipe writes the full recipe. Check the amounts and times before saving. A note flags ingredient or amount changes cookdex finds when it compares the recipe with the idea.',
      '• Calories on an idea are a rough estimate per serving. The calories and any suggested labels, like High protein, aren’t saved with the recipe.',
      '• To aim for a calorie range, high protein or meal prep, say so in your mood or in Other preferences.',
      '• New ideas avoids repeating earlier titles. You can keep browsing ideas while a recipe is on its way.',
      '• You can leave Smart Create and come back to your ideas during the same session. Changing your inputs or asking for new ideas can replace them.',
    ],
    groups: [
      HelpGroup('Smart Create settings', [
        '• Foods to avoid blocks ideas and recipes when cookdex recognizes a food you listed. For allergies, check the ingredients yourself. For example, pesto may contain nuts even if the recipe never mentions them.',
        '• Use Other preferences for guidance, like “no egg-heavy dishes”. Gemini tries to follow it, but cookdex doesn’t check the result against it.',
        '• Staples are things you always keep, like salt and oil. They don’t count toward Items to buy per idea, which limits how many extra items an idea can need when you start with ingredients or photos.',
        '• You can choose a model for each step. In a step’s settings, Reset to recommended, then Save, restores its model and thinking level. If a model needs billing, Use Flash switches that step to the recommended choice and retries it.',
      ]),
    ],
  ),
  HelpSection(
    'smart',
    'Your Gemini key',
    [
      'Smart Import’s AI help and Smart Create use your own Gemini API key from Google. A key is like a password that lets cookdex ask Google for help, so keep it private. Google requires users to be at least 18 and limits AI Studio and the API to professional or business development. Google requires paid services when an app using the API is offered in the European Economic Area, Switzerland or the UK.',
      '1. Open Google AI Studio with the button below and sign in with your Google account.',
      '2. Open API Keys and create a key, or copy the one that’s already there.',
      '3. In cookdex, open Settings > Smart features > Gemini key, paste the key and choose Save. Test key checks that it works.',
      'The free tier has usage limits. If you reach one, try again later. Google’s unpaid data-use terms allow it to use requests and replies to improve products, including through human review. See What’s kept and what’s sent for regional differences.',
      'Add the key on each device where you want AI help. It’s never included in backups, exports or sync.',
      'In Smart Import settings > Advanced, choose Standard or Thorough, use the usual Smart Import model or enter a custom model ID. For YouTube watching, choose Gemini 3.8 Flash, Follow Smart Import or Gemini 3.5 Flash-Lite. Thorough can take longer and use more of your quota. Reset to recommended, then Save, restores the defaults. Android backup and phone transfer can restore these choices. Recipe ZIPs and sync don’t include them.',
    ],
    links: [
      HelpLink('Open Google AI Studio', 'https://aistudio.google.com/apikey'),
      HelpLink(
        'Google’s key setup guide',
        'https://ai.google.dev/gemini-api/docs/api-key',
      ),
    ],
  ),
  HelpSection('finding', 'Finding recipes', [
    '• With several words, search shows recipes matching the most words first. It also handles accents, plurals, punctuation, common ingredient names and small typos.',
    '• Search in lets you choose which parts of a recipe to search. Reset restores the usual fields and keeps your search words and filters.',
    '• The view button switches between Cards and Compact.',
    '• Tap Recipes or the cookdex heading to jump to the top of your list. While you’re reading a recipe, the first tap on Recipes returns to the list where you were, and the second goes to the top.',
    '• cookdex remembers your place in the last two recipes you opened.',
  ]),
  HelpSection('cooking', 'Reading and cooking', [
    'To make more or less, tap the 1× circle beside Ingredients and choose from 0.5× to 5× in half steps. Cook mode and Add to shopping list use the new amounts. Steps, times and temperatures stay as written, so adjust those yourself. Reopening the recipe sets it back to 1×.',
    'In Cook mode, tap each ingredient as you use it. On Android, the screen stays awake while you cook.',
    '• Tap a step to jump to it. If you scroll away, tap the step counter in the middle to bring the current step back into view.',
    '• Tap Cooking at the top to return to where you were reading. Reopen Cook to pick up at your step.',
    '• Your step and ingredient checks are remembered until you restart the app.',
  ]),
  HelpSection('shopping', 'Shopping list', [
    'In a recipe, choose Add to shopping list under its ingredients, or Add to list in its menu, then pick what you need.',
    '• cookdex combines amounts for the same ingredient when it can. Different package sizes and amounts like “to taste” stay on separate lines.',
    '• Common ingredients find their aisle automatically. Anything else goes to Other until you move it, and cookdex remembers where you put it.',
    '• After a pause, checked items move into Checked. Tap one there to put it back.',
    '• Long-press an item, or right-click it on Windows, to see its source recipes, edit it, move it to another category or delete it.',
    '• Hold the handle on an unchecked item and drag it to another spot or aisle. To reorder, add, rename or delete aisles, open the shopping list menu and choose Categories.',
    'Each device keeps its own shopping list. On Android, turn on Keep shopping screen awake in Settings to keep the list in view.',
  ]),
  HelpSection('sharing', 'Sharing recipes', [
    'When you share a recipe from its menu:',
    '• Use Recipe file to send a cookdex recipe that someone can import.',
    '• Plain text is for a message, or anywhere you want to paste the whole recipe.',
    'To share several at once, long-press a recipe, choose Select, pick the others, then choose Share.',
    'Shared recipes are plain text anyone can read, even without cookdex. Favorites and your shopping list aren’t included. Someone on an older version of cookdex won’t see a Source that isn’t a web address.',
    'To add a recipe someone sent you, choose Open .txt file on Smart Import’s Text tab, or paste the recipe there. No AI is needed. If the file has several recipes, you’ll get a checklist, and recipes you already have start unchecked.',
  ]),
  HelpSection('sync', 'Syncing your devices', [
    'Sync keeps the same recipe book on your own devices, directly over your home Wi-Fi, without an account or a cloud service.',
    '1. On one device, open Settings > Sync settings > Add a device and choose Invite a device.',
    '2. On the other device, do the same but choose Join a device, then scan the QR code (Android) or paste the invitation. Each invitation works once and expires after ten minutes, so keep it private.',
    'To sync, both devices need cookdex open on the same Wi-Fi. On Android, keep it on screen. On Windows, it can be minimized.',
    'Sync shares recipes, favorites and deletions. Each device keeps its own shopping list, drafts, AI settings and Gemini key.',
    'Only pair your own devices: edits and deletions reach every paired device. To give recipes to someone else, use Share.',
    'What the sync status means:',
    '• Not synced: changes are waiting. Open cookdex on both devices on the same Wi-Fi.',
    '• Sync conflict: a recipe changed differently on two devices. Tap the status to choose what to keep.',
    '• Update needed: one of your devices needs a newer cookdex. Update all of them; they stay paired.',
    '• Sync failure: open Sync settings to see what’s wrong.',
    '• Sync off: sync is turned off, or no devices are paired.',
    'If the status says Pairing unfinished, try Sync now, or pair again with a fresh invitation. To unpair a device, use Forget device in Sync settings.',
  ]),
  HelpSection('backups', 'Backups and moving phones', [
    'A recipe ZIP kept somewhere safe, like your computer or cloud storage, is your surest backup.',
    '• Recipe ZIP: in Settings > Backup & restore, Download recipe ZIP saves your recipes, favorites and aisles, and Restore recipe ZIP brings them back. Your Gemini key, pairings and shopping list aren’t included.',
    '• Snapshots: while cookdex is open, it saves a copy once a day when something has changed, keeping about a week of daily copies and a month of weekly ones. Find them in Settings > Backup & restore > Snapshots. Restoring a snapshot adds missing recipes and can update a recipe if the copy in the snapshot is newer. It never deletes a recipe. Snapshots stay with this device’s cookdex data.',
    '• Readable cookbook: Save readable cookbook makes a copy you can read outside cookdex.',
    '• Android backup: on Android 9 or later, with backup on and a screen lock set, your Google account can keep an encrypted copy of your recipes, shopping list, aisles and everyday settings. Your Gemini key, pairings, drafts and snapshots are left out.',
    'Moving to a new phone:',
    '1. On your old phone, download a recipe ZIP and keep it somewhere you can reach.',
    '2. After Android setup, install cookdex from GitHub. Android’s standard transfer skips apps installed outside Google Play.',
    '3. Open cookdex and check your library. If it’s empty, choose Restore a backup and select your recipe ZIP, or pair with a device that has your recipes. Neither fallback brings over your active shopping list.',
    '4. If you use Gemini, add your key on the new phone. Pair it with any remaining devices you want to sync.',
    'Sync isn’t a backup. If you delete a recipe on one device, it’s deleted on all of them.',
    'If cookdex ever says some recipes can’t be read, choose Review options on the Recipes screen, and try restoring a recent backup before discarding anything.',
  ]),
  HelpSection('library', 'Ingredients and tags', [
    'Open Settings > Library to see your ingredients and tags and which recipes use them.',
    '• Rename an ingredient or tag, or merge it into another spelling. Recipe amounts and other details stay as written. Remove tag removes the tag, not the recipes.',
    '• Possible duplicates lists similar spellings to review. Choose which spelling to keep before merging, or choose Keep separate. Kept separate > Show again brings a group back on this device.',
    '• On the Tags tab, New tag asks for a name and the recipes to add it to. Open an existing tag and choose Add to recipes to use it on more. You can also select recipes in your list and choose Add tag.',
    '• In the recipe picker, search and Favorites narrow the list. Select all selects every matching recipe that still needs the tag, including ones off screen. Recipes that already have it stay checked and locked.',
    '• Renaming, merging and adding or removing tags offer Undo for the whole change. cookdex saves a snapshot first.',
  ]),
  HelpSection('appearance', 'Appearance and settings', [
    '• Wallpaper colors: on Android 12 or later, cookdex can match its colors to your wallpaper.',
    '• In Settings > Appearance > Recipe text size, choose Default, Large or Extra large for reading recipes and cooking.',
    '• Updates: in Settings > About, check for updates or turn on daily checks, then open the release page to download a new version. cookdex never installs updates by itself.',
    '• Share cookdex opens the Android share sheet with the download link, or copies it on Windows.',
  ]),
  dataHelp,
  HelpSection('limits', 'Coming later', [
    '• Nutrition info',
    '• Section headings for steps',
    '• Timers in Cook mode',
    '• Syncing in the background on Android. For now, keep cookdex on screen while it syncs.',
  ]),
  HelpSection(
    'feedback',
    'Problems and feedback',
    [
      'If something looks wrong, take a screenshot and write a short note about what you were doing and what you expected. Tap Copy app info below and paste it into your message; it shows your app version and device.',
      'Send it to the person who gave you cookdex, or report it on GitHub. Check the screenshot for anything private first, and never send your Gemini key or a pairing invitation.',
    ],
    links: [
      HelpLink(
        'Report a problem on GitHub',
        'https://github.com/cookdex/cookdex/issues',
      ),
    ],
  ),
];
