// Assemble unchanged host captures into a local review gallery and contact sheets.
// Uses the host's sharp package; adds no application dependency.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const feedback = process.argv.includes('--feedback');
const tags = process.argv.includes('--tags');
const spelling = process.argv.includes('--spelling');
const root = path.resolve(__dirname, '../../artifacts/library-tidy/' + (spelling ? 'checkpoint-4' : tags ? 'checkpoint-3' : feedback ? 'checkpoint-2' : 'checkpoint'));
const states = spelling ? [
  ['ingredients-duplicates', 'Ingredients: similar spellings'], ['tags-duplicates', 'Tags: beef, Beef and Qeef'],
  ['possible-duplicates', 'Possible duplicates page'], ['keep-separate-undo', 'Keep separate and Undo'],
  ['kept-separate', 'Kept separate: Show again'], ['all-kept-library', 'All groups kept separate'],
  ['all-kept-page', 'Kept groups remain reachable'], ['library-search', 'Library search X'],
  ['merge-search', 'Merge picker search X'], ['recipes-search', 'Recipes search X and options'],
  ['picker-search-counts', 'Filtered eligible and locked counts'], ['new-tag-idle', 'New tag: keyboard stays down'],
  ['new-tag-keyboard', 'New tag with keyboard inset'], ['new-tag-keyboard-large', 'New tag: largest text'],
  ['add-tag-idle', 'Add tag: keyboard stays down'], ['add-tag-keyboard', 'Add tag with keyboard inset'],
  ['add-tag-keyboard-large', 'Add tag: largest text'], ['rename-keyboard', 'Rename with keyboard inset'],
  ['rename-keyboard-large', 'Rename: largest text'], ['section-keyboard', 'Section name with keyboard inset'],
  ['section-keyboard-large', 'Section name: largest text'], ['paste-ingredients-keyboard-large', 'Paste ingredients: largest text'],
  ['paste-steps-keyboard-large', 'Paste steps: largest text'], ['category-add-keyboard-large', 'New category: largest text'],
  ['category-rename-keyboard-large', 'Rename category: largest text'], ['shopping-edit-keyboard-large', 'Edit item: largest text'],
  ['device-name-keyboard-large', 'Device name: largest text'], ['import-key-keyboard-large', 'Import settings key: largest text'],
  ['import-model-keyboard-large', 'Import settings model: largest text'],
] : tags ? [
  ['full-width-details', 'Right pane at full width'], ['tags-new-button', 'Tags: New tag'],
  ['new-tag', 'New tag name'], ['new-tag-existing', 'Existing spelling match'],
  ['recipe-picker', 'Choose recipes'], ['picker-selected', 'Select all filtered matches'],
  ['picker-search-fields', 'Existing Search in options'], ['picker-locked', 'Already tagged: checked and locked'],
  ['add-confirmation', 'Add tag confirmation'], ['select-mode', 'Recipes: Add tag in select mode'],
  ['select-tag-suggestions', 'Existing tag suggestions'], ['select-tag-confirmation', 'Only recipes needing the tag'],
] : feedback ? [
  ['settings', 'Settings: Library'], ['many-duplicates', 'Six duplicate groups: preview'],
  ['all-duplicates', 'Show all six groups'], ['duplicate-choices', 'Choose spelling to keep'],
  ['duplicate-alternate', 'Different spelling selected'], ['rename-warning', 'Rename merge warning'],
  ['overlap-details', 'Same ingredient in two sections'], ['plural-merge', 'Eggs into Egg'],
  ['plural-rename', 'Egg into Eggs through Rename'], ['remove-tag', 'Remove tag reassurance'],
  ['undo', 'Ten-second Undo'], ['tablet-ingredients', 'Selected ingredient in both lists'],
  ['tablet-tags', 'Selected tag in both lists'], ['windows-pointer', 'Windows: clicked row and pointer'],
  ['windows-row-rename', 'Windows: Rename targets clicked row'],
] : [
  ['ingredients', 'Ingredients and duplicates'], ['tags', 'Tags and duplicates'],
  ['search', 'Search'], ['details', 'Ingredient details'], ['show-all', 'Show all recipes'],
  ['rename', 'Rename'], ['rename-merge-warning', 'Rename merge warning'],
  ['merge-picker', 'Merge picker'], ['merge-search', 'Picker search'],
  ['merge-confirmation', 'Merge confirmation'], ['undo', 'Undo message'],
  ['duplicates-confirmation', 'Duplicates confirmation'], ['tag-details', 'Tag details'],
  ['remove-tag', 'Remove tag'], ['no-matches', 'No matches'],
  ['empty-ingredients', 'Empty ingredients'], ['empty-tags', 'Empty tags'],
  ['tablet-ingredients', 'Tablet: ingredients'], ['tablet-tags', 'Tablet: tags'],
  ['row-actions', 'Mouse row actions'],
];
async function main() {
  for (const theme of ['light', 'dark']) {
    const items = [];
    for (let i = 0; i < states.length; i++) {
      const [state, label] = states[i];
      const left = (i % 5) * 224, top = Math.floor(i / 5) * 484;
      const text = Buffer.from(`<svg width="224" height="28"><rect width="224" height="28" fill="#e8ece5"/><text x="8" y="19" font-family="sans-serif" font-size="12" fill="#152018">${label}</text></svg>`);
      const image = await sharp(path.join(root, 'screens', `${theme}-${state}.png`)).resize(216, 448, { fit: 'inside' }).png().toBuffer();
      items.push({ input: text, left, top }, { input: image, left: left + 4, top: top + 28 });
    }
    await sharp({ create: { width: 1120, height: Math.ceil(states.length / 5) * 484, channels: 4, background: '#e8ece5' } }).composite(items).png().toFile(path.join(root, `${theme}-contact.png`));
  }
  const figures = (file, label) => `<figure><a href="${file}" target="_blank"><img loading="lazy" src="${file}" alt="${label}"></a><figcaption>${label} · click for full size</figcaption></figure>`;
  const sections = states.map(([state, label]) => `<section id="${state}"><h2>${label}</h2><div class="pair ${state === 'full-width-details' || state.startsWith('tablet') || state === 'row-actions' || state.startsWith('windows') ? 'wide' : ''}">${['light','dark'].map(theme => figures(`screens/${theme}-${state}.png`, `${label} — ${theme}`)).join('')}</div></section>`).join('');
  fs.writeFileSync(path.join(root,'gallery.html'), `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>cookdex Library and icon checkpoint</title><style>
  *{box-sizing:border-box}body{margin:0;background:#f7f8f3;color:#18231b;font:16px/1.5 system-ui,sans-serif}main{max-width:1320px;margin:auto;padding:24px}h1{font-size:28px}h2{font-size:20px;margin-top:40px}nav{display:flex;flex-wrap:wrap;gap:8px 20px}a{color:#345b3b}section{scroll-margin-top:16px}.pair{display:flex;gap:24px;flex-wrap:wrap}figure{margin:0;width:min(390px,100%)}img{width:100%;height:auto;display:block;border:1px solid #d3d9d0;border-radius:6px}figcaption{padding:6px 0;color:#4a594e;font-size:13px}.wide figure{width:100%}.note{max-width:820px}
  </style><main><h1>${spelling ? "Library spelling checks · fourth UI checkpoint" : tags ? "Library tag additions · third UI checkpoint" : "Library and adaptive icon · UI checkpoint"}</h1><p class="note">Real Flutter host renders using synthetic recipes. ${spelling ? "Phone: 390 × 844, light and dark. Keyboard-open states reserve a 300dp host keyboard inset; no native keyboard or device capture is shown. Largest text uses 200% system scaling. The additional dialog captures document the requested field-label audit." : tags ? "Phone: 390 × 844; full-width pane: 1600 × 900. Search in uses the existing fields, including Tags by default; no separate tag filter was added." : "Phone: 390 × 844; tablet: 1280 × 800; Windows: 1600 × 900. For Windows, the capture overlay marks the exact tested pointer coordinate; Flutter host captures omit the OS cursor. Icon and splash images are host resource previews."} Source/dev remains 1.8.4+18004. Awaiting owner UI approval; full verification and independent reviews come afterward.</p><nav>${states.map(([id,label])=>`<a href="#${id}">${label}</a>`).join('')}${tags || spelling ? '' : '<a href="#icons">Android icon</a><a href="#splash">Android splash</a>'}</nav>${sections}${tags || spelling ? '' : `<section id="icons"><h2>Android masks and production themed icon</h2><p class="note">The pan is 12% smaller and nudged left 2.5dp from the first checkpoint, with its optical balance retained. Development provides fixed-color layers and no monochrome layer. Newer launchers can still generate themed icons themselves.</p><div class="pair">${['light','dark'].map(theme=>figures(`icons/adaptive-icon/masks-${theme}.png`,`${theme} icon previews`)).join('')}</div></section><section id="splash"><h2>Android splash</h2><p class="note">Android 12+ uses the app light palette in system light mode. Dark and pre-Android 12 artwork stay unchanged.</p><div class="pair">${['light','dark'].map(theme=>figures(`icons/adaptive-icon/splash-${theme}.png`,`${theme} splash resource preview`)).join('')}</div></section>`}</main></html>`);
  console.log(`Gallery and two ${states.length}-state contact sheets written.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
