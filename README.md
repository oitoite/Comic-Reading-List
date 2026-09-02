# Unlimited Reading List

A small, dependency-free web app for building **ordered reading playlists** of comic runs and
arcs, and ticking off issues as you read them on Marvel Unlimited, DC Universe Infinite or
anywhere else. Built as a static site, so GitHub Pages serves it as-is: no build step, no
backend, no accounts, no analytics.

An entry is a *run or arc*, not a single issue: `The Amazing Spider-Man #294-296 · Kraven's
Last Hunt` is one row that expands into three tickable issues.

## Features

- **Playlists in reading order** — drag to reorder; list view numbers the rows 1, 2, 3…
- **Reorder by touch** — drag an entry by its handle, or long-press anywhere on a row.
  Playlists reorder the same way from the sidebar grips. Built on pointer events, so it
  works on a phone; HTML5 drag-and-drop does not.
- **Installable** — Add to Home Screen on iOS and it launches full-screen with its own
  icon, and keeps working offline.
- **Issue-level progress** — each entry opens a tray of issue pills. Tick them one by one, or
  use *Mark all* / *Clear*. Every count in the app is **issues read, not entries read**.
- **Issue ranges** — type `294-296, 300, Annual 1` and get five issues. Prefixes (`Annual 1-3`),
  en dashes, `1 to 3` and zero padding (`001-003`) all work; anything that isn't a plain
  numeric range (`1.MU`) is kept verbatim. Expansion is capped at 500 issues per entry.
- **Find on Marvel** — search Marvel's catalogue and let it fill everything in: the issue
  list, each issue's permalink and the year, with no account or API key. Trim the range
  before adding if you only want part of a run.
- **Bulk add** — paste a whole reading order, one entry per line:

  ```
  The Amazing Spider-Man #294-296 | Kraven's Last Hunt
  Web of Spider-Man #31-32
  Watchmen
  ```

  `Series #issues | Optional arc title`. A line with no `#` becomes a single unnumbered book.
  A live preview counts the entries and issues before you commit.
- **Derived status** — every issue ticked is *Finished*, some ticked (or explicitly started) is
  *In progress*, otherwise *Not started*. There is no status field to keep in sync by hand.
- **Service links** — each playlist has a default service and each entry can override it. Links
  resolve most-specific-first: an issue's own pasted URL, then the entry's, then a search link
  built from an editable template. Marvel Unlimited points at Marvel's own comics search.
- **Per-issue links** — services that address issues by numeric id (Marvel's
  `/comics/issue/25182/...`) cannot be reached by any search template, so the issue tray has a
  **Links** button: one row per issue, paste and go. On a phone those permalinks hand off to the
  service's own app.
- **Share links** — pack a whole playlist into a URL and send it. Opening one offers a copy.
- **Rich metadata** — writer, artist, publisher, year, cover image, tags, notes, 5-star rating.
- **Search, filter, sort**, list or cover view, light and dark themes.
- **Covers everywhere** — pulled automatically for Marvel entries. Anything without
  artwork gets a colour block keyed to the series name rather than an empty slot.
- **Save a copy** — one tap opens the iOS share sheet, so a backup lands in Files or
  iCloud Drive; elsewhere it downloads. **Restore** reads one back, including old v1
  backups. The sidebar says so when the only copy is the browser's.
- **Keyboard shortcuts** — `/` focuses search, `n` adds an entry, `b` opens bulk add.

## Service search templates

The app links out to whatever service you read on. When neither the issue nor the entry has a
direct link, it builds one from that service's template. Three placeholders are available:

| Placeholder  | Becomes                              |
| ------------ | ------------------------------------ |
| `{q}`        | series and issue — `Fantastic Four #570` |
| `{series}`   | `Fantastic Four`                     |
| `{issue}`    | `570`                                |

`{series}` and `{issue}` exist because some searches return nothing when an issue number is in
the query — use `{series}` alone if that happens.

Marvel Unlimited defaults to Marvel's own comics search:

```
https://www.marvel.com/search?content_type=comics&offset=0&query={q}
```

**The DC Universe Infinite default is still a placeholder** — a site-scoped web search, which
works but is not the in-app search. Replacing it takes ten seconds and no code change: run a
search on the service, copy the address bar **of the results page** (before clicking through to
an issue), and paste it into **Services** with the search term swapped for `{q}`. Templates must
start with `http://` or `https://`.

If you upgrade from a build that shipped a different default, an untouched template moves on to
the new default automatically; anything you edited by hand is left exactly as it is.

### Why a template can't always do the job

Marvel addresses a comic by numeric id — `https://www.marvel.com/comics/issue/25182/fantastic-four-1998-570`
— and `{q}` only ever expands to text like `Fantastic Four #570`. Turning that text into `25182`
is a lookup, and there is no keyless public comics metadata API to do it with: Marvel's official
API requires a server-side key hash, which a static page cannot produce.

So permalinks are entered, not generated. Paste one per issue under **Links** in the issue tray,
or one for a whole entry under **Direct link**. They travel in exports and share links like any
other field.

## Marvel lookup

**Search Marvel** searches a free third-party index of Marvel comics
(`marvel.emreparker.com`) and builds a whole entry from it: the issue list in reading
order, each issue's own `marvel.com` permalink, the year, and the publisher. No account,
no API key, no backend — the service sends CORS headers, so the page calls it directly.

Marvel's own developer API is gone, which is why this points at a third-party index
instead. That also means it is someone else's service: if it moves or disappears, set
**Services → Comic metadata API** to a replacement rather than waiting on a code change.

Cover art and creator credits come from the API's per-issue endpoint, which carries both
(the list endpoints do not). That is one extra call per entry rather than one per issue,
so it costs nothing against the rate limit. Marvel's image CDN serves the artwork; the
URLs are upgraded to https or the browser would block them as mixed content.

If you trim a run before adding it, the cover and credits are re-fetched from the first
issue you actually kept — otherwise a Hickman run would show a cover from 1998.

### Quirks worth knowing

The API is indexed by issue, not by series, so a search matches issue *and* series names
and the results are folded back into the series they came from. It caps at 200 issues per
search, and one long-running volume can fill all 200 — so if the volume you want is
missing, add a year or an issue number (`fantastic four 1998`) to narrow it.

Its search backend returns a server error on `(`, `)`, `*`, `:`, `%`, `?` and apostrophes,
so the query is cleaned before it is sent: those become spaces rather than being deleted,
because `Kraven's Last Hunt` has to stay four tokens to match anything.

Issues come back newest-first with numbers as strings that may be decimal (`605.1`,
`0.5`), so they are sorted numerically into reading order. Some series give every issue the
same number — five one-shots all called `#1` — and those labels are disambiguated
(`1`, `1 (2)`, `1 (3)`) so the range box and the per-issue links do not collide.

There is an **Only issues available on Marvel Unlimited** filter, since that is the point
of the app; the summary line tells you how many of a run are on it.

## Share links

**Share** packs the playlist into the link's own hash: compact JSON → gzip (via
`CompressionStream`, with a raw base64 fallback) → base64url. No server is involved and nothing
is uploaded. A checkbox controls whether your read progress travels with it.

Opening such a link offers to add a **copy** — the recipient's edits never touch yours. Incoming
payloads are treated as untrusted: every field is sanitised, links are restricted to `http(s)`,
and the entry count is capped.

Long playlists make long URLs, and some chat apps and mail clients truncate them. The dialog
shows the character count and warns past ~8,000; for very large playlists, an exported JSON file
travels better.

## The interface

The app is built for a phone first, so the chrome stays out of the way:

- **Tap a row to open its issues.** That is the main gesture — the tray holds the issue
  pills plus the actions for that entry (start/finish, clear, per-issue links, edit,
  remove), so none of them take up space until you want them.
- **Two menus, not two rows of buttons.** The `⋯` beside the app name holds saving,
  restoring, services and the theme; the `⋯` beside the playlist name holds sharing,
  renaming, sort, service, view and delete.
- **One primary action.** *Search Marvel* is pinned to the bottom of the screen on a
  phone and sits above the list on a desktop. Manual entry lives behind *Add manually*.
- **Status is the progress bar's colour** — grey not started, blue in progress, green
  finished — rather than a text badge on every row.

## Installing it on a phone

Open the site in Safari, tap **Share → Add to Home Screen**. It launches without browser
chrome, with its own icon, and the service worker keeps the app shell cached so it opens
without a connection — the Marvel lookup obviously still needs one.

The app is four static files plus a manifest and a service worker; the worker is
network-first, so a deploy is picked up on the next launch rather than being pinned to a
stale cache.

## Data and privacy

Everything lives in your browser's `localStorage` under the key `longbox.playlists.v2` — nothing
is uploaded anywhere. The key is deliberately specific: all GitHub Pages project sites on one
account share a single origin, so a generic name could collide with another app's storage. It
still carries the app's original name (Longbox) on purpose — renaming a storage key orphans
every existing user's data, so it stays put.

Data does not follow you between browsers or devices, and clearing site data erases it — so
**Save a copy** matters. On iOS that opens the share sheet, which is the route into Files and
iCloud Drive; on a desktop it downloads a JSON file. **Restore** loads one back, adding its
playlists alongside your existing ones rather than replacing them. A share link moves a single
playlist. The sidebar nags when the last saved copy is more than a fortnight old.

### Upgrading from v1

A v1 list (`longbox.state.v1`) is migrated automatically the first time you open v2:

- `series` comes from the old series field, falling back to the old title.
- The old title becomes the **arc title**, but only when a series was filled in.
- The old issue string is expanded into individual issues.
- Old *Read* ticks every issue; old *Reading* marks the entry started.

The v1 key is **left in place untouched** as a backup, so the old data survives even if
something about the migration surprises you.

## Publishing on GitHub Pages

Either approach works:

1. **Deploy from a branch** — Settings → Pages → Source: *Deploy from a branch*, pick `main` / `/ (root)`.
2. **GitHub Actions** — Settings → Pages → Source: *GitHub Actions*. The included
   [`.github/workflows/pages.yml`](.github/workflows/pages.yml) publishes the repository root on every push to `main`.

The site is then available at `https://<username>.github.io/Comic-Reading-List/`.

## Running locally

No tooling required — serve the folder:

```sh
python3 -m http.server 8000
# then visit http://localhost:8000
```

Serve it rather than opening `index.html` directly: `file://` pages get an opaque origin, so
`localStorage` and share links behave inconsistently.

## Project layout

```
index.html            markup and dialogs
assets/styles.css     design tokens, layout, light/dark themes
assets/app.js         state, migration, parsing, share codec, rendering
assets/favicon.svg    icon
assets/icons/*.png    home-screen and manifest icons
manifest.webmanifest  installable-app metadata
sw.js                 offline shell
.nojekyll             serve files as-is on Pages
```
