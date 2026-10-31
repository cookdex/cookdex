// Host-only renderer/checker for the actual Android vector resources.
// Requires the host's sharp package; no application dependency is added.
// Run from any directory: node flutter/tool/preview_android_icons.cjs
// Add --write-assets when regenerating the legacy PNGs and light splash.
// --write-fallbacks remains an alias for existing authoring commands.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const sharp = require('sharp');

const root = path.resolve(__dirname, '../..');
const res = path.join(root, 'flutter/android/app/src/main/res');
const output = path.join(root, 'artifacts/adaptive-icon');
const read = (name) => fs.readFileSync(path.join(res, name), 'utf8');
const attribute = (xml, name) => {
  const match = xml.match(new RegExp(`android:${name}="([^"]+)"`));
  assert(match, `Missing ${name}`);
  return match[1];
};

function vector(name) {
  const xml = read(`drawable/${name}.xml`);
  assert.equal(attribute(xml, 'width'), '108dp');
  assert.equal(attribute(xml, 'height'), '108dp');
  assert.equal(attribute(xml, 'viewportWidth'), '108');
  assert.equal(attribute(xml, 'viewportHeight'), '108');
  assert.equal((xml.match(/<path /g) || []).length, 1);
  return {
    path: attribute(xml, 'pathData'),
    fill: attribute(xml, 'fillColor'),
    sx: Number(attribute(xml, 'scaleX')),
    sy: Number(attribute(xml, 'scaleY')),
    tx: Number(attribute(xml, 'translateX')),
    ty: Number(attribute(xml, 'translateY')),
  };
}
const foreground = vector('cookdex_icon_foreground');
const monochrome = vector('cookdex_icon_monochrome');
assert.deepEqual({ ...foreground, fill: '' }, { ...monochrome, fill: '' });
assert.equal(monochrome.fill, '#FFFFFF');
const colors = read('values/colors.xml');
const color = (name, source = colors) => {
  const match = source.match(new RegExp(`<color name="${name}">(#[a-fA-F0-9]{6})</color>`));
  assert(match, `Missing color ${name}`);
  return match[1];
};
const production = color('cookdex_icon_background');
const dev = color('cookdex_icon_background_dev');
assert.notEqual(production, dev);
const lightScheme = fs.readFileSync(path.join(root, 'flutter/lib/ui/theme.dart'), 'utf8')
  .split('const cookdexLightColors =')[1].split(');')[0];
const lightColor = (name) => {
  const match = lightScheme.match(new RegExp(`\\b${name}: Color\\(0xff([a-fA-F0-9]{6})\\)`));
  assert(match, `Missing app light color ${name}`);
  return '#' + match[1].toUpperCase();
};
const lightSplashBackground = color('cookdex_launch_background', read('values-notnight-v31/colors.xml'));
assert.equal(lightSplashBackground, lightColor('surface'));
const mark = (v, fill = v.fill) => `<g transform="translate(${v.tx} ${v.ty}) scale(${v.sx} ${v.sy})"><path fill="${fill}" d="${v.path}"/></g>`;
const svg = (content, width, height = width, viewBox = `0 0 ${width} ${height}`) =>
  Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="${viewBox}">${content}</svg>`);
const mask = (shape) => shape === 'circle'
  ? '<circle cx="54" cy="54" r="36"/>'
  : `<rect x="18" y="18" width="72" height="72" rx="${shape === 'square' ? 0 : 16}"/>`;
const icon = (shape, background, fill = foreground.fill, id = 'icon', artwork = foreground) =>
  `<defs><clipPath id="${id}">${mask(shape)}</clipPath></defs><g clip-path="url(#${id})"><rect width="108" height="108" fill="${background}"/>${mark(artwork, fill)}</g>`;

async function main() {
  fs.mkdirSync(output, { recursive: true });
  // The whole alpha silhouette, not only its bounding box, must be protected.
  const measure = async (artwork) => {
    const raw = await sharp(svg(mark(artwork), 1080, 1080, '0 0 108 108'))
      .ensureAlpha().raw().toBuffer();
    let painted = 0;
    let radius = 0;
    for (let y = 0; y < 1080; y++) for (let x = 0; x < 1080; x++) {
      if (raw[(y * 1080 + x) * 4 + 3] > 0) {
        painted++;
        radius = Math.max(radius, Math.hypot((x + 0.5) / 10 - 54, (y + 0.5) / 10 - 54));
      }
    }
    assert(painted > 20000, 'Pan must be visible');
    assert(radius < 33, `Artwork exceeds 66dp safe circle: ${radius}`);
    return { painted, radius };
  };
  const { painted, radius } = await measure(foreground);
  // Resource selection: all normal/round IDs resolve at both API boundaries.
  for (const api of [26, 33]) for (const variant of ['ic_launcher', 'ic_launcher_production']) {
    const xml = read(`mipmap-anydpi-v${api}/${variant}.xml`);
    const background = variant === 'ic_launcher' ? 'cookdex_icon_background_dev' : 'cookdex_icon_background';
    assert(xml.includes(`<background android:drawable="@color/${background}" />`));
    assert(xml.includes('<foreground android:drawable="@drawable/cookdex_icon_foreground" />'));
    const themed = api === 33 && variant === 'ic_launcher_production';
    assert.equal(xml.includes('<monochrome '), themed);
    if (themed) {
      assert(xml.includes('<monochrome android:drawable="@drawable/cookdex_icon_monochrome" />'));
    }
    assert.equal(read(`mipmap-anydpi-v${api}/${variant}_round.xml`), xml);
  }
  const manifest = fs.readFileSync(path.join(root, 'flutter/android/app/src/main/AndroidManifest.xml'), 'utf8');
  assert(manifest.includes('android:icon="${appIcon}"'));
  assert(manifest.includes('android:roundIcon="${appRoundIcon}"'));
  const gradle = fs.readFileSync(path.join(root, 'flutter/android/app/build.gradle.kts'), 'utf8');
  assert(gradle.includes('manifestPlaceholders["appRoundIcon"] = if (production) "@mipmap/ic_launcher_production_round" else "@mipmap/ic_launcher_round"'));
  for (const mode of ['values-v31', 'values-night-v31']) {
    const styles = read(`${mode}/styles.xml`);
    assert(styles.includes('<item name="android:windowSplashScreenAnimatedIcon">@drawable/cookdex_splash</item>'));
    assert(styles.includes('<item name="android:windowSplashScreenBackground">@color/cookdex_launch_background</item>'));
  }
  const dayStyles = read('values-v31/styles.xml');
  assert(dayStyles.includes('parent="@android:style/Theme.Light.NoTitleBar"'));
  for (const flag of ['windowLightStatusBar', 'windowLightNavigationBar']) {
    assert(dayStyles.includes(`<item name="android:${flag}">true</item>`));
  }
  assert(read('values-night-v31/styles.xml').includes('parent="@android:style/Theme.Black.NoTitleBar"'));
  const writeAssets = process.argv.includes('--write-assets') || process.argv.includes('--write-fallbacks');
  for (const [density, size] of Object.entries({ mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 })) {
    for (const [variant, background] of [['ic_launcher', dev], ['ic_launcher_production', production]]) {
      for (const round of [false, true]) {
        const file = path.join(res, `mipmap-${density}/${variant}${round ? '_round' : ''}.png`);
        const expected = await sharp(svg(icon(round ? 'circle' : 'rounded-square', background), size, size, '18 18 72 72')).png().toBuffer();
        if (writeAssets) fs.writeFileSync(file, expected);
        const actual = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
        const expectedRaw = await sharp(expected).ensureAlpha().raw().toBuffer();
        assert.equal(actual.info.width, size);
        assert.equal(actual.info.height, size);
        assert(actual.data.equals(expectedRaw), `Legacy pixels mismatch: ${path.basename(file)} ${density}`);
      }
    }
  }
  await sharp(svg(mark(foreground), 864, 864, '0 0 108 108')).png().toFile(path.join(output, 'foreground.png'));
  await sharp(svg(mark(monochrome), 864, 864, '0 0 108 108')).png().toFile(path.join(output, 'monochrome.png'));
  const splashPath = path.join(res, 'drawable-xxxhdpi/cookdex_splash.png');
  const splashPixels = await sharp(splashPath).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  assert.equal(splashPixels.info.width, 1152);
  assert.equal(splashPixels.info.height, 1152);
  // Preserve the dark sprite's exact shape/layout, recoloring its separate pan
  // and wordmark bands with the actual Flutter light palette. No resampling.
  const lightSplashPath = path.join(res, 'drawable-notnight-xxxhdpi-v31/cookdex_splash.png');
  const lightPixels = Buffer.from(splashPixels.data);
  const rgb = (hex) => [1, 3, 5].map((start) => parseInt(hex.slice(start, start + 2), 16));
  const panRGB = rgb(lightColor('primary'));
  const wordmarkRGB = rgb(lightColor('onSurface'));
  for (let y = 0; y < 1152; y++) for (let x = 0; x < 1152; x++) {
    const i = (y * 1152 + x) * 4;
    assert(y !== 640 || lightPixels[i + 3] === 0, 'Splash bands must be separated');
    const fill = lightPixels[i + 3] === 0 ? [0, 0, 0] : (y < 640 ? panRGB : wordmarkRGB);
    for (let channel = 0; channel < 3; channel++) lightPixels[i + channel] = fill[channel];
  }
  if (writeAssets) {
    fs.mkdirSync(path.dirname(lightSplashPath), { recursive: true });
    await sharp(lightPixels, { raw: { width: 1152, height: 1152, channels: 4 } }).png().toFile(lightSplashPath);
  }
  const actualLight = await sharp(lightSplashPath).ensureAlpha().raw().toBuffer();
  assert(actualLight.equals(lightPixels), 'Light splash must preserve alpha and use the app light palette');
  let splashRadius = 0;
  for (let y = 0; y < 1152; y++) for (let x = 0; x < 1152; x++) {
    if (splashPixels.data[(y * 1152 + x) * 4 + 3] > 0) {
      splashRadius = Math.max(splashRadius, Math.hypot((x + 0.5) / 4 - 144, (y + 0.5) / 4 - 144));
    }
  }
  assert(splashRadius < 96, 'Splash must remain inside the 192dp safe circle');
  for (const dark of [false, true]) {
    const surface = dark ? '#242B27' : '#FAFAF4';
    const ink = dark ? '#E1E4DC' : '#191D17';
    const muted = dark ? '#BAC5B5' : '#53634D';
    const themedBackground = dark ? '#324B2B' : '#D2E8C6';
    const themedForeground = dark ? '#C2DDB4' : '#344E2C';
    const text = (x, y, value, size = 14, fill = ink) => `<text x="${x}" y="${y}" font-family="sans-serif" font-size="${size}" fill="${fill}">${value}</text>`;
    let content = `<rect width="390" height="844" fill="${surface}"/>`;
    content += text(24, 42, 'cookdex · Android icons', 23);
    content += text(24, 67, 'Host renders from the Android vector layers', 13, muted);
    ['Circle', 'Rounded square', 'Square'].forEach((title, i) => { content += text(24 + i * 120, 106, title, 12, muted); });
    const rows = [
      ['Production', production, foreground.fill, foreground],
      ['Development', dev, foreground.fill, foreground],
      ['Themed · production', themedBackground, themedForeground, monochrome],
      ['Development · fixed color', dev, foreground.fill, foreground],
    ];
    rows.forEach(([title, background, fill, artwork], row) => {
      const y = 134 + row * 147;
      content += text(24, y, title, 16);
      ['circle', 'rounded-square', 'square'].forEach((shape, col) => {
        // 64dp final mask, 96dp layer canvas (Android's 108:72 ratio).
        content += `<g transform="translate(${8 + col * 120} ${y + 5}) scale(${64 / 72})">${icon(shape, background, fill, `mask${row}${col}`, artwork)}</g>`;
      });
    });
    content += text(24, 752, 'The launcher chooses shape and themed colors.', 13, muted);
    content += text(24, 775, 'Only production supplies themed artwork.', 12, muted);
    content += text(24, 814, '390 × 844 · 64dp icons · no device claim', 12, muted);
    await sharp(svg(content, 390, 844)).png().toFile(path.join(output, `masks-${dark ? 'dark' : 'light'}.png`));
    const splash = await sharp(dark ? splashPath : lightSplashPath).resize(288, 288).png().toBuffer();
    await sharp({ create: { width: 390, height: 844, channels: 4, background: dark ? color('cookdex_launch_background') : lightSplashBackground } })
      .composite([{ input: splash, left: 51, top: 278 }]).png().toFile(path.join(output, `splash-${dark ? 'dark' : 'light'}.png`));
  }
  const summary = { safeCircleRadiusDp: 33, measuredArtworkRadiusDp: Number(radius.toFixed(3)), paintedPixelsAt10x: painted,
    artworkScale: foreground.sx, artworkTranslation: [foreground.tx, foreground.ty],
    splashSafeCircleRadiusDp: 96, measuredSplashRadiusDp: Number(splashRadius.toFixed(3)),
    adaptiveResources: 8, verifiedLegacyPNGs: 20, foreground: 'vector', monochrome: 'production-only vector',
    splash: 'Android12+ light resource; existing dark and pre12 retained',
    lightSplash: { background: lightSplashBackground, pan: lightColor('primary'), wordmark: lightColor('onSurface'), alphaMatchesDark: true },
    previewType: 'host SVG rasterization of native resource paths; not Android runtime' };
  fs.writeFileSync(path.join(output, 'verification.json'), JSON.stringify(summary, null, 2) + '\n');
  console.log(JSON.stringify(summary));
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
