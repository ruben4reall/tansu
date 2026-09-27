# Changelog

Every release of Tansu. Versions follow semantic versioning; each one is signed, notarized, and offered to installed copies through Sparkle.

## 1.0.0 (2026-09-28)

Tansu 1.0: your menu bar, in drawers. Free and open source, for macOS 26 Tahoe and macOS 27.

### New

- **Drawers.** Tansu sorts the icons on the right of the menu bar into drawers, each shown as one icon drawn like macOS's own menu bar icons, from a library of 390 by theme (or an emoji, or a few letters), with its name and count if you like. A click drops a glass panel with the drawer's icons, and a click on an icon opens its own menu. Arrow keys, Return, Escape and typing work in every drawer, and a right-click moves an icon to another drawer, keeps it in the menu bar or hides it.
- **Smart Sort.** One click proposes drawers by purpose (files and cloud, security, messages, AI, developer tools, music and video, devices, and more) or by developer, shown as a preview of your menu bar that you adjust before it applies. Clock, Control Center, Battery, Wi-Fi and Sound stay in view. New icons join their drawer, stay in the menu bar or hide, as you choose.
- **Menu bar and Hidden.** Keep in the menu bar the icons you look at all the time, and hide the ones you never need to see: they stay one search away, and in the All drawer.
- **Search.** ⌃⌥⌘Space opens a field under the menu bar: two letters and Return open any icon's menu.
- **Show everything.** A click on Tansu's icon opens every drawer and every hidden icon at once; an Option-click brings every icon back to the menu bar until the next click.
- **Focus.** ⌃⌥⌘F leaves only the clock and Control Center, for a presentation or a screen share, and brings everything back.
- **Notch aware.** Settings draws your menu bar at its real size, notch included, measures the room left beside it, says when icons no longer fit, and moves the overflow into a drawer in one click.
- **Appearance.** A tint for the menu bar (a color or a gradient), a hairline border and a soft shadow, previewed live, in three shapes: full width, a floating bar, or split in two, one piece behind the app menus and one behind the icons, on each side of the notch on a MacBook. Dark Mode can have a look of its own, which the menu bar takes as soon as the Mac switches.
- **macOS 26 and macOS 27.** On macOS 26 Tansu moves icons with the same Command-drag you would use. On macOS 27 it asks the menu bar to leave hidden apps out, and runs from the Applications folder; Settings says which engine runs and what macOS 27 does not allow. Support for macOS 27 is marked beta until it has been tried on a Mac running it.
- **Nothing lost.** Quit Tansu, or let it crash, and every icon is back in the menu bar.
- **One permission.** Accessibility, and nothing else: no Screen Recording, no Input Monitoring. Without it, Tansu says so plainly and moves nothing.
- **Private.** No telemetry, no account. The only connection is the update check, which you can turn off.
- **Native.** A four-step welcome, a dark Settings window in the manner of System Settings, Open at Login, shortcuts you can record for search, Focus, the All drawer and each drawer, and respect for Reduce Motion, Reduce Transparency and Increase Contrast.
- **Updates.** Sparkle checks for new versions, signed with Tansu's EdDSA key and notarized by Apple. Homebrew: `brew install --cask ruben4reall/tap/tansu`.
