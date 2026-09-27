# Contributing to Tansu

Thank you for looking at this. Tansu is small, native and careful; contributions that keep it that way are welcome.

## The promises that cannot change

- One permission: Accessibility. Tansu never asks for Screen Recording or Input Monitoring.
- No screen capture. Drawers show each app's own icon, read from its bundle; nothing on the screen is ever photographed.
- No telemetry, no analytics, no crash reporter. The only network code is Sparkle's update check, in `App/SparkleUpdater.swift`.
- Private macOS functions live in one file, `Packages/TansuKit/Sources/TansuSystem/PrivateAPI.swift`, and are looked up at run time: a missing one turns its feature off with a sentence in Settings, and nothing crashes.
- Nothing is lost from the menu bar. Quit Tansu, let it crash, or take its permission away, and every icon comes back: on macOS 26 the divider goes away with Tansu's process, and on macOS 27 MenuBarAgent drops the restriction of a process that has ended.

Guard tests (`GuardTests`) check the first four at every run, and the engine tests (`TahoeEngineTests`, `GoldenGateEngineTests`) check that restoring the menu bar shows every icon again. A pull request that breaks one will be closed, however good the code is.

## How to propose a change

1. Open an issue first for anything bigger than a typo, so we agree on the direction before you spend time.
2. Fork the repository and branch from `main`.
3. Write a test that fails, then the code that makes it pass: `swift test --package-path Packages/TansuKit`. The release scripts and these documents have their own tests (`scripts/tests/run.sh`), and so does the website (`cd site && node --test tests/*.test.mjs`).
4. Build the app: `brew install xcodegen`, then `scripts/build.sh`. The Debug build is `ch.rubencatalao.tansu.debug`: it keeps its own settings and its own Accessibility grant, apart from an installed Tansu. Launch it with `-TansuDemo YES` to work with generic icons and leave your own menu bar alone. On macOS 27 the engine only works from `/Applications`.
5. Open a pull request against `main`. Say what changes for a person using Tansu, not only in the code, and on which macOS you tried it. CI runs the tests and builds the app.

An app that Smart Sort puts in the wrong drawer is the easiest change to make: add its bundle identifier and its category to `Packages/TansuKit/Sources/TansuCore/Resources/Catalog.json`, then run the tests.

## Style

- Swift 6 with strict concurrency; anything that touches AppKit is `@MainActor`.
- The rules (drawers, Smart Sort, the layout planner, search) live in `TansuCore`, with tests. It imports no AppKit, so `swift test` covers every rule.
- Every user-facing string goes through `Strings.swift` and the String Catalog, in plain English: short sentences, no exclamation marks, no em dash or en dash. After adding or changing one, run `node scripts/sync-strings.mjs`, then translate the new key into the nine other languages in `Localizable.xcstrings`, with the words macOS itself uses in each language: the tests fail while a translation is missing. Not sure of a language? Say so in the pull request, and a native speaker will check it.
- Numbers, dates and times go through the formatters of the person's locale, never `String(format:)`: 0.5 s in English is 0,5 s in French.
- Native controls and the system's own glass first; custom drawing only where macOS has no control, such as the menu bar preview in Settings.
- Colors come from the brand tokens (`brand/tokens/tokens.json`) through `Theme.swift`.
- Nothing polls at rest: listen to notifications rather than run timers. Before and after a change that could cost memory or processor time, measure with `scripts/bench.sh`: at rest, Tansu stays under 30 MB and 0.01 % of one core.
- One change per commit, the message in the imperative.

## Security

See [SECURITY.md](SECURITY.md). Please do not open a public issue for a vulnerability.
