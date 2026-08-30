/* Longbox — ordered comic reading playlists.
   No build step, no backend: state lives in localStorage and travels by JSON export
   or by a share link that carries the whole playlist in its own URL hash. */
(function () {
  'use strict';

  /* A distinct key: every GitHub Pages project site on an account shares one origin,
     so a generic name could collide with another app's storage. */
  var STORAGE_KEY = 'longbox.playlists.v2';
  var LEGACY_KEY = 'longbox.state.v1';
  var SCHEMA_VERSION = 2;

  var MAX_ISSUES = 500;        /* per entry — stops "1-99999" from hanging the page */
  var MAX_BULK_LINES = 500;
  var MAX_SHARE_ENTRIES = 500;

  var STATUSES = { unread: 'Not started', reading: 'In progress', finished: 'Finished' };
  var SORTS = ['order', 'added', 'series', 'title', 'progress', 'year', 'rating'];

  /* Search templates are deliberately editable: Marvel's and DC's real in-app search
     URLs could not be verified from here, so the defaults are honest placeholders
     (a site-scoped web search) that work today and are meant to be replaced. */
  var DEFAULT_SERVICES = [
    { id: 'mu', name: 'Marvel Unlimited', template: 'https://duckduckgo.com/?q=site%3Amarvel.com+{q}' },
    { id: 'dcui', name: 'DC Universe Infinite', template: 'https://duckduckgo.com/?q=site%3Adcuniverseinfinite.com+{q}' },
    { id: 'other', name: 'Other', template: 'https://duckduckgo.com/?q={q}' }
  ];

  /* ---------------- helpers ---------------- */

  function uid() {
    return 'c' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  }

  function str(v, max) {
    if (typeof v !== 'string') return '';
    return v.trim().slice(0, max);
  }

  function numOrEmpty(v) {
    var n = parseInt(v, 10);
    if (isNaN(n) || n < 1900 || n > 2200) return '';
    return n;
  }

  /* Only allow http(s) links — keeps pasted javascript:/data: URLs out of the DOM. */
  function safeUrl(v, max) {
    if (typeof v !== 'string') return '';
    var s = v.trim();
    if (!s) return '';
    if (!/^https?:\/\//i.test(s)) return '';
    return s.slice(0, max || 2000);
  }

  /* ---------------- issue parsing ---------------- */

  var RANGE_RE = /^(.*?)(\d+)\s*(?:-|–|—|\.{2,}|\bto\b)\s*(.*?)(\d+)$/i;

  /* "294-296, 300, Annual 1" -> ["294","295","296","300","Annual 1"].
     Anything that is not a plain numeric range is kept verbatim, so "1.MU" or
     "Director's Cut" survive untouched. */
  function parseIssueSpec(spec, cap) {
    cap = cap || MAX_ISSUES;
    var labels = [];
    var truncated = false;

    String(spec == null ? '' : spec).split(/[,;\n]/).forEach(function (chunk) {
      if (truncated) return;
      var tok = chunk.trim().replace(/^#+\s*/, '').trim();
      if (!tok) return;

      var m = tok.match(RANGE_RE);
      if (m) {
        var prefix = m[1].trim();
        var rightPrefix = m[3].trim().replace(/^#+\s*/, '').trim();
        var from = parseInt(m[2], 10);
        var to = parseInt(m[4], 10);
        var sameSide = rightPrefix === '' || rightPrefix.toLowerCase() === prefix.toLowerCase();

        if (sameSide && to >= from) {
          /* Preserve zero padding: "001-003" -> 001, 002, 003. */
          var pad = /^0\d/.test(m[2]) ? m[2].length : 0;
          var sep = prefix && !/[\s#.]$/.test(prefix) ? ' ' : '';
          for (var n = from; n <= to; n++) {
            if (labels.length >= cap) { truncated = true; return; }
            var num = String(n);
            while (num.length < pad) num = '0' + num;
            labels.push(str(prefix + sep + num, 40));
          }
          return;
        }
      }

      if (labels.length >= cap) { truncated = true; return; }
      labels.push(str(tok, 40));
    });

    return { labels: labels, truncated: truncated };
  }

  /* The inverse, close enough to round-trip: consecutive numbers collapse back
     into ranges so the edit field stays readable. */
  function summarizeIssues(issues) {
    var parts = [];
    var runPrefix = null, runFrom = null, runTo = null, runPad = 0;

    function flush() {
      if (runFrom == null) return;
      var a = pad(runFrom, runPad), b = pad(runTo, runPad);
      var sep = runPrefix && !/[\s#.]$/.test(runPrefix) ? ' ' : '';
      parts.push(runFrom === runTo ? runPrefix + sep + a : runPrefix + sep + a + '-' + b);
      runPrefix = runFrom = runTo = null;
      runPad = 0;
    }
    function pad(n, width) {
      var s = String(n);
      while (s.length < width) s = '0' + s;
      return s;
    }

    (issues || []).forEach(function (is) {
      var label = (is && is.label ? is.label : '').trim();
      var m = label.match(/^(.*?)(\d+)$/);
      if (!label || !m) { flush(); if (label) parts.push(label); return; }
      var prefix = m[1].replace(/\s+$/, '');
      var n = parseInt(m[2], 10);
      var width = /^0\d/.test(m[2]) ? m[2].length : 0;
      if (runFrom != null && prefix === runPrefix && width === runPad && n === runTo + 1) {
        runTo = n;
        return;
      }
      flush();
      runPrefix = prefix; runFrom = runTo = n; runPad = width;
    });
    flush();
    return parts.join(', ');
  }

  /* Bulk lines: "Series #294-296 | Arc title". No "#" means one unnumbered book. */
  function parseBulkLines(text) {
    var out = [];
    var skipped = 0;
    var truncated = false;
    var lines = String(text == null ? '' : text).split(/\r?\n/);

    lines.forEach(function (line) {
      if (out.length >= MAX_BULK_LINES) { truncated = true; return; }
      var raw = line.trim();
      if (!raw || raw.indexOf('//') === 0) return;

      var title = '';
      var left = raw;
      var bar = raw.indexOf('|');
      if (bar > -1) {
        left = raw.slice(0, bar).trim();
        title = raw.slice(bar + 1).trim();
      }

      var series = left, spec = '';
      var hash = left.lastIndexOf('#');
      if (hash > -1) {
        series = left.slice(0, hash).trim();
        spec = left.slice(hash + 1).trim();
      }
      if (!series) { skipped++; return; }

      var parsed = spec ? parseIssueSpec(spec) : { labels: [], truncated: false };
      var labels = parsed.labels.length ? parsed.labels : [''];
      if (parsed.truncated) truncated = true;

      out.push({
        series: str(series, 200),
        title: str(title, 200),
        issues: labels.map(function (l) { return { label: l, done: false }; })
      });
    });

    var issueCount = out.reduce(function (a, e) { return a + e.issues.length; }, 0);
    return { entries: out, issues: issueCount, skipped: skipped, truncated: truncated };
  }

  /* ---------------- state ---------------- */

  function blankState() {
    return {
      version: SCHEMA_VERSION,
      lists: [{ id: uid(), name: 'My reading list', service: 'mu', createdAt: Date.now(), entries: [] }],
      activeListId: null,
      prefs: { theme: 'dark', sort: 'order', view: 'list', services: DEFAULT_SERVICES.map(clone) }
    };
  }

  function clone(o) { return JSON.parse(JSON.stringify(o)); }

  function sanitizeServices(raw) {
    var byId = {};
    if (Array.isArray(raw)) {
      raw.filter(Boolean).forEach(function (s) {
        var id = str(s.id, 20);
        if (id) byId[id] = { id: id, name: str(s.name, 60), template: safeUrl(s.template, 500) };
      });
    }
    return DEFAULT_SERVICES.map(function (d) {
      var found = byId[d.id];
      return {
        id: d.id,
        name: (found && found.name) || d.name,
        template: (found && found.template) || d.template
      };
    });
  }

  /* '' means "inherit the playlist default" on an entry; a list falls back to the first service. */
  function serviceId(v, fallback) {
    var id = str(v, 20);
    return DEFAULT_SERVICES.some(function (d) { return d.id === id; }) ? id : (fallback || '');
  }

  function sanitizeIssues(raw) {
    var out = [];
    if (Array.isArray(raw)) {
      raw.filter(function (i) { return i != null; }).slice(0, MAX_ISSUES).forEach(function (i) {
        if (typeof i === 'string') out.push({ label: str(i, 40), done: false });
        else out.push({ label: str(i.label, 40), done: !!i.done });
      });
    }
    /* Every entry owns at least one tickable issue, so progress is never 0 of 0. */
    return out.length ? out : [{ label: '', done: false }];
  }

  function sanitizeEntry(e) {
    e = e || {};
    return {
      id: typeof e.id === 'string' && e.id ? e.id : uid(),
      series: str(e.series, 200) || 'Untitled',
      title: str(e.title, 200),
      issues: sanitizeIssues(e.issues),
      started: !!e.started,
      writer: str(e.writer, 200),
      artist: str(e.artist, 200),
      publisher: str(e.publisher, 120),
      year: numOrEmpty(e.year),
      service: serviceId(e.service),
      url: safeUrl(e.url),
      cover: safeUrl(e.cover),
      tags: Array.isArray(e.tags)
        ? e.tags.map(function (t) { return str(t, 40); }).filter(Boolean).slice(0, 20)
        : [],
      notes: str(e.notes, 2000),
      rating: Math.max(0, Math.min(5, parseInt(e.rating, 10) || 0)),
      addedAt: typeof e.addedAt === 'number' ? e.addedAt : Date.now()
    };
  }

  function sanitizeLists(raw) {
    if (!Array.isArray(raw)) return [];
    return raw.filter(Boolean).map(function (l) {
      var entries = Array.isArray(l.entries) ? l.entries : (Array.isArray(l.items) ? l.items : []);
      return {
        id: typeof l.id === 'string' && l.id ? l.id : uid(),
        name: str(l.name, 80) || 'Untitled list',
        service: serviceId(l.service, 'mu'),
        createdAt: typeof l.createdAt === 'number' ? l.createdAt : Date.now(),
        entries: entries.filter(Boolean).map(sanitizeEntry)
      };
    });
  }

  /* ---------------- v1 migration ---------------- */

  /* A v1 item was a single comic; a v2 entry is a run or arc. The old title becomes
     the arc name only when a series was filled in, otherwise it *is* the series. */
  function migrateItem(it) {
    it = it || {};
    var oldSeries = str(it.series, 200);
    var oldTitle = str(it.title, 200);
    var parsed = parseIssueSpec(it.issue);
    var labels = parsed.labels.length ? parsed.labels : [''];
    var read = it.status === 'read';

    return sanitizeEntry({
      id: it.id,
      series: oldSeries || oldTitle,
      title: oldSeries ? oldTitle : '',
      issues: labels.map(function (l) { return { label: l, done: read }; }),
      started: it.status === 'reading',
      writer: it.writer,
      artist: it.artist,
      publisher: it.publisher,
      year: it.year,
      cover: it.cover,
      tags: it.tags,
      notes: it.notes,
      rating: it.rating,
      addedAt: it.addedAt
    });
  }

  function migrateV1(parsed) {
    var lists = Array.isArray(parsed && parsed.lists) ? parsed.lists : [];
    var prefs = (parsed && parsed.prefs) || {};
    return {
      version: SCHEMA_VERSION,
      lists: lists.filter(Boolean).map(function (l) {
        return {
          id: typeof l.id === 'string' && l.id ? l.id : uid(),
          name: str(l.name, 80) || 'Untitled list',
          service: 'mu',
          createdAt: typeof l.createdAt === 'number' ? l.createdAt : Date.now(),
          entries: (Array.isArray(l.items) ? l.items : []).filter(Boolean).map(migrateItem)
        };
      }),
      activeListId: typeof parsed.activeListId === 'string' ? parsed.activeListId : null,
      prefs: {
        theme: prefs.theme === 'light' ? 'light' : 'dark',
        sort: 'order',
        view: prefs.view === 'grid' ? 'grid' : 'list',
        services: DEFAULT_SERVICES.map(clone)
      }
    };
  }

  function finalize(parsed) {
    var fresh = blankState();
    var lists = sanitizeLists(parsed && parsed.lists);
    if (!lists.length) lists = fresh.lists;
    var prefs = (parsed && parsed.prefs) || {};
    var sort = SORTS.indexOf(str(prefs.sort, 20)) !== -1 ? str(prefs.sort, 20) : 'order';
    return {
      version: SCHEMA_VERSION,
      lists: lists,
      activeListId: lists.some(function (l) { return l.id === (parsed && parsed.activeListId); })
        ? parsed.activeListId : lists[0].id,
      prefs: {
        theme: prefs.theme === 'light' ? 'light' : 'dark',
        sort: sort,
        view: prefs.view === 'grid' ? 'grid' : 'list',
        services: sanitizeServices(prefs.services)
      }
    };
  }

  function load() {
    var raw = null, legacy = null;
    try { raw = localStorage.getItem(STORAGE_KEY); } catch (e) { raw = null; }

    if (raw) {
      try { return finalize(JSON.parse(raw)); } catch (e) { /* fall through */ }
    }

    try { legacy = localStorage.getItem(LEGACY_KEY); } catch (e) { legacy = null; }
    if (legacy) {
      try {
        var migrated = finalize(migrateV1(JSON.parse(legacy)));
        migratedFromV1 = true;
        return migrated;              /* the v1 key is left untouched as a backup */
      } catch (e) { /* fall through */ }
    }

    var fresh = blankState();
    fresh.activeListId = fresh.lists[0].id;
    return fresh;
  }

  var migratedFromV1 = false;
  var state = load();
  var ui = {
    query: '',
    status: 'all',
    sort: state.prefs.sort || 'order',
    view: state.prefs.view || 'list',
    expanded: {}
  };
  var editingId = null;

  function save() {
    state.prefs.sort = ui.sort;
    state.prefs.view = ui.view;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    } catch (e) {
      toast('Could not save — browser storage is full or blocked.');
    }
  }

  function activeList() {
    var l = state.lists.filter(function (x) { return x.id === state.activeListId; })[0];
    if (!l) { l = state.lists[0]; state.activeListId = l.id; }
    return l;
  }

  function findEntry(id) {
    return activeList().entries.filter(function (e) { return e.id === id; })[0];
  }

  /* ---------------- derived status & progress ---------------- */

  function doneCount(entry) {
    return entry.issues.filter(function (i) { return i.done; }).length;
  }

  function statusOf(entry) {
    var done = doneCount(entry);
    if (done === entry.issues.length) return 'finished';
    if (done > 0 || entry.started) return 'reading';
    return 'unread';
  }

  /* Progress is counted in issues, not entries: a 30-issue run is not one tick. */
  function listProgress(list) {
    var total = 0, done = 0;
    list.entries.forEach(function (e) {
      total += e.issues.length;
      done += doneCount(e);
    });
    return { done: done, total: total, pct: total ? Math.round((done / total) * 100) : 0 };
  }

  /* ---------------- services & links ---------------- */

  function serviceById(id) {
    var all = state.prefs.services;
    return all.filter(function (s) { return s.id === id; })[0] || all[0];
  }

  function serviceFor(entry) {
    return serviceById(entry.service || activeList().service);
  }

  function searchUrl(entry, issueLabel) {
    var svc = serviceFor(entry);
    var tpl = safeUrl(svc && svc.template, 500);
    if (!tpl) return '';
    var q = [entry.series, issueLabel ? '#' + issueLabel : ''].filter(Boolean).join(' ');
    if (tpl.indexOf('{q}') === -1) return tpl;
    return tpl.replace(/\{q\}/g, encodeURIComponent(q));
  }

  /* A pasted direct link always wins over the generated search. */
  function linkFor(entry, issueLabel) {
    return entry.url || searchUrl(entry, issueLabel);
  }

  function nextIssue(entry) {
    for (var i = 0; i < entry.issues.length; i++) {
      if (!entry.issues[i].done) return entry.issues[i];
    }
    return entry.issues[entry.issues.length - 1];
  }

  /* ---------------- share links ---------------- */

  /* A playlist is packed into the URL hash itself: short keys -> JSON -> gzip
     (when the browser has CompressionStream) -> base64url. No server involved. */
  function b64urlEncode(bytes) {
    var bin = '';
    for (var i = 0; i < bytes.length; i += 0x8000) {
      bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  function b64urlDecode(s) {
    var t = String(s).replace(/-/g, '+').replace(/_/g, '/');
    while (t.length % 4) t += '=';
    var bin = atob(t);
    var out = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function packList(list, includeProgress) {
    return {
      v: 2,
      n: list.name,
      s: list.service,
      e: list.entries.slice(0, MAX_SHARE_ENTRIES).map(function (en) {
        var o = { s: en.series };
        if (en.title) o.t = en.title;
        o.i = en.issues.map(function (is) { return is.label; });
        if (includeProgress) {
          var done = [];
          en.issues.forEach(function (is, idx) { if (is.done) done.push(idx); });
          if (done.length) o.d = done;
          if (en.started) o.st = 1;
        }
        if (en.writer) o.w = en.writer;
        if (en.artist) o.a = en.artist;
        if (en.publisher) o.p = en.publisher;
        if (en.year) o.y = en.year;
        if (en.service) o.sv = en.service;
        if (en.url) o.u = en.url;
        if (en.cover) o.c = en.cover;
        if (en.tags.length) o.g = en.tags;
        if (en.notes) o.o = en.notes;
        if (en.rating) o.r = en.rating;
        return o;
      })
    };
  }

  /* The decoded payload came out of somebody else's URL: treat every field as
     hostile, cap the entry count and run it all through the same sanitizers. */
  function unpackList(obj) {
    if (!obj || typeof obj !== 'object') return null;
    var entriesRaw = Array.isArray(obj.e) ? obj.e.slice(0, MAX_SHARE_ENTRIES) : [];
    var entries = entriesRaw.filter(Boolean).map(function (o) {
      var done = Array.isArray(o.d) ? o.d : [];
      var issues = (Array.isArray(o.i) ? o.i : []).slice(0, MAX_ISSUES).map(function (label, idx) {
        return { label: str(String(label == null ? '' : label), 40), done: done.indexOf(idx) !== -1 };
      });
      return sanitizeEntry({
        series: o.s, title: o.t, issues: issues, started: !!o.st,
        writer: o.w, artist: o.a, publisher: o.p, year: o.y,
        service: o.sv, url: o.u, cover: o.c, tags: o.g, notes: o.o, rating: o.r
      });
    });
    return {
      id: uid(),
      name: str(String(obj.n == null ? '' : obj.n), 80) || 'Shared list',
      service: serviceId(String(obj.s == null ? '' : obj.s), 'mu'),
      createdAt: Date.now(),
      entries: entries
    };
  }

  function encodeShare(obj) {
    var bytes = new TextEncoder().encode(JSON.stringify(obj));
    if (typeof CompressionStream === 'function' && typeof Response === 'function') {
      try {
        var stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream('gzip'));
        return new Response(stream).arrayBuffer().then(function (buf) {
          return 'g' + b64urlEncode(new Uint8Array(buf));
        }).catch(function () {
          return 'r' + b64urlEncode(bytes);       /* raw base64url fallback */
        });
      } catch (e) { /* fall through */ }
    }
    return Promise.resolve('r' + b64urlEncode(bytes));
  }

  function decodeShare(code) {
    return new Promise(function (resolve, reject) {
      var kind = code.charAt(0);
      var body = code.slice(1);
      var bytes;
      try { bytes = b64urlDecode(kind === 'g' || kind === 'r' ? body : code); }
      catch (e) { reject(e); return; }

      if (kind !== 'g') {
        try { resolve(JSON.parse(new TextDecoder().decode(bytes))); }
        catch (e) { reject(e); }
        return;
      }
      if (typeof DecompressionStream !== 'function') { reject(new Error('no gzip support')); return; }
      try {
        var stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
        new Response(stream).text().then(function (text) {
          resolve(JSON.parse(text));
        }).catch(reject);
      } catch (e) { reject(e); }
    });
  }

  function shareUrl(list, includeProgress) {
    return encodeShare(packList(list, includeProgress)).then(function (code) {
      return location.origin + location.pathname + '#list=' + code;
    });
  }

  /* ---------------- dom helpers ---------------- */

  function $(id) { return document.getElementById(id); }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  var toastTimer;
  function toast(msg) {
    var el = $('toast');
    if (!el) return;
    el.textContent = msg;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.hidden = true; }, 2600);
  }

  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : (many || one + 's')); }

  /* ---------------- rendering ---------------- */

  function render() {
    renderSidebar();
    renderHeader();
    renderEntries();
  }

  function renderSidebar() {
    var nav = $('listNav');
    nav.innerHTML = '';
    state.lists.forEach(function (list) {
      var li = document.createElement('li');
      var btn = document.createElement('button');
      btn.className = list.id === state.activeListId ? 'is-active' : '';
      btn.type = 'button';
      var p = listProgress(list);
      btn.innerHTML = '<span class="nav-name">' + esc(list.name) + '</span>' +
        '<span class="count">' + p.done + '/' + p.total + '</span>';
      btn.addEventListener('click', function () {
        state.activeListId = list.id;
        ui.expanded = {};
        save();
        $('sidebar').classList.remove('open');
        render();
      });
      li.appendChild(btn);
      nav.appendChild(li);
    });
  }

  function renderHeader() {
    var list = activeList();
    var entries = list.entries;
    $('listTitle').textContent = list.name;
    $('deleteListBtn').disabled = state.lists.length <= 1;
    $('listService').value = list.service;

    var p = listProgress(list);
    var finished = entries.filter(function (e) { return statusOf(e) === 'finished'; }).length;
    var reading = entries.filter(function (e) { return statusOf(e) === 'reading'; }).length;
    var rated = entries.filter(function (e) { return e.rating > 0; });
    var avg = rated.length
      ? (rated.reduce(function (a, e) { return a + e.rating; }, 0) / rated.length).toFixed(1)
      : null;

    var parts = [
      '<span><b>' + entries.length + '</b> ' + (entries.length === 1 ? 'entry' : 'entries') + '</span>',
      '<span><b>' + p.done + '</b> of <b>' + p.total + '</b> issues read</span>',
      '<span><b>' + finished + '</b> finished</span>',
      '<span><b>' + reading + '</b> in progress</span>'
    ];
    if (avg) parts.push('<span><b>' + avg + '</b> avg rating</span>');
    $('stats').innerHTML = parts.join('');

    $('progressFill').style.width = p.pct + '%';
    $('progressBar').setAttribute('aria-valuenow', String(p.pct));
    $('progressBar').setAttribute('aria-valuetext', p.done + ' of ' + p.total + ' issues read');
  }

  function visibleEntries() {
    var entries = activeList().entries.slice();
    var q = ui.query.trim().toLowerCase();

    if (ui.status !== 'all') {
      entries = entries.filter(function (e) { return statusOf(e) === ui.status; });
    }
    if (q) {
      entries = entries.filter(function (e) {
        return [e.series, e.title, e.writer, e.artist, e.publisher, e.notes,
          e.tags.join(' '), e.issues.map(function (i) { return i.label; }).join(' ')]
          .join(' ').toLowerCase().indexOf(q) !== -1;
      });
    }

    var by = {
      added: function (a, b) { return b.addedAt - a.addedAt; },
      series: function (a, b) { return a.series.localeCompare(b.series) || a.title.localeCompare(b.title); },
      title: function (a, b) { return (a.title || a.series).localeCompare(b.title || b.series); },
      rating: function (a, b) { return b.rating - a.rating || a.series.localeCompare(b.series); },
      year: function (a, b) { return (Number(b.year) || 0) - (Number(a.year) || 0); },
      progress: function (a, b) {
        return (doneCount(b) / b.issues.length) - (doneCount(a) / a.issues.length);
      }
    };
    if (by[ui.sort]) entries.sort(by[ui.sort]);
    return entries;
  }

  function stars(n) {
    return n > 0 ? '★'.repeat(n) + '☆'.repeat(5 - n) : '';
  }

  function metaLines(e) {
    var creators = [e.writer, e.artist].filter(Boolean).join(' / ');
    var pub = [e.publisher, e.year].filter(function (x) { return x !== '' && x != null; }).join(' · ');
    return [creators, pub].filter(Boolean);
  }

  function renderEntries() {
    var wrap = $('entries');
    var entries = visibleEntries();
    var total = activeList().entries.length;

    /* Reading-order numbers are a pure CSS counter — see .numbered in the stylesheet. */
    var ordered = ui.sort === 'order';
    wrap.className = 'entries ' + (ui.view === 'list' ? 'list-view' : 'grid-view') +
      (ordered && ui.view === 'list' ? ' numbered' : '');
    wrap.innerHTML = '';

    var empty = $('empty');
    if (!entries.length) {
      empty.hidden = false;
      if (total === 0) {
        $('emptyTitle').textContent = 'Nothing on this playlist yet';
        $('emptyText').textContent = 'Add a run or arc, or paste a whole reading order at once.';
        $('emptyAddBtn').hidden = false;
        $('emptyBulkBtn').hidden = false;
      } else {
        $('emptyTitle').textContent = 'No matches';
        $('emptyText').textContent = 'Nothing on this playlist matches your search or filter.';
        $('emptyAddBtn').hidden = true;
        $('emptyBulkBtn').hidden = true;
      }
      return;
    }
    empty.hidden = true;

    var draggable = ordered && ui.view === 'list' && !ui.query && ui.status === 'all';
    entries.forEach(function (e) { wrap.appendChild(card(e, draggable)); });
  }

  function card(e, draggable) {
    var el = document.createElement('article');
    el.className = 'card' + (e.cover ? '' : ' no-cover');
    el.dataset.id = e.id;

    var status = statusOf(e);
    var done = doneCount(e);
    var total = e.issues.length;
    var pct = total ? Math.round((done / total) * 100) : 0;
    var single = total === 1 && !e.issues[0].label;

    var coverInner = e.cover
      ? '<img alt="" loading="lazy" src="' + esc(e.cover) + '">'
      : '<div class="cover-fallback">' + esc(e.series) + '</div>';

    var metas = metaLines(e).map(function (s) {
      return '<div class="card-sub">' + esc(s) + '</div>';
    }).join('');

    var tags = e.tags.length
      ? '<div class="tags">' + e.tags.map(function (t) { return '<span class="tag">' + esc(t) + '</span>'; }).join('') + '</div>'
      : '';

    var range = single ? 'Single book' : summarizeIssues(e.issues);
    var link = linkFor(e, nextIssue(e).label);
    var svc = serviceFor(e);

    /* unread -> start, reading -> mark the whole run read, finished -> reset */
    var next = {
      unread: { label: 'Start', hint: 'Mark this run as started' },
      reading: { label: 'Finish', hint: 'Tick every issue' },
      finished: { label: 'Reset', hint: 'Clear every tick' }
    }[status];

    el.innerHTML =
      '<div class="card-main">' +
        (draggable ? '<span class="drag-handle" title="Drag to reorder">☰</span>' : '') +
        '<div class="cover">' + coverInner + '</div>' +
        '<span class="badge ' + status + '">' + esc(STATUSES[status]) + '</span>' +
        '<div class="card-body">' +
          '<div class="card-head">' +
            '<div class="card-title">' + esc(e.series) + '</div>' +
            (e.title ? '<div class="card-arc">' + esc(e.title) + '</div>' : '') +
          '</div>' +
          '<div class="card-issues">' + esc(range) + '</div>' +
          metas +
          '<div class="entry-progress" title="' + done + ' of ' + total + ' issues read">' +
            '<div class="entry-bar"><div class="entry-fill" style="width:' + pct + '%"></div></div>' +
            '<span class="entry-count">' + done + '/' + total + '</span>' +
          '</div>' +
          (e.rating ? '<div class="card-stars" title="' + e.rating + ' out of 5">' + stars(e.rating) + '</div>' : '') +
          (e.notes ? '<div class="card-notes">' + esc(e.notes) + '</div>' : '') +
          tags +
          '<div class="card-actions">' +
            '<button class="btn small" data-act="cycle" title="' + esc(next.hint) + '">' + next.label + '</button>' +
            '<button class="btn ghost small" data-act="toggle" aria-expanded="' + (ui.expanded[e.id] ? 'true' : 'false') + '">' +
              'Issues ' + (ui.expanded[e.id] ? '▴' : '▾') + '</button>' +
            (link
              ? '<a class="btn ghost small" href="' + esc(link) + '" target="_blank" rel="noopener noreferrer" ' +
                'title="' + esc((e.url ? 'Open direct link' : 'Search ' + svc.name) + (single ? '' : ' — #' + nextIssue(e).label)) + '">Read ↗</a>'
              : '') +
            '<button class="btn ghost small icon-act" data-act="edit" title="Edit" ' +
              'aria-label="Edit ' + esc(e.series) + '">✎</button>' +
            '<button class="btn ghost small icon-act danger" data-act="remove" title="Remove" ' +
              'aria-label="Remove ' + esc(e.series) + '">×</button>' +
          '</div>' +
        '</div>' +
      '</div>' +
      (ui.expanded[e.id] ? issueTray(e) : '');

    var img = el.querySelector('img');
    if (img) {
      img.addEventListener('error', function () {
        var holder = img.parentNode;
        img.remove();
        var fb = document.createElement('div');
        fb.className = 'cover-fallback';
        fb.textContent = e.series;
        holder.insertBefore(fb, holder.firstChild);
      });
    }

    el.addEventListener('click', function (ev) {
      var btn = ev.target.closest('[data-act]');
      if (!btn) return;
      var act = btn.dataset.act;
      if (act === 'cycle') cycleEntry(e.id);
      else if (act === 'toggle') toggleTray(e.id);
      else if (act === 'edit') openEntryDialog(e.id);
      else if (act === 'remove') removeEntry(e.id);
      else if (act === 'issue') toggleIssue(e.id, parseInt(btn.dataset.idx, 10));
      else if (act === 'all') setAllIssues(e.id, true);
      else if (act === 'none') setAllIssues(e.id, false);
    });

    if (draggable) enableDrag(el);
    return el;
  }

  function issueTray(e) {
    var single = e.issues.length === 1 && !e.issues[0].label;
    var pills = e.issues.map(function (is, idx) {
      var url = linkFor(e, is.label);
      var label = is.label || 'Whole book';
      return '<span class="pill' + (is.done ? ' is-done' : '') + '">' +
        '<button type="button" class="pill-tick" data-act="issue" data-idx="' + idx + '" ' +
          'aria-pressed="' + (is.done ? 'true' : 'false') + '" ' +
          'title="' + (is.done ? 'Mark unread' : 'Mark read') + '">' +
          '<span class="pill-box" aria-hidden="true">' + (is.done ? '✓' : '') + '</span>' +
          '<span class="pill-label">' + esc(label) + '</span>' +
        '</button>' +
        (url
          ? '<a class="pill-link" href="' + esc(url) + '" target="_blank" rel="noopener noreferrer" ' +
            'aria-label="Open ' + esc(e.series + ' ' + label) + '" title="Open">↗</a>'
          : '') +
        '</span>';
    }).join('');

    return '<div class="issue-tray">' +
      '<div class="tray-head">' +
        '<span class="tray-title">' + (single ? 'Book' : plural(e.issues.length, 'issue')) + '</span>' +
        '<button class="btn ghost small" data-act="all">Mark all</button>' +
        '<button class="btn ghost small" data-act="none">Clear</button>' +
      '</div>' +
      '<div class="pills">' + pills + '</div>' +
    '</div>';
  }

  /* Re-render one card in place. Ticking issues one after another shouldn't
     rebuild the whole page or steal focus mid-run. */
  function refreshEntry(id, focusIdx) {
    var e = findEntry(id);
    var el = document.querySelector('.card[data-id="' + id + '"]');
    if (!e || !el) { render(); return; }
    var draggable = el.querySelector('.drag-handle') !== null;
    var fresh = card(e, draggable);
    el.parentNode.replaceChild(fresh, el);
    renderHeader();
    renderSidebar();
    if (typeof focusIdx === 'number') {
      var btn = fresh.querySelector('[data-act="issue"][data-idx="' + focusIdx + '"]');
      if (btn) btn.focus();
    }
  }

  /* ---------------- entry actions ---------------- */

  function toggleTray(id) {
    ui.expanded[id] = !ui.expanded[id];
    refreshEntry(id);
  }

  function toggleIssue(id, idx) {
    var e = findEntry(id);
    if (!e || !e.issues[idx]) return;
    e.issues[idx].done = !e.issues[idx].done;
    if (e.issues[idx].done) e.started = true;
    save();
    refreshEntry(id, idx);
  }

  function setAllIssues(id, done) {
    var e = findEntry(id);
    if (!e) return;
    e.issues.forEach(function (i) { i.done = done; });
    if (!done) e.started = false;
    save();
    refreshEntry(id);
  }

  function cycleEntry(id) {
    var e = findEntry(id);
    if (!e) return;
    var status = statusOf(e);
    if (status === 'unread') e.started = true;
    else if (status === 'reading') e.issues.forEach(function (i) { i.done = true; });
    else { e.issues.forEach(function (i) { i.done = false; }); e.started = false; }
    save();
    refreshEntry(id);
  }

  function removeEntry(id) {
    var list = activeList();
    var e = findEntry(id);
    if (!e) return;
    confirmAction('Remove entry?', '“' + entryLabel(e) + '” will be removed from ' + list.name + '.', 'Remove')
      .then(function (ok) {
        if (!ok) return;
        list.entries = list.entries.filter(function (x) { return x.id !== id; });
        delete ui.expanded[id];
        save();
        render();
        toast('Removed');
      });
  }

  function entryLabel(e) {
    return e.title ? e.series + ' — ' + e.title : e.series;
  }

  /* ---------------- drag reorder ---------------- */

  var dragId = null;

  function enableDrag(el) {
    el.draggable = true;
    el.addEventListener('dragstart', function (ev) {
      dragId = el.dataset.id;
      el.classList.add('dragging');
      ev.dataTransfer.effectAllowed = 'move';
      try { ev.dataTransfer.setData('text/plain', dragId); } catch (e) { /* ignore */ }
    });
    el.addEventListener('dragend', function () {
      el.classList.remove('dragging');
      dragId = null;
      document.querySelectorAll('.drop-target').forEach(function (n) { n.classList.remove('drop-target'); });
    });
    el.addEventListener('dragover', function (ev) {
      if (!dragId || dragId === el.dataset.id) return;
      ev.preventDefault();
      ev.dataTransfer.dropEffect = 'move';
      el.classList.add('drop-target');
    });
    el.addEventListener('dragleave', function () { el.classList.remove('drop-target'); });
    el.addEventListener('drop', function (ev) {
      ev.preventDefault();
      el.classList.remove('drop-target');
      if (!dragId || dragId === el.dataset.id) return;
      moveEntry(dragId, el.dataset.id);
    });
  }

  function moveEntry(fromId, toId) {
    var entries = activeList().entries;
    var from = entries.findIndex(function (e) { return e.id === fromId; });
    var to = entries.findIndex(function (e) { return e.id === toId; });
    if (from < 0 || to < 0) return;
    entries.splice(to, 0, entries.splice(from, 1)[0]);
    save();
    renderEntries();
  }

  /* ---------------- entry dialog ---------------- */

  /* Re-typing the issue list must not wipe read progress: ticks follow their label. */
  function mergeDone(oldIssues, labels) {
    var pool = {};
    (oldIssues || []).forEach(function (i) {
      if (!i.done) return;
      pool[i.label] = (pool[i.label] || 0) + 1;
    });
    return labels.map(function (l) {
      if (pool[l] > 0) { pool[l]--; return { label: l, done: true }; }
      return { label: l, done: false };
    });
  }

  function openEntryDialog(id) {
    editingId = id || null;
    var form = $('entryForm');
    form.reset();
    $('dialogTitle').textContent = id ? 'Edit entry' : 'Add a run or arc';
    $('saveEntryBtn').textContent = id ? 'Save changes' : 'Add to playlist';
    form.service.value = '';

    if (id) {
      var e = findEntry(id);
      if (e) {
        form.series.value = e.series;
        form.title.value = e.title;
        form.issues.value = summarizeIssues(e.issues);
        form.started.checked = e.started;
        form.writer.value = e.writer;
        form.artist.value = e.artist;
        form.publisher.value = e.publisher;
        form.year.value = e.year;
        form.service.value = e.service;
        form.url.value = e.url;
        form.cover.value = e.cover;
        form.tags.value = e.tags.join(', ');
        form.notes.value = e.notes;
        form.rating.value = String(e.rating);
      }
    }
    $('entryDialog').showModal();
    $('f_series').focus();
  }

  function saveEntryFromForm() {
    var form = $('entryForm');
    var series = str(form.series.value, 200);
    if (!series) { toast('A series name is required.'); return; }

    var parsed = parseIssueSpec(form.issues.value);
    var labels = parsed.labels.length ? parsed.labels : [''];
    if (parsed.truncated) toast('Issue list capped at ' + MAX_ISSUES + '.');

    var list = activeList();
    var prev = editingId ? findEntry(editingId) : null;

    var data = {
      id: prev ? prev.id : uid(),
      series: series,
      title: form.title.value,
      issues: mergeDone(prev ? prev.issues : [], labels),
      started: form.started.checked,
      writer: form.writer.value,
      artist: form.artist.value,
      publisher: form.publisher.value,
      year: form.year.value,
      service: form.service.value,
      url: form.url.value,
      cover: form.cover.value,
      tags: form.tags.value.split(',').map(function (t) { return t.trim(); }).filter(Boolean),
      notes: form.notes.value,
      rating: form.rating.value,
      addedAt: prev ? prev.addedAt : Date.now()
    };

    if (prev) {
      var idx = list.entries.findIndex(function (x) { return x.id === editingId; });
      list.entries[idx] = sanitizeEntry(data);
      toast('Saved');
    } else {
      list.entries.push(sanitizeEntry(data));
      toast('Added to ' + list.name);
    }
    editingId = null;
    save();
    render();
  }

  /* ---------------- bulk add ---------------- */

  function updateBulkPreview() {
    var res = parseBulkLines($('bulkText').value);
    var bits = [];
    if (!res.entries.length) bits.push('Nothing to add yet');
    else bits.push(plural(res.entries.length, 'entry', 'entries') + ' · ' + plural(res.issues, 'issue'));
    if (res.skipped) bits.push(plural(res.skipped, 'line') + ' skipped');
    if (res.truncated) bits.push('capped');
    $('bulkPreview').textContent = bits.join(' · ');
    $('bulkAddBtn').disabled = !res.entries.length;
  }

  function addBulkFromForm() {
    var res = parseBulkLines($('bulkText').value);
    if (!res.entries.length) return;
    var list = activeList();
    res.entries.forEach(function (e) {
      list.entries.push(sanitizeEntry({ series: e.series, title: e.title, issues: e.issues }));
    });
    save();
    render();
    toast('Added ' + plural(res.entries.length, 'entry', 'entries') + ' · ' + plural(res.issues, 'issue'));
  }

  /* ---------------- services dialog ---------------- */

  function openServicesDialog() {
    var wrap = $('servicesFields');
    wrap.innerHTML = state.prefs.services.map(function (s) {
      return '<div class="service-row">' +
        '<label class="field"><span>Name</span>' +
          '<input data-svc="name" data-id="' + esc(s.id) + '" maxlength="60" value="' + esc(s.name) + '"></label>' +
        '<label class="field"><span>Search URL template</span>' +
          '<input data-svc="template" data-id="' + esc(s.id) + '" maxlength="500" ' +
          'placeholder="https://example.com/search?q={q}" value="' + esc(s.template) + '"></label>' +
      '</div>';
    }).join('');
    $('servicesDialog').showModal();
  }

  function saveServicesFromForm() {
    var inputs = $('servicesFields').querySelectorAll('[data-svc]');
    var draft = {};
    state.prefs.services.forEach(function (s) { draft[s.id] = { id: s.id, name: s.name, template: s.template }; });

    var rejected = 0;
    Array.prototype.forEach.call(inputs, function (input) {
      var id = input.dataset.id;
      if (!draft[id]) return;
      if (input.dataset.svc === 'name') {
        draft[id].name = str(input.value, 60) || draft[id].name;
      } else {
        var t = str(input.value, 500);
        var ok = safeUrl(t, 500);
        if (t && !ok) rejected++;
        else draft[id].template = ok;
      }
    });

    state.prefs.services = sanitizeServices(Object.keys(draft).map(function (k) { return draft[k]; }));
    save();
    fillServiceSelects();      /* a renamed service has to show up in the pickers too */
    render();
    toast(rejected ? 'Saved — ' + plural(rejected, 'template') + ' ignored (needs http:// or https://)' : 'Services saved');
  }

  /* ---------------- share ---------------- */

  function refreshShareLink() {
    var list = activeList();
    var include = $('shareProgress').checked;
    $('shareUrl').value = 'Building link…';
    shareUrl(list, include).then(function (url) {
      $('shareUrl').value = url;
      var p = listProgress(list);
      $('shareMeta').textContent = plural(list.entries.length, 'entry', 'entries') + ' · ' +
        plural(p.total, 'issue') + ' · ' + url.length.toLocaleString() + ' characters';
      $('shareWarn').hidden = url.length < 8000;
    }).catch(function () {
      $('shareUrl').value = '';
      $('shareMeta').textContent = 'Could not build a link for this playlist.';
    });
  }

  function copyShareLink() {
    var input = $('shareUrl');
    if (!input.value) return;
    var done = function () { toast('Link copied'); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(input.value).then(done, function () { legacyCopy(input, done); });
    } else {
      legacyCopy(input, done);
    }
  }

  function legacyCopy(input, done) {
    input.removeAttribute('readonly');
    input.select();
    try { document.execCommand('copy'); done(); }
    catch (e) { toast('Press Ctrl/Cmd+C to copy.'); }
    input.setAttribute('readonly', 'readonly');
  }

  var pendingShare = null;

  function handleIncomingHash() {
    var m = /[#&]list=([A-Za-z0-9\-_]+)/.exec(location.hash || '');
    if (!m) return;
    /* Clear the hash first: a bad payload shouldn't re-prompt on every reload. */
    try { history.replaceState(null, '', location.pathname + location.search); } catch (e) { location.hash = ''; }

    decodeShare(m[1]).then(function (obj) {
      var list = unpackList(obj);
      if (!list || !list.entries.length) { toast('That share link had nothing readable in it.'); return; }
      pendingShare = list;
      var issues = listProgress(list).total;
      $('incomingName').textContent = list.name;
      $('incomingMeta').textContent = plural(list.entries.length, 'entry', 'entries') + ' · ' + plural(issues, 'issue');
      $('incomingDialog').showModal();
    }).catch(function () {
      toast('That share link could not be read.');
    });
  }

  function acceptIncoming() {
    if (!pendingShare) return;
    var list = pendingShare;
    pendingShare = null;
    if (state.lists.some(function (l) { return l.name === list.name; })) list.name = list.name + ' (shared)';
    state.lists.push(list);
    state.activeListId = list.id;
    ui.expanded = {};
    save();
    render();
    toast('Added ' + list.name);
  }

  /* ---------------- list actions ---------------- */

  function promptFor(title, label, initial) {
    return new Promise(function (resolve) {
      var dlg = $('promptDialog');
      $('promptTitle').textContent = title;
      $('promptLabel').textContent = label;
      $('promptInput').value = initial || '';
      function onClose() {
        dlg.removeEventListener('close', onClose);
        resolve(dlg.returnValue === 'ok' ? $('promptInput').value.trim() : null);
      }
      dlg.addEventListener('close', onClose);
      dlg.showModal();
      $('promptInput').select();
    });
  }

  function confirmAction(title, text, okLabel) {
    return new Promise(function (resolve) {
      var dlg = $('confirmDialog');
      $('confirmTitle').textContent = title;
      $('confirmText').textContent = text;
      $('confirmOk').textContent = okLabel || 'Delete';
      function onClose() {
        dlg.removeEventListener('close', onClose);
        resolve(dlg.returnValue === 'ok');
      }
      dlg.addEventListener('close', onClose);
      dlg.showModal();
    });
  }

  function newList() {
    promptFor('New playlist', 'Playlist name', '').then(function (name) {
      if (!name) return;
      var list = { id: uid(), name: str(name, 80), service: activeList().service, createdAt: Date.now(), entries: [] };
      state.lists.push(list);
      state.activeListId = list.id;
      ui.expanded = {};
      save();
      render();
      toast('Created ' + list.name);
    });
  }

  function renameList() {
    var list = activeList();
    promptFor('Rename playlist', 'Playlist name', list.name).then(function (name) {
      if (!name) return;
      list.name = str(name, 80);
      save();
      render();
    });
  }

  function deleteList() {
    if (state.lists.length <= 1) { toast('You need at least one playlist.'); return; }
    var list = activeList();
    confirmAction('Delete playlist?', '“' + list.name + '” and its ' +
      plural(list.entries.length, 'entry', 'entries') + ' will be deleted. This cannot be undone.',
      'Delete playlist').then(function (ok) {
      if (!ok) return;
      state.lists = state.lists.filter(function (l) { return l.id !== list.id; });
      state.activeListId = state.lists[0].id;
      ui.expanded = {};
      save();
      render();
      toast('Playlist deleted');
    });
  }

  /* ---------------- import / export ---------------- */

  function exportJson() {
    var payload = JSON.stringify({
      version: SCHEMA_VERSION,
      exportedAt: new Date().toISOString(),
      lists: state.lists,
      services: state.prefs.services
    }, null, 2);
    var blob = new Blob([payload], { type: 'application/json' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = 'longbox-' + new Date().toISOString().slice(0, 10) + '.json';
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
    toast('Backup downloaded');
  }

  function importJson(file) {
    var reader = new FileReader();
    reader.onload = function () {
      var incoming = null;
      try {
        var parsed = JSON.parse(String(reader.result));
        /* Old v1 backups are still importable — they get migrated on the way in. */
        var looksV1 = parsed && (parsed.version === 1 ||
          (Array.isArray(parsed.lists) && parsed.lists.some(function (l) { return l && Array.isArray(l.items); })));
        incoming = sanitizeLists(looksV1 ? migrateV1(parsed).lists : parsed.lists);
      } catch (e) {
        incoming = null;
      }
      if (!incoming || !incoming.length) { toast('That file has no readable playlists.'); return; }
      incoming.forEach(function (l) {
        l.id = uid();
        if (state.lists.some(function (x) { return x.name === l.name; })) l.name = l.name + ' (imported)';
        state.lists.push(l);
      });
      state.activeListId = state.lists[state.lists.length - 1].id;
      ui.expanded = {};
      save();
      render();
      toast('Imported ' + plural(incoming.length, 'playlist'));
    };
    reader.onerror = function () { toast('Could not read that file.'); };
    reader.readAsText(file);
  }

  /* ---------------- theme ---------------- */

  function applyTheme() {
    document.documentElement.setAttribute('data-theme', state.prefs.theme);
    $('themeBtn').textContent = state.prefs.theme === 'dark' ? '☽' : '☀';
  }

  /* ---------------- wiring ---------------- */

  function fillServiceSelects() {
    var listOpts = state.prefs.services.map(function (s) {
      return '<option value="' + esc(s.id) + '">' + esc(s.name) + '</option>';
    }).join('');
    $('listService').innerHTML = listOpts;
    $('f_service').innerHTML = '<option value="">Playlist default</option>' + listOpts;
  }

  function init() {
    applyTheme();
    fillServiceSelects();
    $('sort').value = ui.sort;
    $('gridViewBtn').classList.toggle('is-active', ui.view === 'grid');
    $('listViewBtn').classList.toggle('is-active', ui.view === 'list');

    $('addEntryBtn').addEventListener('click', function () { openEntryDialog(null); });
    $('emptyAddBtn').addEventListener('click', function () { openEntryDialog(null); });
    $('bulkBtn').addEventListener('click', openBulkDialog);
    $('emptyBulkBtn').addEventListener('click', openBulkDialog);
    $('newListBtn').addEventListener('click', newList);
    $('renameListBtn').addEventListener('click', renameList);
    $('deleteListBtn').addEventListener('click', deleteList);
    /* Two ways in: the topbar button gives way on narrow screens, the sidebar one never does. */
    $('servicesBtn').addEventListener('click', openServicesDialog);
    $('servicesBtnAlt').addEventListener('click', function () {
      $('sidebar').classList.remove('open');
      openServicesDialog();
    });

    $('shareBtn').addEventListener('click', function () {
      $('shareDialog').showModal();
      refreshShareLink();
    });
    $('shareProgress').addEventListener('change', refreshShareLink);
    $('shareCopyBtn').addEventListener('click', function (ev) { ev.preventDefault(); copyShareLink(); });

    $('incomingDialog').addEventListener('close', function () {
      if ($('incomingDialog').returnValue === 'ok') acceptIncoming();
      else pendingShare = null;
    });

    $('listService').addEventListener('change', function (e) {
      activeList().service = e.target.value;
      save();
      renderEntries();
    });

    $('entryDialog').addEventListener('close', function () {
      if ($('entryDialog').returnValue === 'save') saveEntryFromForm();
      else editingId = null;
    });

    $('bulkDialog').addEventListener('close', function () {
      if ($('bulkDialog').returnValue === 'add') addBulkFromForm();
    });

    $('servicesDialog').addEventListener('close', function () {
      if ($('servicesDialog').returnValue === 'save') saveServicesFromForm();
    });

    $('bulkText').addEventListener('input', updateBulkPreview);

    $('search').addEventListener('input', function (e) {
      ui.query = e.target.value;
      renderEntries();
    });

    $('statusFilter').addEventListener('click', function (e) {
      var chip = e.target.closest('.chip');
      if (!chip) return;
      ui.status = chip.dataset.status;
      Array.prototype.forEach.call(this.querySelectorAll('.chip'), function (c) {
        c.classList.toggle('is-active', c === chip);
      });
      renderEntries();
    });

    $('sort').addEventListener('change', function (e) {
      ui.sort = e.target.value;
      save();
      renderEntries();
    });

    $('gridViewBtn').addEventListener('click', function () { setView('grid'); });
    $('listViewBtn').addEventListener('click', function () { setView('list'); });

    $('exportBtn').addEventListener('click', exportJson);
    $('importBtn').addEventListener('click', function () { $('importFile').click(); });
    $('importFile').addEventListener('change', function (e) {
      if (e.target.files && e.target.files[0]) importJson(e.target.files[0]);
      e.target.value = '';
    });

    $('themeBtn').addEventListener('click', function () {
      state.prefs.theme = state.prefs.theme === 'dark' ? 'light' : 'dark';
      applyTheme();
      save();
    });

    $('menuToggle').addEventListener('click', function () {
      $('sidebar').classList.toggle('open');
    });

    document.addEventListener('keydown', function (e) {
      var typing = /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName);
      if (typing || e.metaKey || e.ctrlKey || e.altKey) return;
      if (document.querySelector('dialog[open]')) return;
      if (e.key === '/') { e.preventDefault(); $('search').focus(); }
      else if (e.key === 'n') { e.preventDefault(); openEntryDialog(null); }
      else if (e.key === 'b') { e.preventDefault(); openBulkDialog(); }
    });

    render();
    if (migratedFromV1) {
      save();
      toast('Brought your old list over — issues are now tickable.');
    }
    handleIncomingHash();
  }

  function openBulkDialog() {
    $('bulkText').value = '';
    updateBulkPreview();
    $('bulkDialog').showModal();
    $('bulkText').focus();
  }

  function setView(view) {
    ui.view = view;
    $('gridViewBtn').classList.toggle('is-active', view === 'grid');
    $('listViewBtn').classList.toggle('is-active', view === 'list');
    save();
    renderEntries();
  }

  /* A small, deliberate test surface: the parsers and the share codec are pure
     functions and are far easier to check directly than through the DOM. */
  window.__longbox = {
    parseIssueSpec: parseIssueSpec,
    summarizeIssues: summarizeIssues,
    parseBulkLines: parseBulkLines,
    packList: packList,
    unpackList: unpackList,
    encodeShare: encodeShare,
    decodeShare: decodeShare,
    migrateV1: migrateV1,
    statusOf: statusOf,
    listProgress: listProgress,
    state: function () { return state; }
  };

  document.addEventListener('DOMContentLoaded', init);
})();
