/* Longbox — a comic book reading list tracker.
   No build step, no backend: state lives in localStorage and travels by JSON export. */
(function () {
  'use strict';

  var STORAGE_KEY = 'longbox.state.v1';
  var SCHEMA_VERSION = 1;
  var STATUSES = { unread: 'Want to read', reading: 'Reading', read: 'Read' };

  /* ---------------- state ---------------- */

  var state = load();
  var ui = {
    query: '',
    status: 'all',
    sort: state.prefs.sort || 'manual',
    view: state.prefs.view || 'grid'
  };
  var editingId = null;

  function uid() {
    return 'c' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  }

  function blankState() {
    return {
      version: SCHEMA_VERSION,
      lists: [{ id: uid(), name: 'My reading list', createdAt: Date.now(), items: [] }],
      activeListId: null,
      prefs: { theme: 'dark', sort: 'manual', view: 'grid' }
    };
  }

  function load() {
    var fresh = blankState();
    var raw;
    try { raw = localStorage.getItem(STORAGE_KEY); } catch (e) { raw = null; }
    if (!raw) { fresh.activeListId = fresh.lists[0].id; return fresh; }
    try {
      var parsed = JSON.parse(raw);
      var lists = sanitizeLists(parsed && parsed.lists);
      if (!lists.length) lists = fresh.lists;
      var prefs = (parsed && parsed.prefs) || {};
      return {
        version: SCHEMA_VERSION,
        lists: lists,
        activeListId: lists.some(function (l) { return l.id === (parsed && parsed.activeListId); })
          ? parsed.activeListId : lists[0].id,
        prefs: {
          theme: prefs.theme === 'light' ? 'light' : 'dark',
          sort: typeof prefs.sort === 'string' ? prefs.sort : 'manual',
          view: prefs.view === 'list' ? 'list' : 'grid'
        }
      };
    } catch (e) {
      fresh.activeListId = fresh.lists[0].id;
      return fresh;
    }
  }

  function sanitizeLists(raw) {
    if (!Array.isArray(raw)) return [];
    return raw.filter(Boolean).map(function (l) {
      return {
        id: typeof l.id === 'string' && l.id ? l.id : uid(),
        name: str(l.name, 80) || 'Untitled list',
        createdAt: typeof l.createdAt === 'number' ? l.createdAt : Date.now(),
        items: Array.isArray(l.items) ? l.items.filter(Boolean).map(sanitizeItem) : []
      };
    });
  }

  function sanitizeItem(it) {
    return {
      id: typeof it.id === 'string' && it.id ? it.id : uid(),
      title: str(it.title, 200) || 'Untitled',
      series: str(it.series, 200),
      issue: str(it.issue, 40),
      writer: str(it.writer, 200),
      artist: str(it.artist, 200),
      publisher: str(it.publisher, 120),
      year: numOrEmpty(it.year),
      status: STATUSES[it.status] ? it.status : 'unread',
      rating: Math.max(0, Math.min(5, parseInt(it.rating, 10) || 0)),
      cover: safeUrl(it.cover),
      tags: Array.isArray(it.tags) ? it.tags.map(function (t) { return str(t, 40); }).filter(Boolean).slice(0, 20) : [],
      notes: str(it.notes, 2000),
      addedAt: typeof it.addedAt === 'number' ? it.addedAt : Date.now(),
      finishedAt: typeof it.finishedAt === 'number' ? it.finishedAt : null
    };
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

  /* Only allow http(s) covers — keeps pasted javascript:/data: URLs out of the DOM. */
  function safeUrl(v) {
    if (typeof v !== 'string') return '';
    var s = v.trim();
    if (!s) return '';
    if (!/^https?:\/\//i.test(s)) return '';
    return s.slice(0, 2000);
  }

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
    el.textContent = msg;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.hidden = true; }, 2600);
  }

  /* ---------------- rendering ---------------- */

  function render() {
    renderSidebar();
    renderHeader();
    renderComics();
  }

  function renderSidebar() {
    var nav = $('listNav');
    nav.innerHTML = '';
    state.lists.forEach(function (list) {
      var li = document.createElement('li');
      var btn = document.createElement('button');
      btn.className = list.id === state.activeListId ? 'is-active' : '';
      btn.type = 'button';
      var read = list.items.filter(function (i) { return i.status === 'read'; }).length;
      btn.innerHTML = '<span class="nav-name">' + esc(list.name) + '</span>' +
        '<span class="count">' + read + '/' + list.items.length + '</span>';
      btn.addEventListener('click', function () {
        state.activeListId = list.id;
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
    var items = list.items;
    $('listTitle').textContent = list.name;
    $('deleteListBtn').disabled = state.lists.length <= 1;

    var read = items.filter(function (i) { return i.status === 'read'; }).length;
    var reading = items.filter(function (i) { return i.status === 'reading'; }).length;
    var rated = items.filter(function (i) { return i.rating > 0; });
    var avg = rated.length
      ? (rated.reduce(function (a, i) { return a + i.rating; }, 0) / rated.length).toFixed(1)
      : null;

    var parts = [
      '<span><b>' + items.length + '</b> in list</span>',
      '<span><b>' + read + '</b> read</span>',
      '<span><b>' + reading + '</b> reading</span>',
      '<span><b>' + (items.length - read - reading) + '</b> to read</span>'
    ];
    if (avg) parts.push('<span><b>' + avg + '</b> avg rating</span>');
    $('stats').innerHTML = parts.join('');

    var pct = items.length ? Math.round((read / items.length) * 100) : 0;
    $('progressFill').style.width = pct + '%';
    $('progressBar').setAttribute('aria-valuenow', String(pct));
  }

  function visibleItems() {
    var items = activeList().items.slice();
    var q = ui.query.trim().toLowerCase();

    if (ui.status !== 'all') {
      items = items.filter(function (i) { return i.status === ui.status; });
    }
    if (q) {
      items = items.filter(function (i) {
        return [i.title, i.series, i.issue, i.writer, i.artist, i.publisher, i.notes, i.tags.join(' ')]
          .join(' ').toLowerCase().indexOf(q) !== -1;
      });
    }

    var by = {
      added: function (a, b) { return b.addedAt - a.addedAt; },
      title: function (a, b) { return a.title.localeCompare(b.title); },
      rating: function (a, b) { return b.rating - a.rating || a.title.localeCompare(b.title); },
      year: function (a, b) { return (Number(b.year) || 0) - (Number(a.year) || 0); },
      series: function (a, b) {
        var s = (a.series || a.title).localeCompare(b.series || b.title);
        if (s !== 0) return s;
        return issueNum(a.issue) - issueNum(b.issue);
      }
    };
    if (by[ui.sort]) items.sort(by[ui.sort]);
    return items;
  }

  function issueNum(v) {
    var m = String(v || '').match(/\d+/);
    return m ? parseInt(m[0], 10) : Number.MAX_SAFE_INTEGER;
  }

  function stars(n) {
    return n > 0 ? '★'.repeat(n) + '☆'.repeat(5 - n) : '';
  }

  function subtitle(it) {
    var bits = [];
    if (it.series && it.series !== it.title) bits.push(it.series);
    if (it.issue) bits.push(it.issue);
    var line1 = bits.join(' ');
    var line2 = [it.writer, it.artist].filter(Boolean).join(' / ');
    var line3 = [it.publisher, it.year].filter(function (x) { return x !== '' && x != null; }).join(' · ');
    return [line1, line2, line3].filter(Boolean);
  }

  function renderComics() {
    var wrap = $('comics');
    var items = visibleItems();
    var total = activeList().items.length;

    wrap.className = 'comics ' + (ui.view === 'list' ? 'list-view' : 'grid-view');
    wrap.innerHTML = '';

    var empty = $('empty');
    if (!items.length) {
      empty.hidden = false;
      if (total === 0) {
        $('emptyTitle').textContent = 'Nothing here yet';
        $('emptyText').textContent = 'Add your first comic to start building this list.';
        $('emptyAddBtn').hidden = false;
      } else {
        $('emptyTitle').textContent = 'No matches';
        $('emptyText').textContent = 'No comics in this list match your search or filter.';
        $('emptyAddBtn').hidden = true;
      }
      return;
    }
    empty.hidden = true;

    var draggable = ui.sort === 'manual' && ui.view === 'list' && !ui.query && ui.status === 'all';

    items.forEach(function (it) {
      wrap.appendChild(card(it, draggable));
    });
  }

  function card(it, draggable) {
    var el = document.createElement('article');
    el.className = 'card';
    el.dataset.id = it.id;

    var subs = subtitle(it).map(function (s) {
      return '<div class="card-sub">' + esc(s) + '</div>';
    }).join('');

    var coverInner = it.cover
      ? '<img alt="" loading="lazy" src="' + esc(it.cover) + '">'
      : '<div class="cover-fallback">' + esc(it.series || it.title) + '</div>';

    var tags = it.tags.length
      ? '<div class="tags">' + it.tags.map(function (t) { return '<span class="tag">' + esc(t) + '</span>'; }).join('') + '</div>'
      : '';

    /* The status button advances unread -> reading -> read -> unread. */
    var next = {
      unread:  { label: 'Start',  hint: 'Mark as currently reading' },
      reading: { label: 'Finish', hint: 'Mark as read' },
      read:    { label: 'Unread', hint: 'Move back to want to read' }
    }[it.status];

    /* The badge is a direct child of the card so each view can place it:
       overlaid on the cover in grid view, as its own column in list view. */
    el.innerHTML =
      (draggable ? '<span class="drag-handle" title="Drag to reorder">☰</span>' : '') +
      '<div class="cover">' + coverInner + '</div>' +
      '<span class="badge ' + it.status + '">' + esc(STATUSES[it.status]) + '</span>' +
      '<div class="card-body">' +
        '<div class="card-title">' + esc(it.title) + '</div>' +
        subs +
        (it.rating ? '<div class="card-stars" title="' + it.rating + ' out of 5">' + stars(it.rating) + '</div>' : '') +
        (it.notes ? '<div class="card-notes">' + esc(it.notes) + '</div>' : '') +
        tags +
        '<div class="card-actions">' +
          '<button class="btn small" data-act="cycle" title="' + esc(next.hint) + '">' + next.label + '</button>' +
          '<button class="btn ghost small icon-act" data-act="edit" title="Edit" ' +
            'aria-label="Edit ' + esc(it.title) + '">✎</button>' +
          '<button class="btn ghost small icon-act danger" data-act="remove" title="Remove" ' +
            'aria-label="Remove ' + esc(it.title) + '">×</button>' +
        '</div>' +
      '</div>';

    var img = el.querySelector('img');
    if (img) {
      img.addEventListener('error', function () {
        var holder = img.parentNode;
        img.remove();
        var fb = document.createElement('div');
        fb.className = 'cover-fallback';
        fb.textContent = it.series || it.title;
        holder.insertBefore(fb, holder.firstChild);
      });
    }

    el.addEventListener('click', function (ev) {
      var btn = ev.target.closest('[data-act]');
      if (!btn) return;
      var act = btn.dataset.act;
      if (act === 'cycle') cycleStatus(it.id);
      else if (act === 'edit') openComicDialog(it.id);
      else if (act === 'remove') removeComic(it.id);
    });

    if (draggable) enableDrag(el);
    return el;
  }

  /* ---------------- drag reorder (list view, custom order) ---------------- */

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
      moveItem(dragId, el.dataset.id);
    });
  }

  function moveItem(fromId, toId) {
    var items = activeList().items;
    var from = items.findIndex(function (i) { return i.id === fromId; });
    var to = items.findIndex(function (i) { return i.id === toId; });
    if (from < 0 || to < 0) return;
    items.splice(to, 0, items.splice(from, 1)[0]);
    save();
    renderComics();
  }

  /* ---------------- comic actions ---------------- */

  function cycleStatus(id) {
    var it = activeList().items.filter(function (i) { return i.id === id; })[0];
    if (!it) return;
    it.status = it.status === 'unread' ? 'reading' : (it.status === 'reading' ? 'read' : 'unread');
    it.finishedAt = it.status === 'read' ? Date.now() : null;
    save();
    render();
  }

  function removeComic(id) {
    var list = activeList();
    var it = list.items.filter(function (i) { return i.id === id; })[0];
    if (!it) return;
    confirmAction('Remove comic?', '“' + it.title + '” will be removed from ' + list.name + '.', 'Remove')
      .then(function (ok) {
        if (!ok) return;
        list.items = list.items.filter(function (i) { return i.id !== id; });
        save();
        render();
        toast('Removed');
      });
  }

  function openComicDialog(id) {
    editingId = id || null;
    var form = $('comicForm');
    form.reset();
    $('formError').hidden = true;
    $('dialogTitle').textContent = id ? 'Edit comic' : 'Add comic';
    $('saveComicBtn').textContent = id ? 'Save changes' : 'Add to list';

    if (id) {
      var it = activeList().items.filter(function (i) { return i.id === id; })[0];
      if (it) {
        form.title.value = it.title;
        form.series.value = it.series;
        form.issue.value = it.issue;
        form.writer.value = it.writer;
        form.artist.value = it.artist;
        form.publisher.value = it.publisher;
        form.year.value = it.year;
        form.status.value = it.status;
        form.rating.value = String(it.rating);
        form.cover.value = it.cover;
        form.tags.value = it.tags.join(', ');
        form.notes.value = it.notes;
      }
    }
    $('comicDialog').showModal();
    $('f_title').focus();
  }

  function saveComicFromForm() {
    var form = $('comicForm');
    var data = {
      title: form.title.value,
      series: form.series.value,
      issue: form.issue.value,
      writer: form.writer.value,
      artist: form.artist.value,
      publisher: form.publisher.value,
      year: form.year.value,
      status: form.status.value,
      rating: form.rating.value,
      cover: form.cover.value,
      tags: form.tags.value.split(',').map(function (t) { return t.trim(); }).filter(Boolean),
      notes: form.notes.value
    };
    if (!str(data.title, 200)) { toast('A title is required.'); return; }

    var list = activeList();
    if (editingId) {
      var idx = list.items.findIndex(function (i) { return i.id === editingId; });
      if (idx > -1) {
        var prev = list.items[idx];
        data.id = prev.id;
        data.addedAt = prev.addedAt;
        data.finishedAt = data.status === 'read' ? (prev.finishedAt || Date.now()) : null;
        list.items[idx] = sanitizeItem(data);
      }
      toast('Saved');
    } else {
      data.id = uid();
      data.addedAt = Date.now();
      data.finishedAt = data.status === 'read' ? Date.now() : null;
      list.items.push(sanitizeItem(data));
      toast('Added to ' + list.name);
    }
    editingId = null;
    save();
    render();
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
    promptFor('New reading list', 'List name', '').then(function (name) {
      if (!name) return;
      var list = { id: uid(), name: str(name, 80), createdAt: Date.now(), items: [] };
      state.lists.push(list);
      state.activeListId = list.id;
      save();
      render();
      toast('Created ' + list.name);
    });
  }

  function renameList() {
    var list = activeList();
    promptFor('Rename list', 'List name', list.name).then(function (name) {
      if (!name) return;
      list.name = str(name, 80);
      save();
      render();
    });
  }

  function deleteList() {
    if (state.lists.length <= 1) { toast('You need at least one list.'); return; }
    var list = activeList();
    confirmAction('Delete list?', '“' + list.name + '” and its ' + list.items.length +
      ' comic(s) will be deleted. This cannot be undone.', 'Delete list').then(function (ok) {
      if (!ok) return;
      state.lists = state.lists.filter(function (l) { return l.id !== list.id; });
      state.activeListId = state.lists[0].id;
      save();
      render();
      toast('List deleted');
    });
  }

  /* ---------------- import / export ---------------- */

  function exportJson() {
    var payload = JSON.stringify({ version: SCHEMA_VERSION, exportedAt: new Date().toISOString(), lists: state.lists }, null, 2);
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
      var incoming;
      try {
        incoming = sanitizeLists(JSON.parse(String(reader.result)).lists);
      } catch (e) {
        incoming = null;
      }
      if (!incoming || !incoming.length) { toast('That file has no readable lists.'); return; }
      incoming.forEach(function (l) {
        l.id = uid();
        if (state.lists.some(function (x) { return x.name === l.name; })) l.name = l.name + ' (imported)';
        state.lists.push(l);
      });
      state.activeListId = state.lists[state.lists.length - 1].id;
      save();
      render();
      toast('Imported ' + incoming.length + ' list(s)');
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

  function init() {
    applyTheme();
    $('sort').value = ui.sort;
    $('gridViewBtn').classList.toggle('is-active', ui.view === 'grid');
    $('listViewBtn').classList.toggle('is-active', ui.view === 'list');

    $('addComicBtn').addEventListener('click', function () { openComicDialog(null); });
    $('emptyAddBtn').addEventListener('click', function () { openComicDialog(null); });
    $('newListBtn').addEventListener('click', newList);
    $('renameListBtn').addEventListener('click', renameList);
    $('deleteListBtn').addEventListener('click', deleteList);

    $('comicDialog').addEventListener('close', function () {
      if ($('comicDialog').returnValue === 'save') saveComicFromForm();
      else editingId = null;
    });

    $('search').addEventListener('input', function (e) {
      ui.query = e.target.value;
      renderComics();
    });

    $('statusFilter').addEventListener('click', function (e) {
      var chip = e.target.closest('.chip');
      if (!chip) return;
      ui.status = chip.dataset.status;
      Array.prototype.forEach.call(this.querySelectorAll('.chip'), function (c) {
        c.classList.toggle('is-active', c === chip);
      });
      renderComics();
    });

    $('sort').addEventListener('change', function (e) {
      ui.sort = e.target.value;
      save();
      renderComics();
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
      else if (e.key === 'n') { e.preventDefault(); openComicDialog(null); }
    });

    render();
  }

  function setView(view) {
    ui.view = view;
    $('gridViewBtn').classList.toggle('is-active', view === 'grid');
    $('listViewBtn').classList.toggle('is-active', view === 'list');
    save();
    renderComics();
  }

  document.addEventListener('DOMContentLoaded', init);
})();
