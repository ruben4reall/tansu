# Security

Tansu runs only on your Mac. This page says what it touches, what it never does, how those promises are checked, and how to report a problem.

## What it touches

| Where | What Tansu does there |
| --- | --- |
| Accessibility | The one permission Tansu asks for, to see which app owns each icon and to open icons for you. Through it, Tansu reads the menu bar items of running apps and of macOS (their owner, position, identifier and label) and presses an item to open its menu. It reads nothing else: no window, no text you type. Without the permission, Tansu shows its drawers and Settings and moves nothing. |
| Other apps' bundles | Read only, for the apps that own menu bar icons: the name, the icon and the declared App Store category, and the organization named in the app's Developer ID signature (Smart Sort's *By developer*). Nothing is written there. |
| The window list | On macOS 26, the position, size, owner and number of the menu bar's windows, from `CGWindowListCopyWindowInfo`, which needs no permission. It gives no picture: Tansu never asks for Screen Recording. |
| Synthetic mouse events (macOS 26) | macOS 26 has no function to move another app's icon, so Tansu moves it the way you would: a Command-drag, posted as synthetic mouse events that carry the icon's window number. Tansu does this only when it arranges the menu bar (a layout applied from the welcome or from Settings, a new icon sorted into its drawer, Focus turned on or off) and when you open a hidden icon from a drawer: the icon comes next to the drawer's icon, its menu opens, and it goes back once the menu closes. The pointer is hidden during a move and put back where it was. Nothing moves while a mouse button or a modifier key is down, or within 0.15 s of your own pointer movement: Tansu waits, and gives up after two seconds rather than interfere. An icon whose app does not answer the Accessibility press gets a synthetic click instead. |
| The order of other apps' icons (macOS 26) | Changed only by those Command-drags, so each app remembers its icon's new place the same way it does after one of your own drags. Tansu writes nothing in other apps' preferences. |
| MenuBarAgent's restriction (macOS 27) | macOS 27 draws the whole menu bar in one agent, MenuBarAgent, and the only way for another app to take icons out of it is the restriction behind exam mode, from the private `MenuBarClientCore` framework. While any icon is out of the menu bar (in a drawer or hidden), one restriction is active: it lets through every running app except those whose icons you put in a drawer or hid, plus Tansu and the Apple agents that draw system icons. When every icon is in the menu bar, no restriction is active, and MenuBarAgent drops it by itself when Tansu quits or crashes. Its side effects come from macOS: while it is active, the menu bar shows neither the status of macOS Focus modes (such as Do Not Disturb) nor the camera and microphone indicators, and a click on the clock would not open Notification Center. So Tansu lifts the restriction while the pointer rests on the clock (the hidden icons show for that moment) and puts it back half a second after the pointer leaves. The green light next to the built-in camera does not depend on the menu bar and still turns on. On macOS 27 Tansu must run from `/Applications`, because MenuBarAgent only honours apps there. |
| The pointer's position (macOS 27) | A global mouse-move monitor tells Tansu when the pointer reaches the clock. It is active only while the restriction is, needs no permission, and sees where the pointer is, never a click or a key. |
| Clicks outside a drawer | While a drawer or the search field is open, a global monitor notices a click elsewhere, to close it. It learns only that a click happened. |
| `~/Library/Preferences/ch.rubencatalao.tansu.plist` | Your settings, as one JSON value: the drawers, where each icon goes, the appearance and the shortcuts. AppKit also keeps there the positions of Tansu's own menu bar items. An unreadable value falls back to the defaults. A Debug build, made from source, uses `ch.rubencatalao.tansu.debug.plist` instead. |
| `~/Library/Caches/ch.rubencatalao.tansu` and `~/Library/HTTPStorages/ch.rubencatalao.tansu` | Sparkle's downloaded update, until it is installed, and the storage macOS creates for the update check. |
| Login Items | When Open at Login is on (the welcome turns it on; turn it off there or in Settings, General), through `SMAppService`. It shows in System Settings, General, Login Items. |
| Keyboard shortcuts | ⌃⌥⌘Space (search), ⌃⌥⌘F (Focus) and any you record are registered with `RegisterEventHotKey`. No event tap, no Input Monitoring, no keyboard monitoring. |
| The system log | Numbers, states and bundle identifiers, under the subsystem `ch.rubencatalao.tansu`. Never a window title, an icon's label or a path. |
| Private macOS functions | Two, both in `PrivateAPI.swift` and looked up at run time: on macOS 27 the restriction above (`MBAssessmentModeConfiguration` and `MBAssessmentModeAssertion`), and on macOS 26 a SkyLight connection property that lets Tansu hide the pointer while another app is in front. A missing one turns its feature off with a sentence in Settings; nothing crashes. The [README](README.md#private-macos-apis) says why each is needed. |
| The network | Only Sparkle's update check, which you can turn off in the welcome or in Settings, General: it reads `https://gettansu.vercel.app/appcast.xml` and downloads updates from GitHub Releases. The request says which version of Tansu asks, like any update check; Sparkle's system profile is off. |

## What it never does

- No picture of the screen, ever: Tansu never asks for Screen Recording, and drawers show each app's icon from its bundle.
- No keyboard monitoring and no Input Monitoring permission.
- No telemetry, analytics or crash reports. No account.
- No network connection other than the update check above.
- Nothing written in other apps' preferences or in system settings.
- No icon lost: when Tansu quits, crashes or loses its permission, every icon comes back to the menu bar.
- On macOS 27, the pointer never moves.

## How the promises are checked

- Guard tests (`GuardTests`) run with every test run: no networking API outside `App/SparkleUpdater.swift`, Sparkle only in that file and as the one external dependency, no analytics library, no screen capture API anywhere in the shipped code, and private functions only in `PrivateAPI.swift`.
- The engine tests (`TahoeEngineTests`, `GoldenGateEngineTests`) drive both engines against a simulated menu bar: restoring the menu bar shows every icon (on macOS 26, so does losing the permission), nothing moves while you use the pointer, the restriction lifts over the clock and ends when every icon is back in the menu bar, and nothing is hidden outside `/Applications` on macOS 27.
- `scripts/tests/test-update-settings.sh` checks the update settings the app ships with: an HTTPS feed, a 32-byte EdDSA key, a signed feed, verification before extraction, no system profile.
- Updates are signed twice: with Tansu's EdDSA key, which Sparkle checks before it opens the disk image (and the release scripts check against the published file), and with a Developer ID, notarized by Apple.
- Releases are built with the hardened runtime and notarized, and the disk image carries Apple's ticket. `scripts/release.sh` refuses a build in which any executable is not signed by the team with the hardened runtime.

## Reporting a vulnerability

If you find a way in which Tansu could capture the screen, see what you type, connect somewhere it should not, run something it should not, lose an icon, or break one of the promises above, please report it privately: use "Report a vulnerability" on the Security tab of the repository. You will get an answer within a week, and a fix before any public disclosure.
