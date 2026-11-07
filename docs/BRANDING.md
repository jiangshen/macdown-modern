# Snowfolio identity

The user selected **Snowfolio** on 2026-11-06. It replaces the MacDown working name for
the new independent native writing product. Preserve the liked glacial ice-blue layered
icon, Default/Dark/Clear/Tinted appearances, Markdown document icons, and readable
notebook/callout styling. The M↓ artwork identifies the Markdown format and stays.

| Area | Current identity |
| --- | --- |
| Application and executable | `Snowfolio.app` / `Snowfolio` |
| Native project and scheme | `App/Snowfolio.xcworkspace` / `Snowfolio` |
| Native app entry point | `App/Sources/SnowfolioApp.swift` |
| Swift package | `Packages/SnowfolioCore` |
| UI library and tests | `SnowfolioUI` / `SnowfolioUITests` |
| Build helper | `Tools/build-snowfolio.sh` |
| Registration helper | `Tools/register-snowfolio.swift` |
| Adaptive code color theme | Snowfolio; persisted value stays `adaptive` |
| Fork | `jiangshen/snowfolio` |
| Preferred local checkout | `snowfolio/` |

The previous checkout path remains a compatibility symlink so existing workspace links
and the active migration goal continue resolving. `upstream` still points to the
original MacDown repository; its attribution and fork history remain intact.

## Compatibility identities

The app's existing `local.macdown.modern` bundle identifier, its test identifier, and
its native tabbing identifier remain stable. These are internal macOS compatibility
keys, distinct from the displayed application name. Changing them would create a new
app identity with different preferences, permissions, recent documents and native
restoration state. Snowfolio continues using the same preference domain and legacy
preference migration, preserving explicit settings and the native reopen preference.

The standard `net.daringfireball.markdown` type, `.md` / `.markdown` extensions, MIME
types and Markdown icon resource names remain interoperable. Registration must verify
that Snowfolio appears as an available handler without changing existing defaults.
Installing a production-ready release and setting it as the default remain separately
authorized work, gated on the broader reliability and parity requirements.

## Historical names and provenance

Original MacDown code, old project/CLI/scripting identifiers, license filenames,
third-party notices and historical validation snapshots retain their actual names.
They establish compatibility and legal provenance. They are not the new app's public
branding. Retire legacy first-party code progressively after replacements pass parity;
do not rewrite a copyright notice or past test record to suggest new authorship.

Future release, updater, Help, CLI and URL-routing work should use Snowfolio as the
primary product identity and document any required historical aliases. These features
are still tracked in the roadmap; the rename does not claim their implementation.
