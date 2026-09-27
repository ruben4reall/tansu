# Captures and numbers the site still needs

Every picture of Tansu on the site is a real capture of the app. Until each one exists, its slot holds a placeholder drawn by `node tools/placeholders.mjs`: a neutral skeleton marked inside the PNG with the text `tansu-placeholder`. The tool never overwrites a real picture, and `TANSU_RELEASE=1 node --test tests/*.test.mjs` fails while a placeholder or an empty number is left.

## How to capture

1. Build the Debug app (`scripts/build.sh`) and use demo mode: generic icons, a tinted floating bar, two profiles and three triggers, and nothing in your own menu bar moves.
2. Pass the options as separate arguments (in zsh, an array: `"${OPTIONS[@]}"`, never one string): `-TansuDemo YES -TansuBackdrop <picture> -AppleLanguages '(en)' -AppleLocale en_US -AppleAccentColor 99`, then one of `-TansuSettingsPane <pane>`, `-TansuWelcomeStep 2`, `-TansuOpenDrawer 0` or `all`, `-TansuSearch cl`. `-AppleAccentColor 99` shows the app's own accent, as on a Mac left with the default Multicolor accent.
3. Windows: click once on the title bar so the window draws as the one in front, then capture it by window ID, without the system shadow: `screencapture -x -o -l <window id> <name>@2x.png`. Panels (drawers, search) take `-TansuQuiet YES` and need no click. Never the whole screen.
4. Make the 1x file from the 2x one: `sips --resampleHeightWidth <h/2> <w/2> <name>@2x.png --out <name>.png`.
5. `drawer-files` is cropped to the glass (44 pixels off each side of the 2x capture): the hero draws its own shadow.
6. Keep the file names. If a capture comes out at another size, change the `width` and `height` of its `<img>` in `index.html` to the 1x size: the tests compare all three.
7. Run `node --test tests/*.test.mjs` and `node tools/audit.mjs`.

## Pictures of the app

| File, with its @2x twin | Size at 1x (px) | Where on the page | What it shows |
|---|---|---|---|
| `assets/app/drawer-files.png` | 280 × 125 | Hero: it drops under the cloud drawer's icon | The Files & Cloud drawer's glass alone, two icons with their names. |
| `assets/app/welcome-sort.png` | 680 × 632 | Smart Sort | The welcome at its Smart Sort step: "Tansu found 16 icons", By Purpose selected, the drawers proposed, Sort My Menu Bar. |
| `assets/app/drawer-all.png` | 456 × 525 | Drawers, left | The All drawer: one row per drawer, its mark and name, its icons. |
| `assets/app/search.png` | 604 × 233 | Drawers, right | Search with "cl" typed and three results, the first one selected. |
| `assets/app/settings-profiles.png` | 960 × 700 | Profiles and triggers, left | Settings at Profiles: Laptop (active) and Desk. |
| `assets/app/settings-triggers.png` | 960 × 700 | Profiles and triggers, right | Settings at Triggers: the three demo triggers. |
| `assets/app/settings-layout.png` | 960 × 700 | Settings, left | Settings at Layout: the menu bar with the notch, the room beside it, the space between icons, the drawers' cards. |
| `assets/app/settings-appearance.png` | 960 × 700 | Settings, right | Settings at Appearance: Floating, a gradient, the hairline and the soft shadow over the live preview. |

## Brand pictures

| File | Size (px) | Where | What it is |
|---|---|---|---|
| `assets/brand/favicon-32.png` | 32 × 32 | Browser tab | The app icon at 32 pixels (`brand/icon-previews/default-32.png`); `node tools/placeholders.mjs` rebuilds `favicon.ico` from it. |
| `assets/brand/apple-touch-icon.png` | 180 × 180 | Home screen of a phone | The app icon on an opaque Night square, rendered with `brand/scripts/render-html.sh`. |
| `assets/brand/og.png` | 1280 × 640 | Link previews | `docs/brand/social-preview.png`: the icon, the wordmark and "Your menu bar, in drawers." |
| `assets/brand/wordmark.svg` | 20 px high on the page | Nav and footer | `brand/wordmark/tansu-wordmark-rice.svg`. |

## Numbers to measure

| Slot in `index.html` | Where | How |
|---|---|---|
| `data-slot="memory-at-rest"` | Your Mac, Light on your Mac (the FAQ refers to it) | `scripts/bench.sh` on the MacBook Pro 14 with macOS 26.5: the memory footprint after one idle minute, in whole MB. Replace the `…` and name the Mac in a line under the four figures, as Pli does. |

## Also check before publishing

- The macOS 27 card keeps "Beta" until Tansu has run on macOS 27.
- The comparison table is dated September 2026; every "Not verified" is an invitation to check and correct.
- The GitHub links point to `main`: `LICENSE`, `Packages/TansuKit`, `PrivateAPI.swift`, the `Tests` folder and `Catalog.json` must exist there when the repository becomes public.
- `appcast.xml` is an empty feed until the first release writes its item.
