// Compose unchanged Flutter captures for the approved final design review.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '../../artifacts/library-tidy/final');
const names = fs.readFileSync(path.join(root, 'screens/manifest.txt'), 'utf8').trim().split(/\r?\n/);
const profiles = ['small-phone', 'normal-phone', 'largest-phone', 'tablet-landscape', 'windows-mouse'];
async function main() {
  for (const profile of profiles) {
    for (const theme of ['light', 'dark']) {
      const list = names.filter(n => n.startsWith(`${theme}-${profile}-`));
      const items = [];
      const wide = profile === 'tablet-landscape' || profile === 'windows-mouse';
      const width = wide ? 640 : 240, height = wide ? 440 : 530, columns = wide ? 2 : 4;
      for (const [i, name] of list.entries()) {
        const left = (i % columns) * width, top = Math.floor(i / columns) * height;
        const label = name.replace(`${theme}-${profile}-`, '').replace('.png', '');
        const title = Buffer.from(`<svg width="${width}" height="26"><text x="6" y="19" font-family="sans-serif" font-size="13">${label}</text></svg>`);
        const input = await sharp(path.join(root, 'screens', name)).resize(width - 8, height - 32, {fit:'inside'}).png().toBuffer();
        items.push({input:title, left, top}, {input, left:left+4, top:top+28});
      }
      await sharp({create:{width:width*columns,height:height*Math.ceil(list.length/columns),channels:4,background:'#e7ebe5'}}).composite(items).png().toFile(path.join(root, `${theme}-${profile}-contact.png`));
    }
  }
  const sections = profiles.map(profile => `<h2>${profile}</h2><div class="grid">${names.filter(n=>n.includes(`-${profile}-`)).map(n=>`<figure><a href="screens/${n}"><img loading="lazy" src="screens/${n}"></a><figcaption>${n}</figcaption></figure>`).join('')}</div>`).join('');
  fs.writeFileSync(path.join(root,'gallery.html'), `<!doctype html><html lang="en"><meta charset="utf-8"><title>cookdex Library final review</title><style>body{font:16px system-ui;background:#f8f9f5;color:#17211b;margin:24px}h2{margin-top:48px}.grid{display:flex;flex-wrap:wrap;gap:16px}figure{margin:0;width:320px}img{max-width:100%}figcaption{font-size:12px;overflow-wrap:anywhere}</style><h1>Library final review · 1.8.5+18005</h1><p>86 real Flutter host renders, synthetic fixtures, both themes. Four standard sizes plus affected Windows layout and Recipes Cards/Compact × Favorites. Keyboard inset and additional duplicate states remain in the approved <a href="../checkpoint-4/gallery.html">checkpoint 4</a>.</p>${sections}</html>`);
  console.log(`${names.length} captures indexed; ten contact sheets written.`);
}
main().catch(error=>{console.error(error);process.exitCode=1;});
