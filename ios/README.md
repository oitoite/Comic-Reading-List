# Unlimited Reading List for iOS

A native SwiftUI companion to the web app in the repository root: ordered reading playlists of
comic runs and arcs, ticked off issue by issue as you read them on Marvel Unlimited, DC Universe
Infinite or anywhere else. Same data format as the site, so backups and share links move freely
between the two.

## Layout

```
ios/
  UnlimitedReadingList.xcodeproj   Xcode 16+ project (synchronized folders: drop a file in, it builds)
  UnlimitedReadingList/            the app target — SwiftUI only
    App/                           entry point, URL handling
    Model/                         AppModel: the observable state container every view talks to
    Views/                         screens and sheets
    Design/                        colours, cover placeholders, haptics
    Assets.xcassets                icon (rendered from assets/favicon.svg) and accent colour
  Packages/ReadingListCore/        everything that is not a view, as a Swift package
    Sources/ReadingListCore/       models, sanitiser, parsing, migration, links, share codec,
                                   Marvel index client, file store
    Sources/CZlib/                 zlib shim (gzip for share links)
    Tests/ReadingListCoreTests/    XCTest suite; runs on Linux
```

The split is deliberate. `ReadingListCore` has no UIKit or SwiftUI dependency, so it builds and
tests on Linux — including in the sandbox this port was written in, which has no Xcode — and in the
`iOS core tests` GitHub Actions workflow. The app target is thin: it sequences Core calls and draws.

## Building

Open `ios/UnlimitedReadingList.xcodeproj` in Xcode 16 or later, pick a team under *Signing &
Capabilities*, and run. Deployment target is iOS 17. There are no third-party dependencies; the
only package is the local `ReadingListCore`.

To run the logic tests without Xcode:

```sh
cd ios/Packages/ReadingListCore
swift test          # needs zlib headers: apt-get install zlib1g-dev on Debian/Ubuntu
```

## Data

State is one JSON file, `playlists.v2.json`, in the app's Application Support directory. It is the
same schema as the site's `longbox.playlists.v2` localStorage value, and every byte that enters the
app — the file itself, a restored backup, a share link — goes through `Sanitizer`, which clamps
lengths, drops non-http(s) URLs and caps issue and entry counts.

- **Save a copy** writes the same backup JSON the site exports (`unlimited-reading-list-<date>.json`),
  via the Files picker or the share sheet.
- **Restore** reads a site or app backup, including old v1 (`longbox.state.v1`) backups, which are
  migrated on the way in. Imported playlists are added alongside existing ones.
- **Share links** are `https://oitoite.github.io/Comic-Reading-List/#list=<code>` — the web app's
  own URL, so a recipient without the app still opens it in a browser. The code is short-key JSON →
  gzip → base64url, byte-compatible with the site. The app also registers the
  `unlimitedreadinglist://` scheme, and **Paste a share link** in the sidebar menu imports a link
  from the clipboard by hand.

Opening `https://oitoite.github.io/…` links directly in the app needs a universal-link association:
an `apple-app-site-association` file on the site naming the app's Team ID, plus the Associated
Domains entitlement. That is a five-minute setup once the app has a Team ID; until then the paste
route works.

## What the app adds over the site

- **Up next** at the top of a playlist: the next unread issue in reading order with a Read button.
- Swipe a row to tick the next issue or delete; long-press for the full menu.
- Native share sheet, Files integration, haptics, light/dark/system appearance.
- iPad: playlists in the sidebar, the list in the detail pane.
- Marvel permalinks open through iOS universal links, so they land in the Marvel Unlimited app
  when it is installed.

## What it deliberately does not do

- No accounts, no analytics, no backend. Nothing leaves the device except the requests you make:
  the Marvel index search and the links you open.
- No bundled reading orders. Build the tools; you supply the content.
- No iCloud sync yet. The file store is a single JSON document, so moving it into an iCloud
  container is the natural next step; share links and backups cover cross-device in the meantime.
