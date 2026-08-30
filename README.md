# Longbox — Comic Reading List

A small, dependency-free web app for tracking comic book reading lists. Built as a
static site, so GitHub Pages serves it as-is: no build step, no backend, no accounts.

## Features

- **Multiple reading lists** — one for the current pull, one for the trade backlog, one for the re-read.
- **Rich entries** — title, series, issue/volume, writer, artist, publisher, year, cover image, tags, notes.
- **Three-state progress** — *Want to read → Reading → Read*, with per-list stats and a progress bar.
- **Search and filter** across every field, plus sorting by title, series & issue, year, rating or date added.
- **Custom order** — drag rows to reorder a list (list view, with sort set to *Custom order*).
- **Grid or list view**, light and dark themes.
- **JSON import/export** so your data is portable and backed up.
- **Keyboard shortcuts** — `/` focuses search, `n` adds a comic.

## Data and privacy

Everything lives in your browser's `localStorage` on the device you are using — nothing is
uploaded anywhere. That also means the data does not follow you between browsers or devices,
and clearing site data erases it. Use **Export** to save a JSON backup and **Import** to load
it elsewhere; importing adds the file's lists alongside your existing ones rather than
replacing them.

## Publishing on GitHub Pages

Either approach works:

1. **Deploy from a branch** — Settings → Pages → Source: *Deploy from a branch*, pick `main` / `/ (root)`.
2. **GitHub Actions** — Settings → Pages → Source: *GitHub Actions*. The included
   [`.github/workflows/pages.yml`](.github/workflows/pages.yml) publishes the repository root on every push to `main`.

The site is then available at `https://<username>.github.io/Comic-Reading-List/`.

## Running locally

No tooling required — open `index.html` in a browser, or serve the folder:

```sh
python3 -m http.server 8000
# then visit http://localhost:8000
```

## Project layout

```
index.html          markup and dialogs
assets/styles.css   design tokens, layout, light/dark themes
assets/app.js       state, storage, rendering, import/export
assets/favicon.svg  icon
.nojekyll           serve files as-is on Pages
```
