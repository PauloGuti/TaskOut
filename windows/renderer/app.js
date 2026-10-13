'use strict';
const api = window.taskout;
if (api.acrylic()) document.body.classList.add('acrylic');

// ───────── Datos ─────────
const PALETTE = ['E5675C', 'F0A04B', 'E8C547', '6DBE8C', '4FB3BF', '5B8DEF', '9A7BE0', 'E37FB5', '8E8E93'];
const DEFAULT_CATS = [['Hogar', 'F0A04B'], ['Ejercicio', '6DBE8C'], ['Trabajo', '5B8DEF'], ['Freelance', '9A7BE0'], ['Colegio hija', 'E37FB5'], ['Personal', '4FB3BF']];
const DURATIONS = [['15 min', 15], ['30 min', 30], ['1 h', 60], ['2 h', 120], ['1 día', 1440]];
const SECTION_TITLES = { overdue: 'De antes', today: 'Hoy', tomorrow: 'Mañana', later: 'Más adelante', done: 'Hechas hoy' };
const uid = () => crypto.randomUUID();

let tasks = [];
let categories = DEFAULT_CATS.map(([name, colorHex]) => ({ id: uid(), name, colorHex }));
let calendarOn = false;
let cal = { configured: false, connected: false, account: '' };
let draft;
let selectedID = null, peekID = null, completingID = null, lastDoneID = null;
let showDone = false, notesFocused = false, peeking = false;
let undoTimer = null, toastTimer = null;

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const hm = (d) => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const sod = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const fmtTime = (ms) => new Date(ms).toLocaleTimeString('es-ES', { hour: '2-digit', minute: '2-digit' });
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
const category = (id) => categories.find((c) => c.id === id);
const task = (id) => tasks.find((t) => t.id === id);

function persist() { api.save({ tasks, categories, calendarOn }); }

// ───────── Borrador ─────────
function roundedNow() {
  const step = 300000;
  return new Date(Math.ceil(Date.now() / step) * step);
}
function newDraft(categoryID) {
  const n = roundedNow();
  return { title: '', notes: '', day: ymd(new Date()), time: hm(n), minutes: 60, categoryID: categoryID ?? categories[0]?.id, editingID: null };
}
const draftStart = () => new Date(`${draft.day}T${draft.time || '00:00'}:00`).getTime();
const draftEnd = () => draftStart() + draft.minutes * 60000;
const draftActive = () => !!draft.title || !!draft.notes || !!draft.editingID;

// ───────── Secciones ─────────
function sections() {
  const today = sod(new Date()).getTime();
  const tomorrow = addDays(today, 1).getTime();
  const dayAfter = addDays(today, 2).getTime();
  const open = tasks.filter((t) => !t.done || t.id === completingID).sort((a, b) => a.start - b.start);
  const s = { overdue: [], today: [], tomorrow: [], later: [] };
  for (const t of open) {
    if (t.start < today) (t.end > today ? s.today : s.overdue).push(t);
    else if (t.start < tomorrow) s.today.push(t);
    else if (t.start < dayAfter) s.tomorrow.push(t);
    else s.later.push(t);
  }
  const out = ['overdue', 'today', 'tomorrow', 'later'].map((kind) => ({ kind, tasks: s[kind] }));
  if (showDone) out.push({ kind: 'done', tasks: doneToday() });
  return out.filter((x) => x.tasks.length);
}
function doneToday() {
  const today = sod(new Date()).getTime();
  return tasks.filter((t) => t.done && t.id !== completingID && (t.doneAt || 0) >= today).sort((a, b) => (b.doneAt || 0) - (a.doneAt || 0));
}
const flatIDs = () => sections().flatMap((s) => s.tasks.map((t) => t.id));
function progress() {
  const d = doneToday().length + (completingID ? 1 : 0);
  const secs = sections();
  const openToday = (secs.find((s) => s.kind === 'today')?.tasks || []).filter((t) => t.id !== completingID).length;
  const overdue = secs.find((s) => s.kind === 'overdue')?.tasks.length || 0;
  return { done: d, total: d + openToday + overdue };
}

// ───────── Pintado ─────────
const ICON = {
  cal: '<svg viewBox="0 0 24 24"><rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/></svg>',
  calOn: '<svg viewBox="0 0 24 24"><rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4M9 15l2.2 2.2L15.5 13"/></svg>',
  calWarn: '<svg viewBox="0 0 24 24"><rect x="3.5" y="5" width="17" height="15" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4M12 13v3M12 18.2v.1"/></svg>',
  check: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M8 12.3l2.8 2.8L16 9.5"/></svg>',
  checkFill: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="currentColor"/><path d="M8 12.3l2.8 2.8L16 9.5" stroke="var(--solid)"/></svg>',
  tag: '<svg viewBox="0 0 24 24"><path d="M3.5 12.2V5.5a2 2 0 0 1 2-2h6.7a2 2 0 0 1 1.4.6l7 7a2 2 0 0 1 0 2.8l-6.7 6.7a2 2 0 0 1-2.8 0l-7-7a2 2 0 0 1-.6-1.4z"/><circle cx="8.5" cy="8.5" r="1.2"/></svg>',
};

function renderHeader() {
  $('dateLabel').textContent = cap(new Date().toLocaleDateString('es-ES', { weekday: 'long', day: 'numeric', month: 'long' }));
  const p = progress();
  const frac = p.total ? p.done / p.total : 0;
  $('ringFg').style.strokeDashoffset = 100.5 * (1 - frac);
  $('ringText').textContent = p.total ? `${p.done}/${p.total}` : '·';

  const btn = $('btnCal');
  const denied = !cal.configured;
  btn.className = 'hbtn nodrag' + (denied ? ' warn' : calendarOn && cal.connected ? ' on' : '');
  btn.innerHTML = denied ? ICON.calWarn : calendarOn && cal.connected ? ICON.calOn : ICON.cal;
  btn.title = denied ? 'Falta el ID de aplicación de Microsoft (ver windows/README.md)'
    : !cal.connected ? 'Conectar con el Calendario (Outlook / Microsoft)'
    : calendarOn ? `Sincronizando con ${cal.account || 'tu Calendario'} (clic para pausar)` : 'Sincronizar con el Calendario';
  $('btnDone').className = 'hbtn nodrag' + (showDone ? ' accent' : '');
  $('btnDone').innerHTML = showDone ? ICON.checkFill : ICON.check;
  $('btnCats').innerHTML = ICON.tag;
}

function renderComposer() {
  const cat = category(draft.categoryID);
  const col = cat ? '#' + cat.colorHex : 'var(--accent)';
  const box = $('composer');
  box.style.setProperty('--c', col);
  const editing = !!draft.editingID;
  $('titleIcon').textContent = editing ? '✎' : '+';
  $('title').placeholder = editing ? 'Editando…' : 'Anotar algo…';
  $('submitBtn').hidden = !draft.title;
  $('extra').hidden = !draftActive();
  if ($('title').value !== draft.title) $('title').value = draft.title;
  if ($('notes').value !== draft.notes) $('notes').value = draft.notes;
  $('day').value = draft.day;
  $('time').value = draft.time;
  $('catRow').innerHTML = categories.map((c) =>
    `<button class="chip${draft.categoryID === c.id ? ' sel' : ''}" data-cat="${c.id}" style="--c:#${c.colorHex}"><i></i>${esc(c.name)}</button>`).join('');
  const today = ymd(new Date()), tomorrow = ymd(addDays(new Date(), 1));
  $('chipToday').classList.toggle('sel', draft.day === today);
  $('chipTomorrow').classList.toggle('sel', draft.day === tomorrow);
  const durRow = $('durRow');
  durRow.querySelectorAll('.chip').forEach((n) => n.remove());
  durRow.prepend(...DURATIONS.map(([label, m]) => {
    const b = document.createElement('button');
    b.className = 'chip' + (draft.minutes === m ? ' sel' : '');
    b.textContent = label;
    b.onclick = () => { draft.minutes = m; renderComposer(); };
    return b;
  }));
  $('endLabel').textContent = '→ ' + fmtTime(draftEnd());
}

function rowHTML(t, kind) {
  const cat = category(t.categoryID);
  const color = cat ? '#' + cat.colorHex : '#8E8E93';
  const big = kind === 'today' || kind === 'overdue';
  const completing = t.id === completingID;
  const isDone = t.done || completing;
  const timeFmt = { hour: '2-digit', minute: '2-digit' };
  let label;
  if (kind === 'later' || kind === 'overdue') {
    label = new Date(t.start).toLocaleDateString('es-ES', { weekday: 'short', day: 'numeric', month: 'short' }) + ', ' + fmtTime(t.start);
  } else {
    label = t.end - t.start >= 86400000 ? `${fmtTime(t.start)} · 1 día` : `${fmtTime(t.start)} – ${fmtTime(t.end)}`;
  }
  const peek = t.id === peekID;
  const burst = completing ? `<span class="burst">${Array.from({ length: 8 }, (_, i) => `<b style="--a:${i * 45}deg"></b>`).join('')}</span>` : '';
  return `<div class="row ${kind}${big ? ' big' : ''}${isDone ? ' done' : ''}${completing ? ' completing' : ''}${t.id === selectedID ? ' sel' : ''}" data-id="${t.id}" style="--c:${color}">
    <button class="check" data-check="${t.id}" aria-label="Completar"><span class="c"><svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>${burst}</span></button>
    <div class="main"><div class="title">${esc(t.title)}</div>
      <div class="meta">${label}${cat ? ' · ' + esc(cat.name) : ''}</div></div>
    ${t.notes && !peek ? '<span class="noteicon">≡</span>' : ''}
    ${peek ? `<div class="peek${t.notes ? '' : ' empty'}">${t.notes ? esc(t.notes) : 'Sin notas'}</div>` : ''}
  </div>`;
}

function renderList() {
  const secs = sections();
  const finished = doneToday().length > 0;
  $('list').innerHTML = secs.length
    ? secs.map((s) => `<div class="sec ${s.kind}">${SECTION_TITLES[s.kind]}<span>${s.tasks.length}</span></div>` + s.tasks.map((t) => rowHTML(t, s.kind)).join('')).join('')
    : `<div class="empty"><div class="ico">${finished ? '✨' : '🌿'}</div><h3>${finished ? 'Todo hecho por hoy' : 'Todo en calma'}</h3><p>${finished ? 'Respira. Lo lograste.' : 'Nada pendiente. Escribe arriba para anotar algo.'}</p></div>`;
}

function renderFooter() {
  $('hints').hidden = !!lastDoneID || !$('toast').hidden;
  $('undo').hidden = !lastDoneID;
}

function renderAll() { renderHeader(); renderComposer(); renderList(); renderFooter(); }
function renderTasks() { renderHeader(); renderList(); renderFooter(); }

function paintSelection() {
  document.querySelectorAll('.row').forEach((r) => r.classList.toggle('sel', r.dataset.id === selectedID));
  document.querySelector('.row.sel')?.scrollIntoView({ block: 'nearest' });
}

function toast(msg) {
  const t = $('toast');
  t.textContent = msg;
  t.hidden = false;
  renderFooter();
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; renderFooter(); }, 5000);
}

// ───────── Calendario ─────────
async function sync(id) {
  const t = task(id);
  if (!t || t.done || !calendarOn || !cal.connected) return;
  const r = await api.cal.upsert(t, category(t.categoryID));
  if (!r.ok) { toast('No se pudo sincronizar: ' + r.error); return; }
  const cur = task(id);
  if (cur) { cur.eventID = r.eventID; cur.eventCal = r.eventCal; persist(); }
}
async function syncAll() {
  if (!calendarOn || !cal.connected) return;
  for (const t of tasks.filter((x) => !x.done)) await sync(t.id);
}
async function enableCalendar() {
  if (!cal.connected) {
    toast('Se abrió el navegador para iniciar sesión…');
    const r = await api.cal.connect();
    if (!r.ok) { toast(r.error); return; }
    cal = { configured: r.configured, connected: r.connected, account: r.account };
  }
  calendarOn = true;
  persist(); renderHeader();
  toast('Calendario conectado' + (cal.account ? ': ' + cal.account : ''));
  syncAll();
}
function toggleCalendar() {
  if (!cal.configured) { toast('Falta el ID de aplicación de Microsoft (ver windows/README.md)'); return; }
  if (calendarOn && cal.connected) { calendarOn = false; persist(); renderHeader(); }
  else enableCalendar();
}

// ───────── Acciones ─────────
function ensureSelection() {
  const ids = flatIDs();
  if (!selectedID || !ids.includes(selectedID)) selectedID = ids[0] ?? null;
}
function move(delta) {
  const ids = flatIDs();
  if (!ids.length) return;
  ensureSelection();
  const i = ids.indexOf(selectedID);
  selectedID = ids[Math.max(0, Math.min(ids.length - 1, i + delta))];
  paintSelection();
}
function submit() {
  const title = draft.title.trim();
  if (!title) return;
  const notes = draft.notes.trim();
  let id;
  const existing = draft.editingID && task(draft.editingID);
  if (existing) {
    Object.assign(existing, { title, notes, categoryID: draft.categoryID, start: draftStart(), end: draftEnd() });
    id = existing.id;
  } else {
    const t = { id: uid(), title, notes, categoryID: draft.categoryID, start: draftStart(), end: draftEnd(), done: false, doneAt: null, eventID: null, eventCal: null };
    tasks.push(t);
    id = t.id;
  }
  persist();
  sync(id);
  draft = newDraft(draft.categoryID);
  selectedID = id;
  renderAll();
}
function cancelDraft() { draft = newDraft(draft.categoryID); renderComposer(); }
function edit(id) {
  const t = task(id);
  if (!t) return;
  const s = new Date(t.start);
  draft = { title: t.title, notes: t.notes, day: ymd(s), time: hm(s), minutes: Math.max(5, Math.round((t.end - t.start) / 60000)), categoryID: t.categoryID, editingID: t.id };
  renderComposer();
  $('title').focus();
}
function requestToggle(id) {
  const t = task(id);
  if (!t) return;
  if (t.done) { reopen(id); return; }
  if (completingID) return;
  completingID = id;
  renderTasks();
  setTimeout(() => finishComplete(id), 500);
}
function finishComplete(id) {
  const ids = flatIDs();
  const idx = Math.max(0, ids.indexOf(id));
  const t = task(id);
  if (!t) { completingID = null; renderTasks(); return; }
  t.done = true; t.doneAt = Date.now();
  completingID = null;
  api.cal.remove(t.eventID);
  t.eventID = null; t.eventCal = null;
  persist();
  const rest = flatIDs();
  selectedID = rest.length ? rest[Math.min(idx, rest.length - 1)] : null;
  lastDoneID = id;
  clearTimeout(undoTimer);
  undoTimer = setTimeout(() => { lastDoneID = null; renderFooter(); }, 6000);
  renderTasks();
}
function reopen(id) {
  const t = task(id);
  if (!t) return;
  t.done = false; t.doneAt = null;
  if (lastDoneID === id) lastDoneID = null;
  persist(); sync(id);
  selectedID = id;
  renderTasks();
}
function remove(id) {
  const i = tasks.findIndex((t) => t.id === id);
  if (i < 0) return;
  const ids = flatIDs();
  const idx = Math.max(0, ids.indexOf(id));
  api.cal.remove(tasks[i].eventID);
  tasks.splice(i, 1);
  persist();
  const rest = flatIDs();
  selectedID = rest.length ? rest[Math.min(idx, rest.length - 1)] : null;
  renderTasks();
}
function postpone(id) {
  const t = task(id);
  if (!t) return;
  t.start = addDays(t.start, 1).getTime();
  t.end = addDays(t.end, 1).getTime();
  persist(); sync(id);
  renderTasks();
}

// ───────── Teclado ─────────
function onKey(e) {
  const composing = draftActive();
  const t = e.target;
  if (t.closest?.('#cats') || t.type === 'date' || t.type === 'time') return;
  if (e.type === 'keyup') {
    if (e.key === 'Tab' && peeking) { peeking = false; peekID = null; renderList(); e.preventDefault(); }
    return;
  }
  const ctrl = e.ctrlKey || e.metaKey;
  switch (e.key) {
    case 'Tab':
      if (composing || notesFocused) return;
      e.preventDefault();
      if (!peeking && !e.repeat) { ensureSelection(); peeking = true; peekID = selectedID; renderList(); }
      return;
    case 'ArrowUp': if (!notesFocused) { e.preventDefault(); move(-1); } return;
    case 'ArrowDown': if (!notesFocused) { e.preventDefault(); move(1); } return;
    case 'Enter':
      if (composing || notesFocused) return;
      e.preventDefault();
      if (selectedID && !e.repeat) requestToggle(selectedID);
      return;
    case 'Escape': if (composing) { e.preventDefault(); cancelDraft(); } return;
    case 'Backspace': if (ctrl && selectedID && !composing) { e.preventDefault(); remove(selectedID); } return;
    case 'ArrowRight': if (ctrl && selectedID && !composing) { e.preventDefault(); postpone(selectedID); } return;
    case 'e': case 'E': if (ctrl && selectedID) { e.preventDefault(); edit(selectedID); } return;
    case 'z': case 'Z': if (ctrl && !composing && lastDoneID) { e.preventDefault(); reopen(lastDoneID); } return;
  }
}
document.addEventListener('keydown', onKey);
document.addEventListener('keyup', onKey);

// ───────── Eventos ─────────
$('title').addEventListener('input', (e) => { draft.title = e.target.value; renderComposer(); });
$('title').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); submit(); } });
$('notes').addEventListener('input', (e) => { draft.notes = e.target.value; renderComposer(); });
$('notes').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); submit(); } });
$('notes').addEventListener('focus', () => { notesFocused = true; });
$('notes').addEventListener('blur', () => { notesFocused = false; });
$('submitBtn').onclick = submit;
$('day').addEventListener('change', (e) => { if (e.target.value) { draft.day = e.target.value; renderComposer(); } });
$('time').addEventListener('change', (e) => { if (e.target.value) { draft.time = e.target.value; renderComposer(); } });
$('chipToday').onclick = () => { draft.day = ymd(new Date()); renderComposer(); };
$('chipTomorrow').onclick = () => { draft.day = ymd(addDays(new Date(), 1)); renderComposer(); };
$('catRow').addEventListener('click', (e) => {
  const b = e.target.closest('[data-cat]');
  if (b) { draft.categoryID = b.dataset.cat; renderComposer(); }
});
$('btnCal').onclick = toggleCalendar;
$('btnDone').onclick = () => { showDone = !showDone; renderTasks(); };
$('undoBtn').onclick = () => lastDoneID && reopen(lastDoneID);

$('list').addEventListener('mouseover', (e) => {
  const row = e.target.closest('.row');
  if (row && row.dataset.id !== selectedID) { selectedID = row.dataset.id; document.querySelectorAll('.row').forEach((r) => r.classList.toggle('sel', r === row)); }
});
$('list').addEventListener('click', (e) => {
  const c = e.target.closest('[data-check]');
  if (c) requestToggle(c.dataset.check);
});

// Menú contextual
const menu = $('menu');
function closeMenu() { menu.hidden = true; }
$('list').addEventListener('contextmenu', (e) => {
  const row = e.target.closest('.row');
  if (!row) return;
  e.preventDefault();
  const id = row.dataset.id;
  selectedID = id; paintSelection();
  menu.innerHTML = '<button data-a="edit">Editar</button><button data-a="post">Posponer a mañana</button><hr><button data-a="del" class="danger">Eliminar</button>';
  menu.hidden = false;
  menu.style.left = Math.min(e.clientX, innerWidth - menu.offsetWidth - 6) + 'px';
  menu.style.top = Math.min(e.clientY, innerHeight - menu.offsetHeight - 6) + 'px';
  menu.onclick = (ev) => {
    const a = ev.target.dataset.a;
    closeMenu();
    if (a === 'edit') edit(id); else if (a === 'post') postpone(id); else if (a === 'del') remove(id);
  };
});
document.addEventListener('mousedown', (e) => {
  if (!menu.contains(e.target)) closeMenu();
  if (!$('cats').hidden && !$('cats').contains(e.target) && !$('btnCats').contains(e.target)) closeCats();
});
window.addEventListener('blur', closeMenu);

// Categorías
let paletteFor = null;
function renderCats() {
  $('cats').innerHTML = '<h4>Categorías</h4>' + categories.map((c) =>
    `<div><div class="crow" style="--c:#${c.colorHex}"><span class="dot" data-dot="${c.id}"></span><input data-name="${c.id}" value="${esc(c.name)}" placeholder="Nombre"><button class="del" data-del="${c.id}" title="Eliminar">🗑</button></div>` +
    (paletteFor === c.id ? `<div class="palette">${PALETTE.map((h) => `<i data-hex="${h}" data-for="${c.id}" class="${h === c.colorHex ? 'sel' : ''}" style="--c:#${h}"></i>`).join('')}</div>` : '') + '</div>').join('')
    + '<button class="addcat" data-add>+ Nueva categoría</button>';
}
function closeCats() { if ($('cats').hidden) return; $('cats').hidden = true; paletteFor = null; syncAll(); }
$('btnCats').onclick = () => { if ($('cats').hidden) { renderCats(); $('cats').hidden = false; } else closeCats(); };
$('cats').addEventListener('click', (e) => {
  const d = e.target.dataset;
  if (d.dot) { paletteFor = paletteFor === d.dot ? null : d.dot; renderCats(); }
  else if (d.hex) { category(d.for).colorHex = d.hex; paletteFor = null; persist(); renderCats(); renderAll(); }
  else if (d.del) {
    categories = categories.filter((c) => c.id !== d.del);
    tasks.forEach((t) => { if (t.categoryID === d.del) t.categoryID = null; });
    if (draft.categoryID === d.del) draft.categoryID = categories[0]?.id;
    persist(); renderCats(); renderAll();
  } else if ('add' in d) {
    const used = new Set(categories.map((c) => c.colorHex));
    categories.push({ id: uid(), name: 'Nueva', colorHex: PALETTE.find((h) => !used.has(h)) || PALETTE[0] });
    persist(); renderCats(); renderAll();
  }
});
$('cats').addEventListener('input', (e) => {
  const id = e.target.dataset.name;
  if (id) { category(id).name = e.target.value; persist(); renderComposer(); renderList(); }
});

// ───────── Arranque ─────────
function panelDidShow() {
  if (!draftActive()) draft = newDraft(draft.categoryID);
  ensureSelection();
  api.cal.status().then((s) => { cal = s; renderHeader(); });
  renderAll();
  $('title').focus();
}

(async function init() {
  const saved = await api.load();
  if (saved) {
    tasks = saved.tasks || [];
    if (saved.categories?.length) categories = saved.categories;
    calendarOn = !!saved.calendarOn;
  }
  draft = newDraft();
  cal = await api.cal.status();
  const ok = await api.hotkeyOK();
  $('hintKey').textContent = ok ? 'cerrar' : '⚠︎ ocupado';
  api.onShown(panelDidShow);
  api.onCalDisconnected(() => { cal.connected = false; cal.account = ''; calendarOn = false; persist(); renderHeader(); });
  panelDidShow();
  if (calendarOn && cal.connected) syncAll();
})();
