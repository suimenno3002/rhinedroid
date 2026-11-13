# RhineDroid 2D UI spec for SwiftUI (iPad 1194x834 landscape / 834x1194 portrait)

Source root: `upstream/web/src`. CSS load order (later wins at equal specificity), from music-app.ts:1-14:
style.css → quality-settings.css → document-decryption.css → decryption.css → music.css → music-navigation-motion.css → music-navigation-ruler.css → music-transport-title.css → music-theme.css → music-theme-switch.css → music-overview.css → **android.css** → music-now-playing.css.
Every Android selector is prefixed `.music-app`, so android.css wins over music.css for the same property. Layout values below are given as "base (music.css) → effective (android.css)". Only the effective value matters for the iPad build.

Viewport media queries in android.css that do NOT apply at 1194x834 or 834x1194: `max-height:410px`, `max-width:700px`, `max-height:480px`, `max-width:740px` (all landscape-only). responsive.css is not imported by music-app.ts.

Units: 1 CSS px = 1 pt. `vw` = 11.94pt landscape / 8.34pt portrait. `vh` = 8.34pt landscape / 11.94pt portrait.

Fonts: style.css:1-34 registers `MiSans` from MiSans-Light/Regular/Demibold/Bold woff2. Mapping: weight 300 → **MiSans-Light**, 400/500 → **MiSans-Regular** (500 has no face, so the browser uses the nearest, Regular), 600 → **MiSans-Demibold**, 700 → **MiSans-Bold**. `.music-app { font-family: MiSans, system-ui, sans-serif }` (music.css:11). Buttons/inputs `font: inherit` (music.css:43-50). Default weight 400. The only exception is music.css:1299 `ui-monospace, monospace` (see detail section).

---

## 1. Root stage, theme variables, veils

### 1.1 Stage (music.css:13-22, music-app.ts:266-271)
`#stage.music-app` fills the viewport (`inset:0; width:100%; height:100%`), `background: var(--page-bg)`. On the native Vulkan build (android.css:157-160) html/body/#viewport/#stage are `background: transparent`. The 3D surface sits behind, and the page color is painted by the native renderer clear color. In SwiftUI: put the Metal view at the bottom with the clear color = `--page-bg`, and keep the SwiftUI overlay transparent.
Attributes on stage: `data-mode="archive"|"detail"`, `data-theme="day"|"night"`, `data-android="true"`, `data-layout="portrait"` (portrait only), `data-now-playing="true"` (expanded card).

Global rules:
- `button { border-radius: 6px }` (music.css:54-57). No background by default (style.css reset; see 1.5).
- `button:disabled { opacity: 0.38 }` (music.css:76-79).
- focus ring: `outline: 2px solid var(--accent); outline-offset: 4px` (music.css:68-75).
- `svg { width:20px; height:20px }` default icon size (music.css:80-84).
- `-webkit-tap-highlight-color: transparent` (android.css:2). No pressed highlight anywhere unless stated.

### 1.2 Theme variables (music.css:1-32; music-theme.css:1-71 @property initial values = day)

| var | day | night |
|---|---|---|
| `--ink` | `#232722` | `#e9eef2` |
| `--muted` | `#74786f` | `#9caabd` |
| `--line` | `rgba(42,49,42,0.18)` | `rgba(208,226,243,0.20)` |
| `--accent` | `#b56834` | `#d9ad7d` |
| `--surface` | `#efede7` | `#162234` |
| `--panel` | `rgba(245,244,239,0.97)` | `rgba(17,27,42,0.97)` |
| `--page-bg` | `#e8e5e1` | `#08121f` |
| `--veil` | `rgba(236,233,225,0.72)` | `rgba(10,21,37,0.75)` |
| `--music-status-ink` | `#74786f` | `#e9eef2` |
| `--music-night-mix` | `0` | `1` |

A "dusk" theme exists in CSS (music.css:33-42) but the app only exposes day/night (music-app.ts:85, 189-192). Ignore dusk.

Theme labels (music-app.ts:262-265): day = **暖昼**, night = **深夜**.

Theme transition (music-theme.css:94-112): once `.theme-motion-ready` is set, all of the variables above (plus `--music-side-veil-opacity` and the three `--music-night-veil-*` stops) interpolate over `calc(650ms * var(--music-motion-scale,1))` with `cubic-bezier(0.4, 0, 0.2, 1)`. SwiftUI: animate one `nightMix: Double` 0↔1 with `.timingCurve(0.4, 0, 0.2, 1, duration: 0.65)` and derive every color by lerping day→night (CSS @property `<color>` interpolates in premultiplied sRGB, so lerp premultiplied RGBA). `--music-motion-scale = 1 / motionSpeed` (music-app.ts:205). Default speed 1. With `reduce-motion` there's no transition (music-theme.css:165-167).

### 1.3 Vignette / veils (z-index 1, above 3D, below all UI)
`.music-vignette` (music.css:114-126) is `position:absolute; inset:0; pointer-events:none; z-index:1`. music-theme.css:115-159 replaces its background with two pseudo-layers that cross-fade:

**Day layer** (`::before`, music-theme.css:126-135), opacity `1 - nightMix`:
```css
linear-gradient(180deg, var(--veil), transparent 23%, transparent 75%, var(--veil))
```
`--veil` is the interpolated variable (day rgba(236,233,225,0.72)). Stops: 0% veil → 23% clear → 75% clear → 100% veil (vertical).

**Night layer** (`::after`, music-theme.css:142-159), opacity `nightMix`, two stacked gradients (the first is on top):
```css
linear-gradient(90deg,
  transparent var(--music-night-veil-start, 24%),
  rgba(5,13,25, calc(0.28 * var(--music-side-veil-opacity))) var(--music-night-veil-mid, 48%),
  rgba(5,13,25, calc(0.78 * var(--music-side-veil-opacity))) var(--music-night-veil-end, 70%),
  rgba(5,13,25, calc(0.84 * var(--music-side-veil-opacity)))),
linear-gradient(180deg, rgba(5,13,25,0.4), transparent 24%, transparent 73%, rgba(5,13,25,0.72))
```
Side-veil stops depend on state (music-theme.css:73-84, 137-141):
- default: start 24%, mid 48%, end 70%
- `data-mode="archive"` and landscape: start **32%**, mid **58%**, end **78%**
- portrait: `--music-side-veil-opacity: 0`, so the horizontal gradient is fully transparent and only the vertical one shows.
- detail mode in landscape uses the default 24/48/70.
The stops and side-veil opacity are registered @property types, so they animate with the same 650 ms curve. Archive↔detail therefore slides the night veil.

Resolved landscape archive (1194 wide): clear until x=382pt, rgba(5,13,25,.28) at 692pt, .78 at 931pt, .84 at 1194pt. Landscape detail: clear to 287pt, .28 at 573pt, .78 at 836pt, .84 at 1194pt.

**Edge mask** (android.css:184-186), applied to the whole vignette (both layers):
```css
mask-image: linear-gradient(180deg, transparent, #000 10%, #000 90%, transparent);
```
The veils fade to nothing over the top 10% and bottom 10% (83.4pt landscape / 119.4pt portrait), so the raw page-bg shows at the edges. SwiftUI: `.mask(LinearGradient(stops: [.clear@0, .black@0.1, .black@0.9, .clear@1], vertical))`.

### 1.4 `.three-scene`
`opacity:1; inset:0; transition: opacity calc(0.4s*scale)` (music.css:103-107). `touch-action:none` on Vulkan (android.css:161).

### 1.5 Z-order (low → high)
three-scene (0) → vignette (1) → browse/callout/status/detail (3) → navigation (4) → header (6) → overview / now-playing / panels / toast / loading (see their sections).

---

## 2. Top bar

DOM (music-app.ts:274-285). Global reset: `* {box-sizing:border-box}`; buttons have no border and no background (style.css:29-56).

### 2.1 Header container `.music-header`
| | landscape | portrait |
|---|---|---|
| position | abs, z 6, `top:12; left:20; right:20` (android.css:3) | `top:12; left:16; right:16` (android.css:124) |
| layout | flex row, `justify-content:space-between; align-items:center; gap:12` | flex **column** (music-theme-switch.css:49), `align-items:flex-start`+`stretch`, gap 12, wrap. Row 1 = brand (width 100%), row 2 = topnav (width 100%) |
| resolved | x 20…1174, y 12. Row height 48 (buttons), brand centered vertically | x 16…818. Brand at y 12, topnav row starts y ≈ 12+21+12 = 45 |

### 2.2 Brand block (`a.music-brand`, music.css:138-159, android.css:4-5,117,126-127)
- `.music-identity`: flex, align center, gap 28 (music.css:1903). Contains only the brand.
- Brand: flex column, gap 5, no shrink. Not interactive in the app (link to /index.html). In SwiftUI it's static text.
- `strong` "RhineDroid": MiSans **Bold 700**, **23px** landscape / **21px** portrait, line-height 1, letter-spacing 1px, color `--ink` (day #232722 / night #e9eef2).
- `span` subtitle: text `MUSIC ARCHIVE ／ LOCAL MUSIC PLAYER` (the `／` is a full-width slash inside `<i>`). **8px**, Regular 400, letter-spacing **0.7px** (android.css:117 wins over :5), line-height 1.5 (12pt line). `<i>`: `font-style:normal; color:--muted; margin:0 5px`. Rest is `--ink`. **Hidden in portrait** (android.css:127).
- Brand block height landscape = 23 + 5 + 12 = 40.

### 2.3 Library status line ("breadcrumb" under the brand) `#library-status` (music.css:230-255, android.css:16,131, music-theme-switch.css:123-129)
- Text (music-app.ts:809): native = `设备音乐 · {tracks} 首`; browser = `浏览器预览 · 静音演示`. For the iPad: `设备音乐 · {N} 首` (N = total track count), or replace with a Navidrome label in the same format.
- Abs, z 3. Landscape `top:76; left:22`; portrait `top:112; left:16` (android wins on position; font 8px and line-height 1.6 come from music-theme-switch.css:127-128).
- flex, align center, gap 7. Font **9px** landscape / **8px** portrait, Regular, letter-spacing 0.3px. Color day `--muted` #74786f, night `--ink` #e9eef2 (music.css:2184).
- Leading square `<i>` 4×4, radius 0, `#8c9b7b`. While a scan/enrich is running (`.working`): background `--accent` + `music-pulse 1.3s ease-in-out infinite` (opacity 1 → 0.25 at 50% → 1; music.css:1379).
- `visibility:hidden` in detail mode (the back button takes its place). Hidden in overview (see 2.8).

### 2.4 "缩略图模式" overview toggle `.music-view-toggle` (music-app.ts:285; music-overview.css:1-9,53; android.css:17,132)
- Structure: `[grid icon 16×16] 缩略图模式 [kbd V hidden]`. flex, align center, **gap 11**. Text 12px (`!important`), Regular, letter-spacing .06em = 0.72px, color `--ink`.
- Position abs, z 7. Landscape `left:20; top:102`, portrait `left:16; top:132`. `min-height:48; padding:10px 0`. No background. **`border-bottom:1px solid var(--line)`** (radius 6 from the global button rule only rounds the bottom corners slightly; the rule looks straight).
- Icon (stroke 1.5, see 2.9): `<rect x="3" y="3" width="6" height="7"/><rect x="15" y="3" width="6" height="7"/><rect x="3" y="14" width="6" height="7"/><rect x="15" y="14" width="6" height="7"/>`
- States: `disabled` until the scene is ready (opacity 0.38). Hidden when there are no albums. Detail mode: `opacity:0; visibility:hidden`. Overview active: `opacity:0; translateY(-6px)`, transitions opacity 280ms ease, transform 360ms cubic-bezier(.4,0,.2,1), visibility switched after 280ms (music-overview.css:39-52).

### 2.5 Top navigation `.music-topnav` (music.css:160-176, android.css:6-15,116,128)
Children in order: 音乐库 (folder icon) · 搜索 (search icon) · theme switch · ↻ (orientation) · settings icon · minimal transport.
- Landscape: flex, align center, **gap 4** (android.css:116 wins over :6 and music.css 25), padding 0.
- Every icon button: **48×48 min, padding 8**, radius 6, no background. Labels `<span>音乐库</span>` / `<span>搜索</span>` are **hidden** (android.css:15), so only icons show. SVG **17×17** (music.css:173), `currentColor` = `--ink`. Text-glyph button `↻`: 12px Regular `--ink`, centered.
- ↻ calls `nativeCommand("orientation")` (music-app.ts:1914). On iPad this rotates or does nothing. Keep it as a visual (the screenshots show it).
- Overview active: everything except the minimal transport gets `opacity:0; translateY(-6px)` (280/360ms, see 2.4).
- Portrait: `display:grid; grid-template-columns: repeat(4,48px) minmax(48px,1fr); gap:4; justify-content:space-between; width:100%` (android.css:128). The theme switch is `display:none` (android.css:129,154), so the grid cells are library, search, ↻, settings (48 each) + the transport (fills the rest: 834 − 32 − 4·48 − 4·4 = **594pt** wide).
- Approximate landscape x positions (right-aligned group ending at 1174): transport ≈ 1174−(12+48+48+2)=1064…1174, then settings, ↻, theme switch (~112 wide), search, library going left with 4pt gaps. In screenshot a-archive-day-landscape the icons sit at about y 18 centered on y≈36.

### 2.6 Theme switch pill `.theme-switch` (music.css:192-229, music-theme-switch.css:1-42, android.css:10-12)
- Container: flex, align center, gap 4, `height:48`, `border:1px solid var(--line)`, **radius 8**, padding 3, `position:relative; isolation:isolate`, no shrink. Landscape only.
- Two buttons, `暖昼` (day) and `深夜` (night), each: flex, align center, justify center, gap 5, radius 5, min 48×48, padding 8 (android), font **11px** Regular, `flex:1 0 auto`. Content: `[7×7 square dot] 暖昼`.
- Dot: 7×7, radius 0, `box-shadow: 0 0 0 1px rgba(128,128,128,0.35)` (1px gray ring). Day dot `#e9c492`, night dot `#415577`.
- Inactive button: `opacity:0.6`, color `--ink`. Active (`aria-pressed=true`): `opacity:1`, color `--surface` (day #efede7 / night #162234), background transparent. The dark fill is the moving pill.
- Pill `::before`: abs `top:3; bottom:3; left:3; width:calc((100% − 10px)/2)`, radius 5, `background:var(--ink)`. Day `translateX(0)`, night `translateX(calc(100% + 4px))`. **Transition transform 380ms cubic-bezier(0.22,1,0.36,1)**. Button color/opacity transition 260ms ease. Ink itself crossfades over 650ms (section 1.2).
- Resolved: button ≈ 8 + 7 + 5 + 22 + 8 = 50 wide, pill width ≈ 50, container ≈ 3+50+4+50+3+2 = 112 × 48.

### 2.7 Minimal transport box (top right) `.minimal-transport` (music.css:1908-1960, 2282-2292; android.css:9,13-14,112-115,149-153,167-182; music-transport-title.css)
Structure: `[#transport-track title slot] [play/pause] [stop]`.
- Container: flex, align center, **gap 0**, `padding-left:12px` (landscape), `margin-top:-5px` (landscape; the box sits 5pt higher than the icons), **radius 8**.
- Glass (android.css:167-182), border on all sides:

| | day | night |
|---|---|---|
| background | `linear-gradient(145deg, #ffffff45, #ffffff08 38%, #ffffff18 75%, #ffffff38), color-mix(in srgb, var(--page-bg) 94%, transparent)` | `linear-gradient(145deg, #ffffff15, #ffffff03 44%, #ffffff08), color-mix(in srgb, var(--page-bg) 94%, transparent)` |
| border | `1px solid color-mix(in srgb, var(--line) 50%, #ffffffa8)` | `1px solid color-mix(in srgb, var(--line) 50%, #ffffff50)` |
| box-shadow | `inset 0 1px 0 #ffffffc4, inset 1px 0 0 #ffffff45, inset 0 -1px 0 #ffffff35, 0 10px 28px #00000016` | `inset 0 1px 0 #ffffff60, inset 1px 0 0 #ffffff18, inset 0 -1px 0 #ffffff15, 0 12px 30px #0005` |

  The base is page-bg at 94% alpha (day rgba(232,229,225,.94) / night rgba(8,18,31,.94)). No backdrop blur.
- Buttons (play-pause, stop): **48×48** (min wins over 29×29), padding 8, `opacity:0.8` (music.css:2291), color `--ink`. `aria-pressed=true` (playing) → `opacity:1; color:--accent`. Transition opacity and color 180ms. SVG 17×17. Disabled (nothing loaded) → opacity 0.38.
- Play/pause cross-glyph: both glyphs are stacked absolutely. The inactive one is `opacity:0; scale(0.7)` and the active one `opacity:1; scale(1)`, 180ms ease for both properties (music.css:1934-1957).
- Title slot `#transport-track` (music-transport-title.css:6-39, android.css:112): `width:0; opacity:0; margin-right:-6px` while hidden. When visible (something playing): `width: min(--song-width, --song-cap)`, opacity 1. Transition width **640ms cubic-bezier(0.4,0,0.2,1)**, opacity 400ms ease. Inner span: 12px landscape / **11px** portrait (≤1100 width rule), line-height 29px, padding-inline 2, ellipsis, `translateX(18px)` → `0` over 640ms with the same curve. `--song-width = ceil(text width + padding) + 14`. Caps: landscape `--song-cap = clamp(0px, calc(100vw − 760px), 240px)` = 240 and `max-width:125px` (android.css:112) → **≤125pt**. Portrait `--song-cap: min(90px, calc(100vw − 288px))` = **90pt** and max-width 90. Tapping it toggles the now-playing card (`data-action="toggle-now-playing"`).
- The title text changes with a rolling reel: `createRollingText` 460ms, direction up, transition "direct", stagger none, motion blur (`--rn-blur:0.2`, edge fade 0.08em) (music-transport-title.ts:18-26). The text is truncated per grapheme to fit and ends with `…`.
- Portrait (android.css:149-153): `position:static; padding:0; margin:0; border:0; gap:0`, justify flex-end. The glass background and shadows stay, but **there is no border**. **Stop button hidden.** It fills the 5th grid column (594 wide, 48 tall), with play at the right edge (see a-archive-day-portrait.png).

### 2.8 Icon SVGs (verbatim)
Helper (music-app.ts:89-90):
```html
<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${path}</svg>
```
`icons` (music-app.ts:91-105):
```
play:     <path d="m9 5 11 7-11 7Z" fill="currentColor" stroke="none"/>
pause:    <path d="M7 5h3v14H7zM14 5h3v14h-3z" fill="currentColor" stroke="none"/>
stop:     <rect x="6" y="6" width="12" height="12" rx="1"/>
search:   <circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 4.5 4.5"/>
settings: <path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="2.5" fill="var(--surface)"/><circle cx="15" cy="17" r="2.5" fill="var(--surface)"/>
previous: <path d="M5 5v14M19 5 8 12l11 7Z" fill="currentColor"/>
next:     <path d="M19 5v14M5 5l11 7-11 7Z" fill="currentColor"/>
speaker:  <path d="M4 9h4l5-4v14l-5-4H4Z"/><path d="M17 8a6 6 0 0 1 0 8M20 5a10 10 0 0 1 0 14"/>
folder:   <path d="M3 7V5h6l2 2h10v13H3Z"/>
```
Inline icons: overview grid (2.4); overview return chevron `<path d="M15 5l-7 7 7 7"/>` (music-app.ts:289). The settings knobs are filled with `--surface`, so they hide the line behind them. previous/next are both stroked and filled.
Stroke width 1.5 in a 24 viewBox at 17pt → **1.0625pt**, round caps and joins.

brand.ts is not used in the top bar (brand is text). Its mark/contour paths are used by the boot sequence (section 10):
```
paths (labelMark/logo): <path d="M156 75C127 48 103 15 70 15C37 15 15 39 15 70S38 128 70 128C103 128 127 96 176 52M155 75C182 99 208 128 240 128C273 128 295 105 295 73S273 15 240 15C221 15 207 23 192 38" fill="none" stroke="currentColor" stroke-width="26"/><path d="M44 70h50M69 45v50M219 70h44" fill="none" stroke="currentColor" stroke-width="15"/>
logo viewBox 0 0 310 185 + <text x="165" y="174" text-anchor="middle" font-family="MiSans,sans-serif" font-size="16" font-weight="700" letter-spacing="22">RHINE·LAB</text>
bootMarkContour: M295 73C295 41 273 15 240 15C221 15 207 23 192 38C186 43 181 47 176 52C127 96 103 128 70 128C38 128 15 101 15 70C15 39 37 15 70 15C103 15 127 48 156 75C182 99 208 128 240 128C273 128 295 105 295 73Z
```

---

## 3. Album callout (`.album-callout`, archive mode)

DOM (music-app.ts:292-299), in `#music-browse` (section, `position` not set, so children are positioned against the stage):
```
.music-browse-veil
.album-callout
  p.music-eyebrow   "MUSIC ARCHIVE " <span>／</span> " " <span#selection-genre>
  div.selection-rule  <span#selection-code>"ALBUM " <span#selection-code-number>001</span></span> <span#selection-format>
  h1#selection-title
  p#selection-artist.selection-artist
  div#selection-meta.selection-meta
  button.open-album  "打开专辑 " <span>↗</span>
```

### 3.1 Box
Selector specificity: android `.music-app:not([data-layout="portrait"]) .album-callout` (android.css:19) ties with music.css:2456 and wins because it loads later. `max-width` is `none` (music.css:2459).

| | landscape 1194×834 | portrait 834×1194 |
|---|---|---|
| left | `64%` = **764.2** | `16` (android.css:133) |
| right | `20px` → right edge **1174** (width 409.8) | `16` (width 802) |
| top | `29%` = **241.9** | `auto` |
| bottom | `var(--callout-bottom)` (music.css:2219), set by JS to `stageHeight − navigation.offsetTop + 28` (music-title.ts:270-276). ≈ **127** (nav top ≈ 735, see 4.1), so the box ends at y ≈ 707 | `164px` → box ends at **y 1030** |
| height | top→bottom (≈465) | `auto`, `max-height:28%` = **334.3** |
| padding / margin | 0 | `padding:8px 0; margin:0` |
| layout | flex column, children `flex-shrink:0`, `min-height:0`, z 3, `overflow-y:auto; overscroll-behavior:contain` | same + `overflow-y:auto` |
| background | none | `linear-gradient(90deg, var(--veil), transparent)` (music.css:2481): day rgba(236,233,225,.72) → clear, left to right |

All text is `--ink` unless stated. `text-shadow:none`. Hidden (`visibility:hidden`) while the now-playing card is expanded (android.css:110-111).
Screenshot check (a-archive-day-landscape): the eyebrow sits at y≈248, x=764. Portrait: eyebrow y≈810, open-album rule y≈1022.

### 3.2 Browse veil `.music-browse-veil` (music.css:561-569, 2483-2490)
`position:absolute; inset:0; pointer-events:none`, below the callout.
- Landscape: `linear-gradient(90deg, transparent 42%, var(--veil) 66%, var(--page-bg) 96%)` → clear to x 501.5, veil at 788, page-bg at 1146 and beyond.
- Portrait (the later rule wins):
```css
linear-gradient(180deg,
  transparent calc(var(--portrait-callout-top) - 12vh),
  var(--veil) calc(var(--portrait-callout-top) + 7vh),
  var(--page-bg) calc(var(--portrait-callout-top) + var(--portrait-callout-height)))
--portrait-callout-height: min(max(210px, 33.333vh), calc(100vh - var(--callout-bottom, 135px) - 150px));
--portrait-callout-top: calc(100vh - var(--callout-bottom, 135px) - var(--portrait-callout-height));
```
  These use the JS `--callout-bottom`, not android's 164. Portrait nav ≈ 116 tall at bottom 36, so callout-bottom ≈ 180, height = 398, top ≈ 616 → clear to y≈473, veil at ≈700, page-bg at ≈1014 and below. (Approximate: depends on the measured nav height.)

### 3.3 Rows

| element | text / data | font | spacing | color |
|---|---|---|---|---|
| eyebrow `p.music-eyebrow` (music.css:265-274, android.css:20) | `MUSIC ARCHIVE ／ {column name}` (column = `archiveColumns[lane]`, i.e. the genre name in genre sort mode). The `／` span has `margin:0 4px` (on top of the literal spaces) | **9px** Regular 400, letter-spacing **1.5px**, line-height **1.7** (15.3) | single line, `white-space:nowrap; overflow:hidden; text-overflow:ellipsis` | ink |
| rule `div.selection-rule` (music.css:275-288) | left `ALBUM {NNN}`: NNN = global index `selected+1`, 3-digit zero-pad (`minimumIntegerDigits:3`). Right `#selection-format`: demo → `DEMO`, otherwise the unique `track.format` values joined with ` / ` (e.g. `FLAC`, `FLAC / MP3`) | left **10px** ls 1px; right **9px** ls 1px, `--muted` | flex space-between, gap 16, `padding:15px 0 12px; margin:0 0 17px`, **`border-bottom:1px solid var(--ink)`** (full-strength ink rule) | ink / muted |
| title `h1#selection-title` | album title (see 3.4) | MiSans **Bold 700**, base size: landscape `clamp(23px, 3.4vw, 38px)` = **38** (3.4vw = 40.6), portrait `clamp(24px, 7vw, 36px)` = **36** (7vw = 58.4) (android.css:21,134 beat the `--album-title-size` rule music.css:2230). line-height **1.4**, letter-spacing **−0.6px**, `overflow-wrap:anywhere` | margin landscape **12 0 8**, portrait **8 0 8** | ink |
| artist `p.selection-artist` (music.css:298-303, android.css:22) | `album.artist` verbatim (no case change; no text-transform anywhere in the CSS) | **12px Demibold 600**, line-height 1.6 (19.2) | `margin:0 0 10px` | ink |
| meta `div.selection-meta` (music.css:304-309, android.css:23,135) | `{year or "年份未提供"}  /  {N} 首曲目  /  {m:ss}`. Separator is **two spaces, `/`, two spaces** (music-app.ts:850-856). Demo replaces the middle item with `演示封面`. The duration item is dropped when there are no tracks. Duration = sum of track seconds as `floor(min):ss` with no hours (e.g. `75:03`), music-app.ts:366-369 | **10px**, weight 500 → MiSans Regular, letter-spacing 0.5px | landscape `display:block`; portrait `display:flex; gap:10px` (one text node, so gap has no effect) | `--muted` |
| open `button.open-album` (music.css:310-326, 2262; android.css:24) | `打开专辑` + span `↗` | label **13px** Regular; `↗` **24px** line-height 1 | flex, space-between, align center, width 100%, **min-height 48**, `padding:10px 0`, **margin-top 8** (android beats music.css:2262's 22), **`border-bottom:1px solid var(--line)`**, radius 6 | ink; hover/pressed → `--accent` |

Screenshot sample (landscape): `MUSIC ARCHIVE ／ 氛围音乐` / `ALBUM 001 ……… DEMO` / rule / `日光留声` / `ORBIT STUDIO` / `2026  /  6 首曲目  /  20:15` / `打开专辑 ↗`.

**Focus ring visible in every reference screenshot:** after the browse surface is revealed the app calls `$("[data-action=open]").focus()` (music-app.ts:537). WebView shows `:focus-visible` there, so there is a **2px `--accent` outline at offset 4px with ~10px rounded corners** (6 radius + 4 offset) around the open-album row. That is the orange double line in the screenshots. Replicate it as a static accent stroke rect inset −4 around the button if pixel parity with the screenshots is the goal, or drop it as a focus artifact. Pick one deliberately.

### 3.4 Title fitting and subtitle (music-title.ts)
- `albumTitleParts` (music-title.ts:5-16): if the title matches `^(.+?)[（(]([^（）()]+)[）)]\s*$`, the main part contains Han characters, and the bracket contains Latin letters and no Han, then it splits into **main** + **translation** (brackets dropped). Otherwise the whole title is main.
- Translation (music.css:2240-2248): block, `margin-top:0.48em`, `font-size:0.45em`, line-height 1.45, letter-spacing 0.01em, **Demibold 600**, `--muted`.
- Fit algorithm (music-title.ts:224-254): budget = callout inner height − every other child's height+margins − title margins (min 28). Try the base size first. It fits when total height ≤ budget+1 **and** the main part is ≤ 2 lines. Otherwise try 8 coarse sizes linearly from base down to **min 20** (18 when innerWidth ≤ 700), then 16 fine steps between the last failure and the first fit. If nothing fits at 20, use 20 and clamp main and translation to **2 lines each**, replacing the overflowing tail of the last line with `…`.
- The reel slot keeps a line box of `size × 1.4` per line.

### 3.5 Title reel animation (music-title-reels.ts)
- Each grapheme becomes its own slot at its natively-laid-out (x,y). Slot = `overflow:hidden`, `padding-inline:0.15em; margin-inline-start:-0.15em`, with a vertical feather mask `linear-gradient(to bottom, transparent, #000 0.02em, #000 calc(100% - 0.02em), transparent)` (music.css:2425-2450). Each face is `white-space:pre` with `clip-path: inset(0 -0.15em)`.
- Slots are keyed by `kind:line:indexInLine`. A selection change re-renders: if the character at a slot key differs (text, font, size, or height), the slot's wheel stacks [current face, new face] vertically and translates from 0 to −(old face height). **The old glyph scrolls up and out and the new one comes up from below.** Slots that are no longer used roll to a blank face. New slots appear empty and roll the glyph in. Unchanged glyphs stay still (only their position moves if the layout shifts).
- All glyphs start together: **no stagger**, one shared timeline origin.
- Curve (music-title-reels.ts:40-55): critically damped spring, **460 ms × motion-scale**, `t = elapsed/460`:
  `x(t) = target + (Δ + a·t)·e^(−10t)`, with `Δ = start − target` and `a = v0·0.46 + 10Δ`. At rest `v0 = 0`, so `x(t) = target + Δ·(1+10t)·e^(−10t)`. Baked as 49 linear keyframes. On interruption the current position and velocity carry over (velocity clamped to ±(max(|Δ|,1)·12/0.46)). Same curve for slot position (translate3d x,y), slot viewport height (clip-path), and the title block height.
- Disabled (no animation) during boot, in detail mode, with reduce-motion, or while hidden.
- SwiftUI: one `Text` per grapheme in a fixed-height clipped box, offset driven by a custom spring `(1+10t)e^{-10t}` over 0.46 s (≈ `.interpolatingSpring(mass:1, stiffness:(10/0.46)², damping:2·10/0.46)` = stiffness 472.6, damping 43.5).

### 3.6 Other rolling fields (music-text-motion.ts)
`#selection-genre`, `#selection-format`, `#genre-name` (rolling text), `#selection-artist`, `#selection-meta` (rolling text if it fits on one line, else plain wrapped text), and the numbers `#selection-number` (2 digits), `#selection-total` (2), `#selection-code-number` (3), `#genre-index` (2), `#genre-total` (2), all from `@kitlangton/rolling-number` 0.4.1.
- Options: duration **460 ms** × scale, `motionBlur:false`, `transition:"direct"`, `stagger:"none"`, edge fade `--rn-edge-fade:0.08em`, blur 0 (music.css:2385-2389). Per-glyph vertical reels with the same `(1+10s)e^(−10s)` damped curve.
- Direction: navigation forward (`direction > 0`) → `"up"`, backward → `"down"`, jumps → `"auto"`. Row moves only drive `selection-number`. Column moves drive `selection-total` and `genre-index`. `selection-code` always follows the direction. `genre-total` uses auto.
- Number formats: `en-US`, no grouping, zero-padded to the minimum digit count.

### 3.7 Browse surface transition (music-app.ts:418-428, ui-transitions.ts)
The four layers (veil, callout, navigation, keyhint) fade **opacity only**. The same fade also plays during boot and on the return from detail (no transform): show **720 ms `cubic-bezier(0.45,0,0.25,1)`**, hide **140 ms `cubic-bezier(0.4,0,1,1)`**. An interrupted reversal uses `max(72, base·sqrt(remaining distance))` ms. Times scale with motion speed.

---

## 4. Bottom navigation (`.music-navigation`) and status footer

DOM (music-app.ts:300-305, 313). `.music-keyhint` is `display:none` on Android (android.css:18), so skip it.

### 4.1 Grid container
| | landscape | portrait |
|---|---|---|
| position | abs z 4, `left:20; bottom:35` (android.css:25), `right:6.2%` = 74.0 (music.css:331) → x 20…1120, width 1100 | `left:12; right:12; bottom:36` (android.css:136) → width 810 |
| grid | `grid-template-columns: minmax(74px,.55fr) minmax(0,1fr) minmax(0,1fr); gap:14; align-items:center` → columns **231.2 / 420.4 / 420.4** at x 20 / 265.2 / 699.6 | one column, `gap:4`. Rows: album stepper, genre stepper. Counter hidden |
| height (approx.) | ≈ 63 (genre block: 8px label + 5 + 48 button) → top ≈ 736 | ≈ 48 + 4 + 63 = 115 → top ≈ 1043 |

Screenshot check: landscape ↑/↓ centered at x≈475 (column center), genre arrows at x≈844 and 976. Portrait stepper row centered y≈1067, genre arrows y≈1127.

### 4.2 Counter (bottom left, landscape only) `.music-counter` (music.css:338-359, android.css:26-27)
- `span.music-eyebrow` **`ALBUM / SELECT`**: 8px Regular, letter-spacing 1.5px, line-height 1.7, ink.
- Row div: flex, `align-items:baseline`, gap 8, margin-top 6.
  - `b#selection-number`: position of the album **within its column**, 1-based, 2-digit zero pad (`01`). **34px Light 300**, line-height 1, letter-spacing **−3px**, ink.
  - `span` `/ ` + `i#selection-total`: number of albums in the column, 2-digit (`03`). 12px **Light 300**, `--muted`. The `i` has `margin-left:8px` (in addition to the space after `/`), letter-spacing 1px, normal style, `tabular-nums`, inline-flex (music-navigation-motion.css:103-108).
- Both numbers are rolling reels (section 3.6). Row navigation drives `selection-number`'s direction. Column navigation drives `selection-total`'s.
- Hidden in portrait (android.css:137).

### 4.3 Album stepper (center) `.album-stepper` (music.css:360-373, android.css:28-35,139)
- flex, align center, `gap:6` (landscape), `justify-self:center`. Portrait: `display:flex; width:100%; justify-content:center; gap:0`.
- `↑` button (prev, `aria-label 上一个专辑`) · ruler `#album-ticks` · `↓` button (next, `下一个专辑`). Glyph buttons: **25px** Regular, line-height 28, **min 48×48**, no shrink, ink. Hover → accent. Disabled (opacity 0.38) only in `arrayMode:"realistic"` at the column ends, or when the column is empty (music-app.ts:966-975).
- `↑` = `stepAlbum(-1)`, `↓` = `stepAlbum(+1)`. They wrap within the column in the default `filled` mode.

### 4.4 Ruler `#album-ticks.music-ruler` (music-ruler.ts, music-navigation-ruler.css)
The default navigation. `music-ticks.ts` with `music-navigation-motion.css` is only used for `?nav=previous`, so it is not needed.
- Constants: `--tick-width:3px; --tick-gap:8px; --tick-rest:10px; --tick-hover:22px; --tick-height:30px` (narrow ≤700px screens use 2/6/8/16/21, which does not apply here). step = 11.
- Host: `display:block; height:30; overflow:hidden`, width = `min(12, n)·11 − 8` (spring-animated). n=3 → **25**, n≥12 → **124**. When n > 12 (`data-overflow`), mask: `linear-gradient(90deg, transparent, #000 8px, #000 calc(100% - 8px), transparent)`.
- Capacity 12 visible, overscan 2 (pool 16), **anchor 5**: when n > 12 the selected tick stays the 6th tick and the strip scrolls. It loops infinitely (`filled` mode) or clamps (`realistic`).
- Each tick: button at `translate3d(x,0,0)`, 3×30 hit box, with the `::after` hit area extended by 4px on each side. Mark: centered vertically, width 3, `background:var(--ink)`.
  - rest: height **10**, opacity **0.28**
  - selected: height **30**, opacity **1**
  - hover/focus (not selected): height **22**, opacity 1, background **`--accent`**
- Motion: every value (scroll, width, height, opacity, presence, x offset) is a **critically damped spring, ω = 18 /s**: `x = target + (Δ + (v + 18Δ)·dt)·e^(−18·dt)`, integrated per frame (dt ≤ 50 ms × speed). Close to a SwiftUI `.interpolatingSpring(stiffness: 324, damping: 36)`.
- On a group (column) change: ticks are reassigned to the nearest existing x, reveal staggered **24 ms × visible order**, and every tick runs a 560 ms ripple: rest height × (1 − 0.4·sin(π·p)), opacity 0.28 − 0.08·sin(π·p).
- Tapping a tick selects that album, passing its ordinal offset as the row direction.
- aria-label `选择专辑`; each tick `选择专辑 {title}`.

### 4.5 Genre / column stepper (right) `.genre-stepper` (music.css:426-449, android.css:30-35,138,140)
- flex, align center, justify center, **gap 4**. Portrait: `width:100%; justify-content:space-between` (arrows at the screen edges, label centered).
- `←` (genre-prev) and `→` (genre-next): **25px**, min 48×48, ink, no shrink. aria `上一个{列名}` / `下一个{列名}`.
- Center block: `text-align:center`, `min-width:118` landscape / **78** portrait.
  - `small#genre-position`: `{CODE} {II} / {TT}`. CODE by sort mode: `GENRE` (按流派, default), `ARTIST` (按歌手名字), `ALBUMS` (按专辑名字) (music-app.ts:208-212). II = 1-based column index, TT = column count, both 2-digit. **8px**, letter-spacing 1.3px, `--muted`, block, margin-bottom 5.
  - `button#genre-name`: column name (genre name; empty genre → `未分类`). **14px** Regular, letter-spacing 1px, min-height 48, padding 4, single-line ellipsis, ink. Tap → opens the **search** panel (`case "genres"`).
- Column labels for the arrows: `流派` / `歌手` / `分组`.
- Data: columns = `archiveColumns` (data.ts). The genre name is a rolling text and the indices are rolling numbers (section 3.6).

### 4.6 Status footer `.music-bottomline` (music.css:463-478, android.css:36,147-148)
- abs z 3, landscape `left:20; right:20; bottom:10`, portrait `left:12; right:12`. flex space-between. **8px** landscape / **7px** portrait, letter-spacing 1.1px, `--muted`, normal line height.
- Left: `LOCAL COLLECTION` + `<i>·</i>` (margin 0 8px, normal style) + `#library-count` = `{n} ALBUMS / {t} TRACKS`, or `DEMONSTRATION` in demo (music-app.ts:819-821). In landscape it sits under the counter.
- Right `#runtime-info`: initially `THREE.JS / LOCAL / V0.4.8` (music-app.ts:313), then rewritten every 1.5 s (music-app.ts:2349-2351): native Vulkan = `VULKAN · GPU INSTANCING / {暖昼|深夜} / V{version}`. The browser build (what the screenshots show) = `{round(fps)} FPS / {theme label} / V0.4.8`, e.g. `7 FPS / 暖昼 / V0.4.8`. On iPad, use `{fps} FPS / 暖昼 / V0.4.8` (or a Metal equivalent of the native string). **Hidden in portrait** (android.css:148).
- In overview, `#runtime-info` fades out (opacity 0, translateY −6, 280/360 ms, see 2.4).

**Portrait note (applies to every section):** music.css `@media (max-width:1100px)` (music.css:1487-1621, 2321-2328) **matches portrait 834 wide** but not landscape 1194. Android rules still win where they set the same property. Values that survive in portrait are called out per section (e.g. transport title 11px, detail tabs gap 14 / 10px, track grid 20/30/34).

---

## 5. Detail mode (`data-mode="detail"`)

DOM (music-app.ts:307-311, rendered by renderDetail music-app.ts:1059-1104, trackList :1108-1122, albumAbout :1123-1127). `.music-detail` = `position:absolute; inset:0; z-index:3; pointer-events:none` (children re-enable pointer events).

### 5.1 Layout
| element | landscape | portrait |
|---|---|---|
| back `button.music-back` | `top:74; left:20` (android.css:37) | `top:128; left:16` (android.css:141) |
| card caption `.card-caption` | `left:20; bottom:35`, flex column gap 5 (android.css:38) | `left:16; right:16; top:45%` = **537.3**, bottom auto (android.css:143) |
| content `#album-detail-content` | `left:53%` = **632.8**, `right:20` (→1174, width 541.2), `top:85`, `bottom:30`, `padding-right:6` (android.css:40) | `left:16; right:16; top:51%` = **608.9**, `bottom:30`, `padding:12px 0 0`, **`border-top:1px solid var(--line)`** (android.css:142) |
| portrait fade | — | `.music-detail::before`: abs `inset:46% 0 0` (from y 549.2), `linear-gradient(180deg, transparent, var(--page-bg) 34px)` (music.css:570-576) |

The content scrolls (`overflow:auto; overscroll-behavior:contain`, thin scrollbar colored `--line`). The left part is the 3D card (native). Library status is hidden in detail. The overview toggle fades out.

### 5.2 Back control and caption
- `← 返回专辑架` + `<kbd>ESC</kbd>` (kbd hidden on Android). **11px** Regular, letter-spacing 0.4px, flex align center gap 25, `min-height:48; padding:8px 0`, ink. Action `back` → archive mode.
- Caption `span#detail-card-id` = `ALBUM / {NNN}` (global index, 3-digit) **12px**, letter-spacing 2px, ink. `small` = `拖动卡片，查看完整封面` **9px** `--muted`, **hidden in portrait** (music.css:1899).

### 5.3 Content blocks, top to bottom (music.css:542-810; android.css:41-46)
1. **Overline** `.detail-overline`: flex space-between, align center, gap 20, margin-bottom 18. Left `ALBUM {NNN}` **8px** letter-spacing 1.6px. Right group (gap 20): `↑ 上一张` and `下一张 ↓`, **9px**, letter-spacing 0, min-height 48. These call stepAlbum −1/+1, with the same disabled rules as section 4.3.
2. **Title** `h1`: **25px Demibold 600** (android.css:42 beats both clamps), line-height 1.22, letter-spacing −0.6px, `margin:0 0 10px`, `overflow-wrap:anywhere`. Uses the same main/translation split (3.4). The translation is `0.5em` (12.5px) Demibold `--muted`, margin-top 0.48em. No reels here.
3. **Artist** `p.detail-artist`: **14px** Regular, flex align center gap 12, margin `0 0 22`. Optional badge `目录离线`: 10px `--accent`, `border:1px solid var(--line)`, padding 3 6.
4. **Facts grid** `.album-facts`: `grid-template-columns:1fr 1fr; gap:12px` (android), `padding:19px 0; margin:12px 0`, **`border-top:1px solid var(--ink)`**, `border-bottom:1px solid var(--line)`. Each cell: `small` label **7px** `--muted` letter-spacing 0.6px, block, margin-bottom 5. `span` value **11px** landscape / **10px** portrait (1100 rule), line-height 1.5, ink, anywhere-wrap.

   | label (verbatim) | value |
   |---|---|
   | `RELEASE / 发行年份` | year or `未提供` |
   | `ARTIST / 歌手` | album.artist |
   | `GENRE / 流派` | genre name or `未分类` |
   | `VOLUMES / 内含 CD` | `{discs} CD · {n} 首` (demo `—`) |
   | `FORMAT / 文件格式` | unique `FORMAT / CODEC` (or format alone) joined with ` · `. Empty → `未提供` (demo `封面演示`) |
   | `RESOLUTION / 位深与采样率` | `{bits} / {rate}`. bits = `有损编码` if every track is lossy, else `{n} bit` or a `{min}–{max} bit` range (en dash). rate = `{kHz with ≤1 decimal} kHz` (e.g. `44.1 kHz`, `48 kHz`). Missing → `未提供` |
   | `BITRATE / 码率` | `{round(bps/1000)} kbps` or a range. Missing → `未提供` |
   | `DURATION / 总时长` | `m:ss` total (minutes not wrapped into hours) |

5. **Tabs** `.music-tabs` (role tablist): flex align center, **gap 22** landscape / **14** portrait, `padding-top:6`, `border-bottom:1px solid var(--line)`, **`position:sticky; top:0; z-index:1; background:var(--veil); backdrop-filter:blur(18px)`**. The sticky bar is visible as a light band in c-detail-tracklist-day.png.
   - Tab buttons: `<span>01</span> 歌单` and `<span>02</span> 专辑介绍`. **11px** landscape / **10px** portrait, `padding:15px 0 11px`, min-height 48, nowrap. Inactive `--muted`, selected `--ink`. The number span is **8px**, margin-right 6.
   - Indicator `i.music-tab-indicator`: abs `left:0; bottom:-1px; width:1px; height:2px; background:var(--ink); transform-origin:left`. JS sets `translateX(button.offsetLeft) scaleX(button.offsetWidth)`, so it underlines the full tab width. Transition **transform 180ms cubic-bezier(0.22,1,0.36,1)**. No transition on first render.
   - Switching tabs: the panel content is replaced and fades **opacity 0.35 → 1 over 150ms cubic-bezier(0.22,1,0.36,1)** (ContentTransition, ui-transitions.ts:103-117). Keyboard ←/→/Home/End on a focused tab switch tabs.
6. **Track list** (tab 歌单), each `button.track-row`:
   - `display:grid; grid-template-columns: 23px minmax(0,1fr) 40px 38px; gap:9px` (portrait: `20px minmax(0,1fr) 30px 34px; gap:6px`), align center, text-align left, `padding:11px 0`, **min-height 48**, `border-bottom:1px solid var(--line)`, width 100%.
   - Columns: number `{trackNumber or index+1, 2-digit}` **9px** `--muted` tabular-nums. Name block: `strong` title **12px** weight 500 (Regular), single-line ellipsis, ink. `small` track artist **10px** `--muted`, margin-top 5, ellipsis. Format `{FORMAT}` **7px** `--muted` right-aligned, plus ` ↗` when the file is not browser-playable. Duration `m:ss` **9px** `--muted` tabular right-aligned.
   - Pressed/hover: `background:var(--veil); color:var(--accent)`. Transition color and background 0.15s.
   - **Playing indicator:** `.playing` → `color:var(--accent)` on the row. Only the title text visibly changes, because the number/format/duration/artist have explicit `--muted`. There is no icon or bar (music.css:731, music-app.ts:1380-1388).
   - Search reveal highlight: `background: color-mix(in srgb, var(--accent) 20%, transparent); box-shadow: inset 3px 0 var(--accent)`.
   - Multi-disc albums: `div.disc-heading` `DISC {NN}` 8px letter-spacing 1.5px `--muted`, padding 20 0 8, before each disc's first track.
   - Rows are disabled if the album folder is offline. Tap → play from this track.
   - Empty album: `.empty-tracks` padding 25 0. `strong` 13px/500: `这个专辑还没有可播放曲目` (demo `这是一张封面演示卡片`). `p` 11px muted line-height 1.9: `请检查音乐文件是否完整，并重新扫描音乐库。` (demo `用于检查封面原始比例与卡片材质。扫描本地音乐库后，这里会显示真实曲目。`). Button `打开音乐库设置 ↗` 11px, border-bottom line, padding-bottom 4, margin-top 10.
7. **About** (tab 专辑介绍) `section.album-about` padding 27 0 20:
   - `small` `ABOUT THIS ALBUM` 8px letter-spacing 1.5px `--muted`.
   - With a description: `p` **12px** line-height **1.95**, `white-space:pre-line`, ink. Optional link `来源：{name} ↗` (text-button, min-height 48) + license small.
   - Without one: `h3` `专辑介绍待补充` 14px/500, margin 17 0 10. `p` `从公开百科核对专辑与歌手后读取介绍，附上来源并保存在本机。无法确认对应专辑时保留空白。`
   - The native build adds `查询专辑介绍 ↗` / `更新专辑介绍 ↗` plus a status line. Skip it or map it to Navidrome getAlbumInfo2.
   - Source note: flex column, gap 6, margin-top 25, `--muted`. `span` `本地音乐 · 文件保持只读` (demo `演示数据`) 8px letter-spacing 1px. `code` = folder path, 9px line-height 1.6, MiSans (font-family inherit).
   - Raw genre tags: flex wrap, gap 7, margin-top 18. Each 9px, padding 4 7, `border:1px solid var(--line)`, radius 0.
   - Then (non-demo) `label.field-label` `手动分类` + text input + `保存分类 ↗`. Input styles are in section 9. Then the producer credits block (`producerBlock`, music.css:811-962), which is optional and can be skipped for the iPad build.
   - For the iPad: Navidrome lyrics (plain text) can go in a third tab or inside 专辑介绍. Reuse the `.album-about p` style (12px / 1.95, pre-line).

### 5.4 Motion
- Surface transition (music-app.ts:411-417): `SurfaceTransition(#music-detail, content, 360, 240, "right")`. **Show:** opacity 0→1 and content `translateX(24px)→0`, **360ms cubic-bezier(0.22,1,0.36,1)**. **Hide:** opacity→0 and `translateX(32px)`, **240ms cubic-bezier(0.4,0,1,1)**. It is revealed only after the native camera finishes entering (MusicPresentation gate).
- Redaction reveal (document-decryption.ts, music-app.ts:406-409): targets `h1, .detail-artist, .album-facts span, .track-name strong, .album-about p`. Each wrapped text line gets a solid block of `--ink` (window = line rect expanded by 1px, overflow hidden). After the text has been visible for **0.35 s**, a **0.95 s** sweep starts. Block i of N has delay `i/(N−1)·0.22` (in progress units). `t = clamp((p − delay)/0.78)`, `eased = t<0.2 ? 0.4·(t/0.2)² : 1 − 0.6·((1−t)/0.8)^(16/3)`, and the ink moves `translateX(eased·101%)` so it slides off to the right and uncovers the text. It runs again after each tab switch (refresh) and is skipped with reduce-motion.

---

## 6. Minimal transport (`.minimal-transport`) and transport title

Geometry, glass, and icons are in **2.7**. Behavior (music-app.ts:1463-1495, 1910, 1993-1998):
- Controls: `[#transport-track title]` `[#play-pause]` `[#stop-playback]` (stop is hidden in portrait). **There is no progress bar or time readout in the minimal transport.** Progress and time live only in the now-playing card (section 7).
- `play-pause`: if a track is loaded, toggle; otherwise `playAlbum()` (plays the selected album from track 1). aria/title: `播放` / `暂停`, title `暂停：{track}` / `播放：{track}`, or `播放当前专辑` when nothing is loaded. Playing → `aria-pressed=true` → button opacity 1 and color `--accent` (180ms). Glyph cross-fade/scale 0.7↔1, 180ms ease.
- `stop`: `player.stop()`. Afterwards there is no current track, so the title slot collapses and the card closes.
- Title slot: visible iff `currentTrack` exists. Text = `currentTrack.title`. aria-label/title `定位歌曲：{title}`. Tap → `toggle-now-playing` (open/close the card, `aria-expanded`). Opening grows the width over 640ms cubic-bezier(0.4,0,0.2,1), slides the text from x+18 to 0 over the same 640ms, and fades opacity in over 400ms ease. Track changes roll the title text (460ms reel, direction up, blur 0.2). Truncation: per grapheme + `…` to fit max width 125 (landscape) / 90 (portrait).
- Because the slot sits at the left of the right-aligned group, growing it pushes every preceding topnav control left (music-transport-title.css:1 comment). In SwiftUI, animate the slot width inside the HStack.
- Remains visible and interactive in overview mode (only the other topnav items fade).
- Reference: d2-now-playing-expanded-archive.png shows `序章 · Arrival` + an accent pause glyph + stop. e-transport-collapsed-*.png shows the collapsed state.

---

## 7. Now-playing card (`#now-playing.now-playing`, music-now-playing.css)

DOM (music-app.ts:314-328):
```
section#now-playing.now-playing [data-playing]
  .now-glass > img#now-backdrop          (blurred cover)
  .now-record   button#now-cover (56×56 cover) | button.now-metadata > strong#now-title, span#now-artist, span#now-album
  .now-progress span#now-elapsed | input#now-seek | span#now-duration
  .now-controls  previous | #now-toggle (play/pause) | next
  .now-footer   label.now-volume [speaker svg][input#now-volume][output 65%] | stop button
  p#now-error
```

### 7.1 Box (music-now-playing.css:2-15, 90)
| | landscape | portrait |
|---|---|---|
| position | abs **z 24**, `left:52%` = **620.9**, `right:18` (→1176, width **555.1**), `bottom:28` | `left:12; right:12; bottom:28` (width 810), `max-height:49%` = 585.1 |
| max-height | `calc(100% − 76px)` = 758 | 585.1 |
| padding | `14px 16px 8px` | same |
| radius | 12 | 12 |
| overflow | hidden, auto-scroll on y, contain | |
| transform-origin | `90% 0` | |

Content height ≈ 14 + 60 (record) + 4 + 48 (progress) + 64 (controls) + 48 (footer) + 8 = **246** → landscape top ≈ y 560. This matches d2-now-playing-expanded-archive.png (card y≈548…806 in pt).

### 7.2 Layers and colors
Scoped variables:

| var | day | night |
|---|---|---|
| `--now-ink` | `#292b25` | `#f4f6fb` |
| `--now-muted` | `#62675d` | `#c1c7d2` |
| `--now-soft` | `#74796c` | `#a0a9b9` |
| `--now-base` | `#ede8ddf7` | `#0b1628f2` |
| `--now-glass` | `linear-gradient(180deg, #f8f4ecf2, #eee8d9db 56%, #dfd5c0f0)` | `linear-gradient(180deg, #02050ed9, #081730b3 56%, #163c67bd)` |
| `--now-tint` (backdrop opacity) | `.22` | `.65` |
| `--now-fill` (slider fill, focus ring) | `#796346` | `#eef5ff` |
| `--now-track` | `#403b3026` | `#ffffff20` |
| `--now-thumb` | `#fffaf0` | `#fff` |
| `--now-glow` | `#d0ac7180` | `#d8eaff80` |
| `--now-glow-soft` | `#b5894a38` | `#b3d1ff38` |
| `--now-button` | `linear-gradient(145deg, #fffdf9c9, #d4c8b966 60%, #fffaf080)` | `linear-gradient(145deg, #dbeaff45, #c6daff23 60%, #d5e4ff39)` |
| `--now-button-edge` | `#fffdf5c4` | `#ffffff40` |
| `--now-error` | `#a43d27` | `#ffc6b7` |

The card has its own palette. Its night/day values switch instantly (they are not @property variables, so no 650ms tween). Bottom → top:
1. Card background `var(--now-base)`. `border:1px solid #ffffff60`. `box-shadow: inset 0 1px 0 #ffffff80, inset 0 -1px 0 #ffffff24, 0 18px 44px #0004`.
2. `.now-glass` (abs inset 0, z −1, clipped to the radius): `img#now-backdrop` = album cover, `object-fit:cover`, sized **card + 70px each way** (left/top −35), `filter: blur(24px) saturate(.9)`, `opacity: var(--now-tint)`. Hidden when there is no cover.
3. `.now-glass::after`: `background: var(--now-glass)` over the blurred cover.
4. Content.
5. `::after` overlay: `box-shadow: inset 1px 0 0 #ffffff20, inset -1px 0 0 #ffffff14` (side specular edges), radius inherited, no pointer events.
No backdrop-filter on the card (the blur is only on its own image).

### 7.3 Record row (`.now-record`)
- grid `56px minmax(0,1fr)`, gap 12, align center, min-height 60.
- `#now-cover`: 56×56, radius 6, overflow hidden, `background:#ffffff18`, `box-shadow: 0 3px 12px #0003`. Image cover-fit. Placeholder `♪` centered. Tap → `locate-playing` (closes the card, reveals the album/track in detail).
- `.now-metadata` (button, text-left, transparent; tap → collapse the card):
  - `strong#now-title`: **Demibold 600**, `clamp(20px, 2.9vw, 27px)` → **27** landscape / **24.2** portrait, line-height 1.2, margin-bottom 5, single line ellipsis, `--now-ink`.
  - `#now-artist`: 12px, line-height 1.6, `--now-muted`, ellipsis.
  - `#now-album` (album title): 10px, line-height 1.4, `--now-soft`, ellipsis.
- On open, focus moves to `.now-metadata` (music-app.ts:1414). The screenshots show its **focus ring: `outline:2px solid var(--now-fill)`, offset 3px** (the rounded brown frame around the title in d2). Same decision as 3.3: reproduce it or drop it deliberately.

### 7.4 Progress (`.now-progress`)
- grid `auto minmax(0,1fr) auto`, gap 9, align center, margin-top 4.
- Times: **11px** `--now-muted`, tabular-nums. Format `m:ss` (`time()`: floor seconds; minutes are not split into hours; negatives → 0:00). Initial text `0:00`. Elapsed updates live while scrubbing.
- `input#now-seek` (also `#now-volume`): height 48 hit area, `touch-action:pan-y`. Track **5px tall, radius 3**, `linear-gradient(90deg, var(--now-fill) var(--fill), var(--now-track) var(--fill))` (hard stop at the value fraction). Thumb **10×10 circle**, `--now-thumb`, `box-shadow: 0 0 7px 3px var(--now-glow), 0 0 17px 6px var(--now-glow-soft)`. Active: `scale(1.25)` with glow `0 0 9px 5px …, 0 0 20px 8px …`, transition transform and box-shadow 160ms ease. Disabled when duration ≤ 0. Seek commits on release (`change`), and position updates pause while dragging.

### 7.5 Controls (`.now-controls`)
- grid `minmax(48px,1fr) 56px minmax(48px,1fr)`, align center, **height 64**.
- Previous / next: transparent, padding 10, min 48×48, SVG **25×25** centered (icons `previous`/`next`, section 2.8). aria `上一首` / `下一首`.
- `#now-toggle`: **56×56 circle**, padding 12, `background: var(--now-button)`, `border:1px solid var(--now-button-edge)`, `box-shadow: inset 0 1px 1px #ffffff50, 0 2px 14px #0002`. Glyph **30×30**: play when paused, pause when `data-playing="true"` (display swap, no animation).
- Every button in the card: `:active { opacity:.7 }`, min 48×48.

### 7.6 Footer (`.now-footer`)
- grid `minmax(0,1fr) 48px`, gap 10, align center.
- `label.now-volume`: grid `18px minmax(0,1fr) 28px`, gap 8. Speaker SVG 17×17 at opacity .7. Volume slider (same style as 7.4, range 0–1, step 0.01, default **0.65**). `output` = `{round(v·100)}%`, 10px `--now-muted`, right-aligned, tabular. Volume changes save `preferences.volume`.
- Stop button: transparent, padding 14, **opacity .65**, SVG 17×17. aria `停止播放`.
- `#now-error`: margin 4 0 8, 11px, line-height 1.5, `--now-error`, hidden when empty.

### 7.7 Open/close behavior
- Opens only if a track is loaded (music-app.ts:1400-1418). `data-now-playing="true"` on the stage hides the album callout and detail content (`visibility:hidden`, android.css:110-111) while the card is up.
- Transition (music-app.ts:1392-1393): `SurfaceTransition(card, card, 320, 240, "up", default, [card], collapsedScale .94)`. **Show:** opacity 0→1, transform `translateY(10px) scale(0.94)` → `translateY(0)`, **320ms cubic-bezier(0.22,1,0.36,1)**. **Hide:** → opacity 0, `translateY(6px) scale(0.94)`, **240ms cubic-bezier(0.4,0,1,1)**. The scale pivots at `90% 0` (top-right, toward the transport). `data-now-playing` clears after the hide finishes.
- Closes automatically when playback stops (no current track).

---

## 8. Overview mode (`data-overview="true"`; music-overview.css, music-overview-ui.ts, music-overview.ts)

DOM (music-app.ts:286-291): `section#music-overview.music-overview` (abs inset 0, **z 4**, `pointer-events:none`), containing heading, `#overview-columns` (abs inset 0, projected labels), return button, and column controls.

### 8.1 Entry / exit
- Toggle: the `缩略图模式` button (2.4) or the **V** key. Only allowed in archive mode, when ready, with albums, no panel open, and boot finished (music-app.ts:539-557).
- On enter: topnav items (except the transport), the view toggle, library status, and `#runtime-info` fade (opacity 0, `translateY(-6px)`, 280ms ease / 360ms cubic-bezier(.4,0,.2,1)). The browse surface hides with its 140ms fade. The native scene runs `setMusicOverview(true)`.
- Scene progress (music-overview.ts:5-15): `damp(progress, active, 6.5, dt)` (critically damped toward 0/1, rate 6.5). Camera framing: `span = max(16.8, 17.5/aspect)`, distance 172, **yaw 28°, elevation 43°** (≈5 columns in landscape, ≈3 in portrait). Outer columns tuck in: `extent = 1 − smoother(p/0.65)·(1 − smoother(4.5 − |lane − center|))`, with `smoother(t) = t³(t(6t − 15) + 10)` (music-overview-edge.ts).
- Chrome (heading, controls, return) appears when progress > **0.12**. Column labels appear when progress > **0.75**.
- Exit: `返回近景` button, V, or 进入 on a column. The browse surface reappears after the camera returns.

### 8.2 Heading `.overview-heading` (music-overview.css:11-14, android.css:56-57,144)
- abs, landscape `left:20; top:76`, portrait `left:16; top:134`.
- `small` **`COLLECTION / OVERVIEW`**: 9px, letter-spacing .23em (2.07px), `--muted`.
- `h2` **`{sortName}浏览收藏`** → default `按流派浏览收藏` (or `按歌手名字浏览收藏` / `按专辑名字浏览收藏`): **19px Regular 400**, letter-spacing .12em (2.28px), margin 9 0, ink.
- `p` `点击列名展开入口 · 点击进入回到标准视图` is **hidden** on Android.

### 8.3 Return button `.overview-return` (music-overview.css:1-9,33; android.css:58)
- abs **z 7**, `left:20; bottom:30`, min-height 48. flex align center gap 11, `padding:9px 0`, **`border-bottom:1px solid var(--line)`**, no background, **12px** letter-spacing .06em, ink, pointer events on.
- Content: chevron SVG 16×16 `<path d="M15 5l-7 7 7 7"/>` + `返回近景` (+ kbd V, hidden). aria `返回标准视图`. Focus moves here after the entrance, so f-overview.png shows the 2px accent focus ring around it.

### 8.4 Column controls `.overview-controls` (music-overview.css:34-36; android.css:31,59-60)
- abs `right:20; bottom:30`, flex align center **gap 12**, pointer events on.
- `←` / `→` buttons: `border:1px solid var(--line)`, transparent, nominal 36×32 but **min 48×48** (android), radius 6, glyph at the inherited font size (Regular, ink). Actions genre-prev / genre-next (`stepGenre`, which also collapses any expanded label). aria `总览上一列` / `总览下一列`.
- Span `← → 切换{列名}` is hidden on Android.

### 8.5 Column label cards (projected per column; music-overview-ui.ts:105-150, music-overview.css:16-32)
- `.overview-anchor`: abs at the projected column point (x,y) from the native scene, `width: var(--overview-label-width)` = **160** (116 when width < 600), `transform: translate(-50%, -100%)` (the card sits centered above the point). Anchor opacity = column `extent`.
- `.overview-column` card: flex row, `width:max-content`, `background: color-mix(in srgb, var(--surface) 87%, transparent)` (day rgba(239,237,231,.87) / night rgba(22,34,52,.87)), **`backdrop-filter: blur(12px)`**, `border-top:1px solid var(--line)`, radius 0, pointer events on.
  - Stem `::after`: 1px vertical `--line` from the card bottom, 22px tall, at x = 80 (label center).
  - Selected column (`aria-current=true`): `border-top-color: var(--accent)` plus `box-shadow: inset 0 1px var(--accent)` (2px accent top edge).
- `.overview-column-label` button: width 160, `padding:10px 12px 9px`, min-height 48, text-left, no background.
  - `strong` column name: **12px**, weight 500 (Regular), single-line ellipsis, ink.
  - `small` caption **`{NN} / {count} 张专辑`** (NN = lane+1, 2-digit): 9px, letter-spacing .06em, margin-top 5, `--muted`.
- Enter slot `.overview-enter-slot`: collapsed `width:0; opacity:0; visibility:hidden`. Expanded (`data-expanded=true`): `width:76; opacity:1`. Transition width **420ms cubic-bezier(.4,0,.2,1)**, opacity 320ms ease, visibility delayed 420ms on collapse.
  - `.overview-enter` button **`进入 →`** (the arrow is an aria-hidden span): width 76, full height, `border-left:1px solid var(--line)`, **11px `--accent`**, nowrap, min-height 48. `translateX(-6px)` → `0` over 420ms with the same curve. Focus style `outline:1px solid var(--accent); outline-offset:-3px`.
- Interaction: tapping a label expands it (only one at a time). Tapping 进入 selects that column (the remembered album, or the album at the current depth), then exits overview. Entering never opens detail.
- Card lifetime: `SurfaceTransition(card, card, 460, 240, "up", cubic-bezier(0.4,0,0.2,1))`. Show = opacity 0→1 with `translateY(10px)→0` over 460ms. Hide = opacity→0 with `translateY(6px)` over 240ms `cubic-bezier(0.4,0,1,1)`. The heading, controls, and return button use the same transition.
- Culling (music-overview.ts:35-60): priority = expanded > selected > nearest to screen center. Skip if extent ≤ .12 (≤ .06 if already shown). Keep x within `[80 + 14, W − 80 − 76 − 34]` (retained: edge −18, right margin 14) and y within `[115, H − 112]` (retained: ±20 slack). Reject overlaps: horizontal ranges (plus 76 if expanded) within 10pt and |Δy| < 62.
- Reference: f-overview.png, f2-overview-column-expanded.png (`氛围音乐 01 / 4 张专辑` selected with accent top; `器乐` expanded with `进入 →`).

---

## 9. Panels (library / search / settings)

### 9.1 Container (music-app.ts:1587-1625, music.css:1001-1043, android.css:47-55,145-146)
```
#music-panel-root > .music-panel-scrim[data-action=dismiss-panel]
  section.music-panel[role=dialog]
    .panel-heading > div{ small, h2 } + button[close-panel] "×"
    #panel-body
```
- Scrim: abs inset 0, **z 30**, `background: rgba(4,12,19,0.25)`, **`backdrop-filter: blur(8px)`**, flex centered, `padding:12px`. Tapping the scrim outside the panel closes it.
- Panel: `background: var(--panel)` (day rgba(245,244,239,.97) / night rgba(17,27,42,.97)), `border:1px solid var(--line)`, **radius 12**, `width:min(620px,100%)` → **620** in both orientations (centered: landscape x 287…907), `max-height:100%` of the scrim content box (810 landscape / 1170 portrait), `padding:18px 22px` (portrait `18px 16px`), `overflow:auto`, `box-shadow: 0 24px 90px rgba(0,0,0,0.13)`.
- Heading: flex, align start, space-between, margin-bottom 14. `small` 9px letter-spacing 2px `--muted`. `h2` **21px** weight 500 (Regular), margin-top 7. Close `×`: 48×48, 29px, line-height 1, `--muted`.
- Titles (music-app.ts:1597-1601): library `MUSIC LIBRARY` / `本地音乐库`; search `FIND MUSIC` / `搜索专辑与歌曲`; settings `SYSTEM SETTINGS` / `播放与画质`.
- Opened by: folder icon → library, search icon or `/` key or tapping the genre name → search, settings icon → settings. Esc or Android back closes the panel.
- **Transition** `new SurfaceTransition(scrim, panel)` with defaults (ui-transitions.ts:3-22): show = scrim opacity 0→1 + panel `translateY(10px)→0`, **300ms cubic-bezier(0.22,1,0.36,1)**; hide = opacity→0 + panel `translateY(6px)`, **200ms cubic-bezier(0.4,0,1,1)**. Interrupted reversal: `max(72, d·sqrt(distance))`. Content behind the scrim is inert. Focus goes to the search input (search panel) or the first button.

### 9.2 Shared controls (music.css:1044-1296, 85-102, 2008)
| control | spec |
|---|---|
| `.panel-intro` | 12px `--muted`, line-height 1.85, margin-bottom 21 |
| `.panel-section` | `padding:20px 0; border-bottom:1px solid var(--line)`. The last one has no border and padding-bottom 0. `h3` **12px weight 500**, margin-bottom 11. `p` 11px line-height 1.9 `--muted`, margin 9 0. `a` 11px + border-bottom line, padding-bottom 4 |
| section header for `<details>` | `summary` text (e.g. `高级设置 · MusicBrainz`) uses the same row with default disclosure |
| `.settings-row` | `<label>` flex, space-between, align center, gap 20, margin 15 0, min-height 48, **12px** ink. Left `<span>` label text + optional `<small>` help (block, **9px** `--muted`, margin-top 5). Right: control |
| select | `border:1px solid var(--line); radius 6; padding:5px 10px; background:var(--surface); 11px; min-width:90`. Native appearance is kept (system chevron) |
| checkbox | `appearance:none`, **16×16**, `border:1px solid var(--line)`, radius 2, `background:var(--surface)`. Checked: background and border `--ink`, with a check mark drawn as an 8×4 box with 2px left+bottom borders in `--surface`, `translateY(-1px) rotate(-45deg)` |
| range (settings) | width **150**, height 48 hit area. Track 3px `--line` radius 2. Thumb **10×14, radius 2, `--accent`** (margin-top −5.5). Value outputs are plain text |
| text/search input | `background:var(--surface); border:1px solid var(--line); radius 6; width 100%; padding:12px 13px; 12px; line-height 1.7; color ink` |
| `.field-label` | 11px, flex space-between, margin-bottom 9. Nested span 9px muted |
| `.text-button` | 11px **`--accent`**, margin `10px 20px 0 0`, min-height 48, inline-flex align center |
| `.primary-button` | background `--ink`, color `--surface`, padding 11 18, 11px, radius 6 |
| `.panel-actions` | flex, align center, gap 20, margin-top 15, 11px |
| `.scan-status` | 10px line-height 1.8 `--muted`, padding 14 0, pre-line |
| chips `.genre-filters button` | flex wrap gap 7, margin 16 0. Each 10px, `border:1px solid var(--line)`, padding 5 10, radius 6, min-height 48. `.active` → background `--ink`, color `--surface` |
| theme cards `.theme-cards` | grid **2 columns** (music.css:2279), gap 12. Button `border:1px solid var(--line)`, padding 12, text-left, radius 6, min-height 64. Pressed → `outline:1px solid var(--ink)`. `i` swatch 48 tall, margin-bottom 10. Day `linear-gradient(135deg, #ded3bd, #f0ede4)`. Night `radial-gradient(circle at 64% 29%, #eee9df 1px, transparent 2px), radial-gradient(circle at 34% 62%, #e0deca 1px, transparent 2px), linear-gradient(135deg, #0c1728, #293b50)`. `strong` 11px/500, `span` 8px line-height 1.6 muted, margin-top 5 |

### 9.3 Library panel (music-app.ts:1626-1629)
Android-specific (MediaStore and SAF folders). Structure for reuse:
- intro `系统媒体库适合快速扫描大规模曲库；也可选择音乐文件夹导入未入库的音频。源文件与标签保持只读。`
- `.library-metrics`: grid of 3 columns, border-top and border-bottom `--line`, padding 17 0, margin-bottom 10. Each cell is a flex baseline row with gap 12: `b` **29px Light 300** (count) + `span` 10px muted. Cells: `{n} 专辑`, `{t} 曲目` (third column empty).
- `.panel-actions`: `授权并扫描设备音乐 ↗`, `添加音乐文件夹 ↗`, `取消扫描`, `权限设置` (plain 11px buttons).
- `#scan-status`: `正在扫描，已有曲库可以继续浏览…` / `上次扫描 {zh-CN datetime}` / `尚未扫描音乐目录。`
- Section `已选文件夹`: the folder list, or `尚未添加文件夹。`, then help text.
- **iPad mapping:** replace this with a Navidrome server section in the same layout: metrics, server URL/user field-labels with text inputs, a `primary-button` for connect/refresh, and scan status.

### 9.4 Search panel (music-app.ts:1662-1690, music-search.ts)
- `input#album-search` type search, placeholder **`专辑、歌曲、歌手、流派…`**. Results are debounced 120ms.
- Chips: `全部` (active by default) + one per genre that has albums.
- Result row `.album-result` (button): grid `49px 1fr 35px 14px`, gap 13, align center, padding 11 0, min-height 64, border-bottom `--line`. Cover 49×49, `background:var(--surface)`, `border:1px solid var(--line)`, image `object-fit:contain` (placeholder ♪). Copy: `strong` 12px/500 line-height 1.5 (title), `small` 10px muted margin-top 3 (album: `{artist} · {genre}`; song: `{track artist} · {album title}`). `em` kind `专辑` / `歌曲` 10px muted, normal style. `i` `↗` 17px. Hover/press → accent.
- Tapping an album result reveals the album. Tapping a song result reveals the album in detail and highlights that track (without playing).
- Empty: `.no-results` `没有找到专辑或歌曲。` 12px muted, centered, padding 45 0. Cap: `显示前 120 项，请细化关键词缩小范围。`

### 9.5 Settings panel, all rows in order (music-app.ts:1692-1712; change handlers :2102-2205, input handlers :2063-2101)
Persisted under localStorage `rhinedroid-preferences` (falls back to legacy `rhine-music-preferences`). Defaults are from music-app.ts:118-144 after normalization at :182-203.

| section h3 | label / help (`small`) | control | pref key | default |
|---|---|---|---|---|
| 外观主题 | theme cards: `暖昼` / `暖白玻璃与日光`, `深夜` / `极简星空与透光白卡` | 2 theme cards | `theme` | `"day"` |
| 音乐库排列 | `排列方式` / `切换后重新载入界面` | select: `按流派` (genre), `按歌手名字` (artist), `按专辑名字` (album). Change reloads the page | `sortMode` | `"genre"` |
| 专辑介绍 | text-button `取消资料查询`. p `从公开百科查询并更新专辑介绍，附上资料来源。介绍保存在本机，音乐文件不会上传。` + coverage p + primary `查询 / 更新专辑介绍 ↗` + `<progress>` (3px, accent) + status | buttons | — | — |
| 制作信息 | p `从 QQ 音乐核对曲目的参与人员，在姓名下方注明来源。批量查询按来源限速排队，可随时取消。保留本地标签与已有资料，查询结果保存在本机。` + primary `查询缺失的制作信息 ↗` + progress + status | buttons | — | — |
| 高级设置 · 专辑阵列 | `专辑列显示` (no help) | select `填充画面` (filled) / `真实专辑列` (realistic). Then p `真实专辑列：各列独立居中；上下浏览到本列首尾时停止。` | `arrayMode` | `"filled"` |
| | `保留每列浏览位置` / `关闭后保持画面深度，选中邻近专辑` | checkbox | `rememberColumnPosition` | `true` |
| 原生音频输出 | `偏好输出设备` / `实际路由由 Android 和设备能力决定` | select (device list) + text-button `刷新输出设备 ↻` + p `Media3 原生解码与系统音频焦点；不会改变系统音量或请求独占输出。` | `outputDeviceId` | `"default"` |
| RENDER QUALITY 渲染画质 (`.quality-settings`, see below) | preset select | select `清晰均衡` (balanced) / `性能` / `原始` (original) / `高` / `极高` + disabled `自定义` | `quality` (+ `renderQuality`) | `"balanced"` → {scale 100, pixelRatio 1.5} |
| | `精细设置` summary `<span>清晰度</span>` (Vulkan) → `渲染比例` / `相对屏幕像素，受密度上限限制；高比例改善细线` | range 50–200 step 5 + `{v}%` output | `renderQuality.scale` | 100 |
| | `像素密度上限` / `控制高密度屏幕的原生像素倍率` | select `1×` `1.5×` `2×` `3×` | `renderQuality.pixelRatio` | 1.5 |
| | note (Vulkan) `Vulkan GPU 实例化 · 固定 FXAA 与轻量玻璃材质。渲染比例和像素密度即时生效。`; summary line `渲染 {scale}% · 像素上限 {pr}× · Vulkan · FXAA` | | | |
| 焦点层次 (Vulkan only) | `轻度景深与边缘高光` / `选中专辑及附近保持清晰，向远处逐渐柔化`, then p `默认开启，可关闭对照。` | checkbox | `focusDepth` | `true` |
| 实验性画面 · RC (only with `?optics=rc`) | `柔光与景深` / `边缘柔光与远近虚化，保留文字清晰`, then p `默认关闭，可即时对比；开启后会增加 GPU 开销，流畅度下降时关闭即可。` | checkbox | `experimentalOptics` | `false` |
| 专辑光带 | `强度` (0–2 step .05), `宽度` (.6–2.5 step .05), `位置偏移` (−6–6 step .1), `补光` (0–1 step .05), `跟随时间` (.4–2.4 step .1). Label only, no help or value output | 5 ranges | `lighting.{strength,width,offset,fill,transitionDuration}` | `DEFAULT_LIGHTING_PRESET` (music-row-lighting.ts) |
| 动效与显示 | `减少动态效果` | checkbox → toggles `.reduce-motion` (every animation and transition becomes ~0.001s) | `reduced` | `false` |
| | `动画速度` / `专辑、镜头、文字与光带同步；不改变歌曲或片头速度` | range 0.25–3 step 0.05 + output `{v.toFixed(2)}×` | `motionSpeed` | `1` (scale = 1/speed) |
| | `静置轻微浮动` / `沿用原版微幅运动，开启后持续渲染` | checkbox | `idleMotion` | `false` |
| | text-buttons `切换当前方向全屏 ↗`, `重播开场 ↗` (closes the panel and replays boot), `重新载入界面 ↻` | | | |
| 声音 | `歌曲音量` | range 0–100 | `volume` (0–1) | `0.65` |
| | `歌曲衔接` / `选择切换歌曲时的音量过渡` | select `淡出但不淡入` (fade-out) / `淡出淡入` (fade-in-out) / `无缝播放` (gapless) | `songTransition` | `"fade-in-out"` (legacy `songFade:false` → gapless) |
| | `界面音效` / `玻璃卡片与终端操作` | checkbox | `sound` | `false` |
| | `音效音量` | range 0–100 | `soundVolume` | `0.22` |
| | `氛围 BGM` / `专辑开始前淡出，停止后淡入` | checkbox | `bgm` | `false` |
| | `BGM 音量` | range 0–100 | `bgmVolume` | `0.18` |
| | text-button `试听界面音效 ↗`, then p `歌曲和氛围音乐由原生服务播放，界面音效独立控制。手动切歌每段淡变约 450ms；曲尾交给 Media3 连续排程。不同格式、采样率或输出设备可能产生间隙，保留文件自带静音。` | | | |
| `<details>` 高级设置 · MusicBrainz | p `向 MusicBrainz 查询专辑名称与艺术家，补充流派和制作人员；音乐文件留在本机。已有资料使用缓存，人工分类优先保留。` + `补充缺失的在线资料 ↗` + `#online-config` (`资料库连接`: field `资料查询联系邮箱或项目网址`, row `扫描后自动补充新专辑资料` / `已有缓存不重复查询；断网仍可浏览与播放` checkbox, `保存资料库设置 ↗`) | | server-side config | |
| 诊断与日志 | `导出运行日志 ZIP ↗` + p `保存设备信息、渲染状态与近期错误记录，不打包音乐和封面。错误记录可能包含文件名，请按需分享。` + `复制性能诊断 ↗` + p `RhineDroid · {version}<br>设备曲库 · 原生音频 · Vulkan GPU 渲染。` + p `音乐界面：RonaldDeng<br>原版界面：LBEILC / RhineLabUI` + p links `上游项目 ↗` · `代码许可 ↗` | | | |

Hidden or forced preferences: `developerMode` and `motionDebug` are forced to false. `audioBackend` is forced to `"browser"`. `outputDeviceId` defaults to `"default"`.

Quality block in a panel (quality-settings.css + music.css:1964-2010): `.quality-settings` margin-top 20, border-bottom `--line`. Heading flex space-between gap 12: `h3` 10px weight 400 letter-spacing 0.8px `RENDER QUALITY` + span `渲染画质` (margin-left 7, muted, letter-spacing 0). Preset select 11px, radius 6, surface background, line border, `padding:9px 28px 9px 12px`, min-width 125. Summary 12px muted tabular, margin 12 0 20. `summary` 12px, padding 15 0, border-top line, span 11px muted margin-left 16. Grid is 1 column. `.quality-control`: flex space-between, gap 18, padding 15 0, border-top line, 11px. `small` 10px muted margin-top 7 line-height 1.5. Range width 150 + output min-width 44, 12px. Note 11px line-height 1.8 muted, margin 12 0 18.

### 9.6 Toast and loading (music.css:1307-1358)
- Toast `#music-toast`: abs `bottom:24; left:50%`, z 50, `background:var(--ink)`, `color:var(--surface)`, 11px line-height 1.7, padding 12 18, `max-width:min(580px, 85vw)`, `box-shadow: 0 8px 24px #0002`, radius 0. Hidden: opacity 0, `translate(-50%, 8px)`. Visible: opacity 1, `translate(-50%, 0)`, 0.2s. Auto-hides after 5.5 s.
- Loading `#music-loading`: abs inset 0, z 40, `background:var(--page-bg)`, flex column centered, gap 14. Orbit 42×42 circle, `border:1px solid var(--line)`, `border-top-color:var(--accent)`, rotate 360° every 1.5s linear, margin-bottom 12. `strong` `OPENING THE ARCHIVE` 11px letter-spacing 3px weight 500. `small` `正在载入三维专辑架` (later `正在准备渲染器与专辑封面…`) 10px muted.

---

## 10. Boot / opening (music-boot.ts, music-opening.ts, music-boot-timing.ts, music-boot.css)

### 10.1 Overlay and lifecycle
- Starts once the scene is ready, unless reduce-motion is on or `?intro=0` is set (music-app.ts:2514-2516). Otherwise the archive shows at once via `showMusicArchiveImmediately` plus the browse fade. It can be replayed from settings (`重播开场 ↗`).
- `section.music-boot-overlay`: abs inset 0, **z 900**, transparent, a focusable dialog (aria `音乐开场：一张一张，慢慢听`). Every stage sibling except `.three-scene` is set inert and `visibility:hidden`. That includes the header and its brand, so **no top bar is visible during the film** (confirmed by i-boot-*.png).
- **Skip:** Esc or Enter on the overlay, or Android back (`handleAndroidBack` → `boot.skip()`). Skip calls `scene.showMusicArchiveImmediately`. Normal completion calls `scene.finishMusicIntro`. Both then run the UI reveal (10.5).
- Clock (music-boot-timing.ts:17-36): app time starts at 0. Each frame adds `min(dt, 0.05 s)`, so stalls are discarded rather than fast-forwarded. It clamps at `END = 4 + 5.2/1.3 = ` **8.0 s**. The frame after the end frame renders triggers `finish("complete")`.

### 10.2 Constants and the native scene mapping
```
MUSIC_BOOT_START_TIME        = 0
MUSIC_BOOT_SCENE_REVEAL_TIME = 3.92   // renderScene = appTime >= 3.92 (paper starts dissolving)
MUSIC_BOOT_SCENE_START       = 4
MUSIC_BOOT_SCENE_TIME        = 21.92
MUSIC_BOOT_SCENE_SPEED       = 1.3
MUSIC_BOOT_END_TIME          = 4 + 5.2/1.3 = 8.0
sceneTime(t) = 21.92 + max(0, t - 4) * 1.3      // t=4 → 21.92, t=8 → 27.12
cinema.reveal = smoothstep((sceneTime - 21.9) / 0.13)   // smoothstep = t²(3−2t), clamped; full by scene 22.03 (app ≈ 4.085)
cinema.lift = 0, zoom = 0, musicIntro = true
phase = sceneTime >= 25.68 ? "select" : opening phase   // 25.68 ↔ app 6.892
```
Feed the native renderer `sceneTime` (21.92 → 27.12 over app 4.0 → 8.0, ×1.3 speed). Before app 3.92 the scene does not need to render because the opaque paper covers it.

### 10.3 Timeline (music-opening.ts:12-35). `unit(t,a,b)` = clamp((t−a)/(b−a)), `smooth` = t²(3−2t), `settle` = 1−(1−t)³
| track | formula | effect |
|---|---|---|
| phase | `logo` t<1.8 · `orbit` <2.64 · `slogan` <4 · `array` ≥4 (· `select` once scene ≥ 25.68) | |
| paper opacity | `1 − smooth(unit(t, 3.92, 4.38))` | the overlay is hidden once it reaches 0 |
| mark opacity | `smooth(unit(t,0.2,0.48)) · (1 − smooth(unit(t,1.8,2.26)))` | |
| contour draw | `settle(unit(t,0.24,1.64))` → `stroke-dasharray: {v} 1` on pathLength 1 | the infinity contour draws on |
| symbols (+ − −) opacity | `settle(unit(t,0.84,1.5))` | |
| orbit opacity | `smooth(unit(t,1.64,2.05)) · (1 − smooth(unit(t,2.78,3.28)))` | |
| orbit draw (outer circle) | `settle(unit(t,1.64,2.82))` dasharray | |
| orbit rotation | `190° · smooth(unit(t,1.64,3.3))` about (260,260) | |
| orbit scale | `0.9 + 0.1·settle(unit(t,1.64,2.8))` | applied as `translate(-50%,-50%) scale(s)` |
| slogan opacity | `titleIn·(1−titleOut)`, titleIn = `settle(unit(t,2.64,3.02))`, titleOut = `smooth(unit(t,3.58,4))` | |
| slogan translateY | `18·(1−titleIn) − 8·titleOut` px | rises 18→0, then lifts −8 |
| slogan clip | `clip-path: inset(0 0 {100·(1−titleIn)}% 0)` | revealed from top to bottom |
| subtitle opacity | `smooth(unit(t,2.82,3.16)) · (1 − smooth(unit(t,3.56,4)))` | |

Reference frames: i-boot-t0.32/t1.02 (logo), t1.82/t2.62 (orbit), t3.42/t3.97 (slogan), t4.52/t5.23/t6.02 (array), t7.02/t7.92 (select), i-boot-settled.

### 10.4 Layers (music-boot.css, music-opening.ts:43-52). All color `--ink`
- **Paper** `.music-opening-paper`: inset 0, `radial-gradient(ellipse at 51% 44%, var(--page-bg) 0%, var(--surface) 100%)`.
- **Mark** `.music-opening-mark`: abs center (`left:50%; top:50%; translate(-50%,-50%)`), `width: clamp(320px, 40vw, 560px)`, max `100% − 40px` → **477.6** landscape / **333.6** portrait. SVG aspect 856/192 (height 107.1 / 74.8). Verbatim SVG:
```html
<svg viewBox="0 64 856 192" aria-hidden="true"><g transform="translate(80 78) scale(1.15)"><path data-opening="contour" d="M295 73C295 41 273 15 240 15C221 15 207 23 192 38C186 43 181 47 176 52C127 96 103 128 70 128C38 128 15 101 15 70C15 39 37 15 70 15C103 15 127 48 156 75C182 99 208 128 240 128C273 128 295 105 295 73Z" pathLength="1" fill="none" stroke="currentColor" stroke-width="18"/><g data-opening="symbols" fill="none" stroke="currentColor" stroke-width="11"><path d="M44 70h50M69 45v50M219 70h44"/></g></g><g class="music-opening-android" transform="translate(476 8) scale(13)" fill="currentColor"><path d="M17.6,9.48l1.84-3.18c0.16-0.31,0.04-0.69-0.26-0.85c-0.29-0.15-0.65-0.06-0.83,0.22l-1.88,3.24 c-2.86-1.21-6.08-1.21-8.94,0L5.65,5.67c-0.19-0.29-0.58-0.38-0.87-0.2C4.5,5.65,4.41,6.01,4.56,6.3L6.4,9.48 C3.3,11.25,1.28,14.44,1,18h22C22.72,14.44,20.7,11.25,17.6,9.48z M7,15.25c-0.69,0-1.25-0.56-1.25-1.25 c0-0.69,0.56-1.25,1.25-1.25S8.25,13.31,8.25,14C8.25,14.69,7.69,15.25,7,15.25z M17,15.25c-0.69,0-1.25-0.56-1.25-1.25 c0-0.69,0.56-1.25,1.25-1.25s1.25,0.56,1.25,1.25C18.25,14.69,17.69,15.25,17,15.25z"/></g></svg>
```
  Contour stroke caps and joins use the SVG defaults (butt/miter). The Android head has no animation of its own and follows the mark opacity. Below it, `span` **`RhineDroid`**: block, margin-top 17, centered, **10px Demibold 600**, letter-spacing .3em (3px).
- **Orbit** `.music-opening-orbit`: `left:50%; top:48%`, square, `width: min(66vh, 54vw, 520px)` → **520** landscape. Portrait (`max-aspect-ratio:1/1`) uses `min(86vw, 500px)` → **500**. Verbatim SVG:
```html
<svg viewBox="0 0 520 520" aria-hidden="true"><g data-opening="orbit-turn" fill="none" stroke="currentColor" stroke-width="1.2"><circle data-opening="orbit-line" cx="260" cy="260" r="236" pathLength="1"/><circle cx="260" cy="260" r="207" stroke-dasharray="142 91 380 95"/><circle cx="260" cy="24" r="4" fill="currentColor" stroke="none"/><circle cx="260" cy="496" r="4" fill="var(--accent)" stroke="none"/></g><path d="M252 260h16M260 252v16" stroke="currentColor" stroke-width="1.1"/></svg>
```
  The fixed center crosshair does not rotate. The bottom dot is `--accent`.
- **Statement** `.music-opening-statement`: `left:20; right:20; top:48%; translateY(-50%)`, centered.
  - `p` slogan **`一张一张，慢慢听`** (full-width comma): `font-size: clamp(23px, 3.35vw, 48px)` → **40.0** landscape. Portrait uses `clamp(18px, 5.75vw, 32px)` → **32**. Weight 450 → MiSans Regular. letter-spacing **.045em** landscape / **.015em** portrait. line-height 1.5, padding 5 0, nowrap.
  - `span` **`ONE ALBUM AT A TIME`**: margin-top 24, 9px, letter-spacing .3em, `--muted`.

### 10.5 Hand-off reveal (music-boot.ts:162-202)
After finishing, the overlay stays up (`data-music-boot="revealing"`, input blocked) while the real UI fades in with **720ms `cubic-bezier(0.22,1,0.36,1)`** (duration = 720 − delay, fill both):

| target | animation | delay |
|---|---|---|
| `.music-vignette`, `.music-identity`, `.music-topnav` | opacity 0 → current | 0 |
| `.library-status` | opacity | 45 ms |
| `.music-empty` | opacity | 60 |
| `.music-bottomline` | opacity | 90 |
| `.music-counter`, `.album-stepper`, `.genre-stepper` | opacity | 110 |
| `.album-callout` | `translate: 0 8px` → 0 | 60 |
| `.music-keyhint` | translate | 140 (hidden on Android) |

In parallel, `showBrowseSurface()` runs the browse fade (veil/callout/navigation: opacity over 720ms `cubic-bezier(0.45,0,0.25,1)`, see 3.7). When all animations finish, `data-music-boot="done"` and focus returns to the open-album button.

---

## 11. Gestures and keyboard

### 11.1 Touch on the 3D scene (native-archive-scene.ts:60-86, viewport-layout.ts:49-55, music-app.ts:2496-2505)
- Single primary pointer, captured on down.
- **Swipe** (archive mode, on pointer up): `major = max(|dx|,|dy|)`, `minor = min(…)`. Valid if `major ≥ 36`, `major ≥ 1.3·minor`, and elapsed ≤ **1400 ms**. Horizontal → axis `lane` → `stepGenre`. Vertical → axis `row` → `stepAlbum`. Direction = `(dominant delta) < 0 ? +1 : −1`: **swipe left = next column, swipe right = previous; swipe up = next album, swipe down = previous.** Ignored during boot, with a panel open, or outside archive mode.
- **Tap** (movement < 12 pt, no swipe): `scene-pick` at normalized (x,y). The picked album becomes selected (`select(index, {cell})`) and overview exits if active.
- **Detail mode drag:** horizontal movement rotates the card, `rotation = clamp((x − x0)·0.008, −1.1, 1.1)` rad, sent once per animation frame (`scene-drag`). Release does not navigate. Caption hint: `拖动卡片，查看完整封面`.
- **Wheel / trackpad** (music-wheel-navigation.ts): archive mode only, when the column has more than 1 album and no panel is open. Ignored if `|dx| ≥ |dy|`, ctrl/shift is held, or the target is an input, button, link, dialog, slider, panel scrim, `#music-detail`, or any scrollable element. Steps: accumulate `deltaY` (line mode ×16, page mode ×page height), each event clamped to 144, **48 pt per album**. Resets after a 200 ms gap, a direction change, a column change, pointerdown, keydown, or blur. Positive deltaY means the next album.
- Detail track list and panels scroll natively (`overscroll-behavior: contain`).

### 11.2 Keyboard (music-app.ts:2206-2291). Ignored during boot (the boot overlay handles Esc/Enter = skip) and while the model viewer is open
| key | action |
|---|---|
| `Esc` | back stack (`handleAndroidBack`, :2569-2577): skip boot → close panel → close now-playing → exit overview → detail→archive |
| `Tab` (panel open) | focus trap inside `#music-panel-root` |
| `←` `→` / `Home` `End` on a focused tab | toggle between 歌单 and 专辑介绍 / first / last tab |
| `/` | open the search panel |
| `V` (no modifiers) | toggle overview |
| `←` / `→` | previous / next column (`stepGenre`) |
| `↑` / `↓` | previous / next album in column (`stepAlbum`) |
| `Enter` (target not a button/link) | open detail |
| `Space` (target not a button/link) | play/pause, or play the selected album if nothing is loaded |
Keys are ignored while typing in an input, textarea, select, or contenteditable. With a panel open, only Esc and Tab apply.

### 11.3 Android back (and an iPad equivalent)
The same `handleAndroidBack` order as Esc. Suggested iPad mapping: an edge-swipe or back gesture, plus hardware keyboard Esc.

