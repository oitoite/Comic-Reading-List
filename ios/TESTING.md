# Testing the iOS app

Two layers, tested two ways. The logic package runs anywhere Swift runs; the app needs a Mac
with Xcode 16 or later.

## 1. Logic package (no Mac needed)

Everything that is not a view lives in `ios/Packages/ReadingListCore` and has its own test suite:
range parsing, bulk parsing, progress maths, link resolution, v1 migration, backups, share links
(including fixtures produced by the web app's own JavaScript), the Marvel index client's parsing,
and the file store.

```sh
git clone https://github.com/oitoite/Comic-Reading-List
cd Comic-Reading-List
git checkout claude/peaceful-faraday-ugl1pu
cd ios/Packages/ReadingListCore
swift test
```

Expected: `Executed 153 tests, with 0 failures`.

- **macOS**: Xcode's toolchain is enough. Run the commands in Terminal.
- **Linux (Ubuntu 24.04)**: install Swift from swift.org and `sudo apt-get install zlib1g-dev`
  (the gzip share codec links against zlib).
- **GitHub Actions**: the `iOS core tests` workflow runs the same command on every push that
  touches `ios/Packages/`. Check the Actions tab of the repository.

Filter to one area while iterating, for example:

```sh
swift test --filter IssueSpecTests
swift test --filter WebInteropTests
```

## 2. The app (Mac + Xcode 16 or later)

### Build

1. Open `ios/UnlimitedReadingList.xcodeproj`.
2. Select the `UnlimitedReadingList` scheme (top-left).
3. In the project navigator click the project, then the `UnlimitedReadingList` target,
   then *Signing & Capabilities*. Pick your Team. A free personal Apple ID works for the
   simulator and for a device you own.
4. Pick a run destination: any iPhone simulator, an iPad simulator for the split-view layout,
   or a plugged-in device.
5. Press ⌘R.

The app was written without access to Xcode, so the first build may surface a small number
of type-check errors in the SwiftUI files. They will be local and mechanical (an argument label,
a modifier signature). Fix them where Xcode points, or paste the error back into a Claude Code
session on the branch.

### Run the package tests inside Xcode

Product → Test (⌘U) runs `ReadingListCoreTests`; the shared scheme already includes it.

### Manual test plan

Work through these in order; each one exercises a distinct piece.

**Playlists (sidebar)**
- Launch: one playlist, "My reading list", is there with 0 of 0 issues.
- Tap **+**, name a playlist, create it. It becomes selected.
- Long-press a playlist → Rename. Swipe left → Delete. The last playlist cannot be deleted from
  the playlist menu.
- On an iPhone, back out of a playlist and tap the same one again: it must reopen.

**Bulk add**
- Playlist → **Add** → **Bulk add**. Paste:
  ```
  The Amazing Spider-Man #294-296 | Kraven's Last Hunt
  Web of Spider-Man #31-32
  Watchmen
  ```
- The preview must say 3 entries · 6 issues. Add them.
- Rows are numbered 1, 2, 3 (reading order), and the header says 0 of 6 issues · 0%.

**Issue tray and progress**
- Tap the first row: three pills, 294 295 296. Tap 294: it fills green, the row shows 1/3, the
  header says 1 of 6, the sidebar says 1 of 6. Status bar colour turns blue (in progress).
- Tap **Finish** in the tray: 3/3, green bar. Tap **Clear**: back to 0/3.
- Swipe the second row right: "Read next" ticks issue 31.
- **Up next** at the top shows the first unticked issue in reading order; its tick button
  advances it.

**Filters, search, sort**
- Segmented control: "In progress" shows only rows with some issues ticked.
- Search "Kraven": one row. Clear it.
- ⋯ menu → Sort → Series. Reading-order numbers disappear and Edit is hidden. Back to
  Reading order: numbers return; **Edit** lets you drag rows, and the order persists after
  relaunch.

**Manual entry and editing**
- **Add** → **Add manually**. Type series, an issue range `Annual 1-3, 5.MU`; the caption under
  the field must say 4 issues. Set a rating. Save.
- Edit that entry, change the range to `Annual 1-3`: an issue you had ticked stays ticked.
- Paste `javascript:alert(1)` into Direct link: a red caption appears; after saving, the detail
  sheet's Read button uses the search template instead (the value was dropped).

**Detail sheet and covers**
- Tap a row's cover: the detail sheet shows all rows, tags, notes and a Read button.
- For a Marvel entry with a cover, tap the cover in the sheet: full-screen viewer, pinch to
  zoom, double-tap to reset.

**Find on Marvel** (needs a network connection)
- **Find on Marvel** → search `fantastic four 1998` → pick the series.
- Wait for "Trim the issue list below…". Cover, year and credits fill in.
- Toggle "Only issues available on Marvel Unlimited": the range and count change.
- Trim the range to `570-588` and add. The entry has per-issue links (a link glyph on each
  pill), and **Read #570** opens marvel.com. On a device with the Marvel Unlimited app installed
  it hands off to the app.
- Open the detail sheet: a blurb appears under the notes after a moment.

**Services**
- Sidebar ⋯ → **Services**. Replace the DC template with a URL that lacks `http`: red caption.
  Put it back. Change the playlist's default service (playlist ⋯ → Read on → DC Universe
  Infinite): an entry with no override now builds its Read link from the DC template.

**Share links**
- Playlist ⋯ → **Share…**. A `https://oitoite.github.io/Comic-Reading-List/#list=g…` link with a
  character count appears. Toggle "Include which issues are ticked off": the link changes.
- **Copy link**, then open it in Safari on the same device: the web app offers to add a copy.
  Progress is present only when the toggle was on.
- Reverse direction: share a playlist from the web app, copy the link, then in the app
  Sidebar ⋯ → **Paste a share link…** → Paste → Add. A sheet offers a copy; accept it.
- Custom scheme: in Safari's address bar enter `unlimitedreadinglist://list/` followed by the
  code after `#list=` from any share link. iOS opens the app with the same sheet.

**Backup and restore**
- Sidebar ⋯ → **Save a copy…** → **Save a copy** opens the share sheet; save to Files. Cancel
  the share sheet instead and the "only exists on this device" note must remain, because
  nothing was saved.
- **Save to Files…** writes `unlimited-reading-list-<date>.json`. Open it in the web app's
  **Restore**: the playlists import there.
- **Restore** → choose a JSON exported by the web app: its playlists are added alongside
  yours, with " (imported)" on a name clash.
- Restore an old v1 backup (`longbox.state.v1` export): series, arc titles, ticks and started
  flags come through as described in the README's "Upgrading from v1".

**Persistence and appearance**
- Force-quit the app and relaunch: everything is as you left it, including the active playlist.
- Sidebar ⋯ → Appearance: System, Light and Dark switch immediately.
- iPad: rotate to landscape; the sidebar and playlist sit side by side.

### Where the data lives

The state file is `playlists.v2.json` under the app's Application Support directory. In the
simulator you can find it with:

```sh
xcrun simctl get_app_container booted com.oitoite.UnlimitedReadingList data
```

then `Library/Application Support/UnlimitedReadingList/playlists.v2.json`. It is the same
schema as the web app's `localStorage` value, so it can be diffed against a site export.

### Testing on your own iPhone without a paid developer account

Signing with a free Apple ID installs to a device you own for seven days at a time. Plug the
phone in, pick it as the destination, and on the phone allow the developer certificate under
Settings → General → VPN & Device Management the first time.
