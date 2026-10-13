// Sincroniza con el Calendario de Outlook.com / Microsoft 365 mediante Microsoft Graph.
// La app "Calendario" de Windows muestra esos mismos calendarios, y también el móvil.
// Cada categoría vive como un calendario propio ("TaskOut · Hogar") con su color.
const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { app, shell, safeStorage } = require('electron');
const config = require('./config.json');

const AUTH = 'https://login.microsoftonline.com/common/oauth2/v2.0';
const GRAPH = 'https://graph.microsoft.com/v1.0';
const SCOPES = 'offline_access User.Read Calendars.ReadWrite';

// Graph solo acepta colores con nombre para los calendarios: se usa el más parecido.
const GRAPH_COLORS = {
  lightRed: [229, 103, 92], lightOrange: [240, 160, 75], lightYellow: [232, 197, 71],
  lightGreen: [109, 190, 140], lightTeal: [79, 179, 191], lightBlue: [91, 141, 239],
  lightPink: [227, 127, 181], lightBrown: [150, 110, 80], lightGray: [142, 142, 147],
};
function nearestColor(hex) {
  const v = parseInt(hex.replace('#', ''), 16);
  const c = [(v >> 16) & 255, (v >> 8) & 255, v & 255];
  let best = 'lightGray', bd = Infinity;
  for (const [name, r] of Object.entries(GRAPH_COLORS)) {
    const d = (r[0] - c[0]) ** 2 + (r[1] - c[1]) ** 2 + (r[2] - c[2]) ** 2;
    if (d < bd) { bd = d; best = name; }
  }
  return best;
}

const authFile = () => path.join(app.getPath('userData'), 'auth.bin');
let auth = null;          // { refresh, access, expires, account }
let calCache = null;      // nombre -> { id, color }
let chain = Promise.resolve();

// Las llamadas a Graph van en fila para no crear dos veces el mismo calendario.
function serial(fn) {
  const r = chain.then(fn);
  chain = r.catch(() => {});
  return r;
}

function loadAuth() {
  if (auth) return auth;
  try {
    const buf = fs.readFileSync(authFile());
    auth = JSON.parse(safeStorage.isEncryptionAvailable() ? safeStorage.decryptString(buf) : buf.toString());
  } catch { auth = null; }
  return auth;
}
function saveAuth() {
  try {
    const s = JSON.stringify(auth);
    fs.writeFileSync(authFile(), safeStorage.isEncryptionAvailable() ? safeStorage.encryptString(s) : s);
  } catch {}
}

const configured = () => !!config.microsoftClientId;
const status = () => ({ configured: configured(), connected: !!loadAuth()?.refresh, account: loadAuth()?.account || '' });

async function tokenRequest(params) {
  const res = await fetch(`${AUTH}/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: config.microsoftClientId, scope: SCOPES, ...params }),
  });
  const j = await res.json();
  if (!res.ok) throw Object.assign(new Error(j.error_description || j.error || 'Error de autenticación'), { code: j.error });
  auth = {
    refresh: j.refresh_token || auth?.refresh,
    access: j.access_token,
    expires: Date.now() + (j.expires_in - 60) * 1000,
    account: auth?.account || '',
  };
  return auth;
}

async function accessToken() {
  const a = loadAuth();
  if (!a?.refresh) throw new Error('Calendario no conectado');
  if (a.access && a.expires > Date.now()) return a.access;
  try {
    await tokenRequest({ grant_type: 'refresh_token', refresh_token: a.refresh });
  } catch (e) {
    if (e.code === 'invalid_grant') { auth = null; try { fs.unlinkSync(authFile()); } catch {} }
    throw e;
  }
  saveAuth();
  return auth.access;
}

// Inicio de sesión en el navegador (flujo con código + PKCE y redirección a localhost).
function connect() {
  if (!configured()) return Promise.reject(new Error('Falta el ID de aplicación de Microsoft (ver windows/README.md)'));
  return new Promise((resolve, reject) => {
    const verifier = crypto.randomBytes(48).toString('base64url');
    const challenge = crypto.createHash('sha256').update(verifier).digest('base64url');
    const state = crypto.randomBytes(16).toString('hex');
    let done = false;
    const finish = (err) => { if (done) return; done = true; clearTimeout(timer); server.close(); err ? reject(err) : resolve(status()); };

    const server = http.createServer(async (req, res) => {
      const url = new URL(req.url, 'http://localhost');
      if (url.pathname !== '/') { res.writeHead(404).end(); return; }
      const page = (msg) => res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
        .end(`<body style="font-family:Segoe UI,sans-serif;text-align:center;padding-top:20vh"><h2>${msg}</h2><p>Ya puedes cerrar esta pestaña y volver a TaskOut.</p></body>`);
      if (url.searchParams.get('state') !== state || !url.searchParams.get('code')) {
        page('No se pudo conectar');
        finish(new Error(url.searchParams.get('error_description') || 'Conexión cancelada'));
        return;
      }
      try {
        auth = null;
        await tokenRequest({
          grant_type: 'authorization_code', code: url.searchParams.get('code'),
          redirect_uri: redirect, code_verifier: verifier,
        });
        const me = await (await fetch(`${GRAPH}/me?$select=mail,userPrincipalName`, { headers: { Authorization: `Bearer ${auth.access}` } })).json();
        auth.account = me.mail || me.userPrincipalName || '';
        saveAuth();
        calCache = null;
        page('Calendario conectado ✓');
        finish();
      } catch (e) { page('No se pudo conectar'); finish(e); }
    });
    let redirect = '';
    const timer = setTimeout(() => finish(new Error('Se agotó el tiempo para iniciar sesión')), 180000);
    server.on('error', finish);
    server.listen(0, '127.0.0.1', () => {
      redirect = `http://localhost:${server.address().port}`;
      shell.openExternal(`${AUTH}/authorize?` + new URLSearchParams({
        client_id: config.microsoftClientId, response_type: 'code', redirect_uri: redirect,
        scope: SCOPES, state, code_challenge: challenge, code_challenge_method: 'S256', prompt: 'select_account',
      }));
    });
  });
}

function disconnect() {
  auth = null; calCache = null;
  try { fs.unlinkSync(authFile()); } catch {}
  return status();
}

async function graph(method, p, body, retried = false) {
  const res = await fetch(GRAPH + p, {
    method,
    headers: { Authorization: `Bearer ${await accessToken()}`, ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 401 && !retried) { auth.expires = 0; return graph(method, p, body, true); }
  if (res.status === 204) return null;
  const j = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(j.error?.message || `Graph ${res.status}`), { status: res.status });
  return j;
}

async function calendarFor(category) {
  const name = 'TaskOut · ' + (category?.name || 'Sin categoría');
  const color = nearestColor(category?.colorHex || '8E8E93');
  if (!calCache) {
    calCache = {};
    const list = await graph('GET', '/me/calendars?$top=100&$select=id,name,color');
    for (const c of list.value) calCache[c.name] = { id: c.id, color: c.color };
  }
  const hit = calCache[name];
  if (hit) {
    if (hit.color !== color) { await graph('PATCH', `/me/calendars/${hit.id}`, { color }); hit.color = color; }
    return hit.id;
  }
  const c = await graph('POST', '/me/calendars', { name, color });
  calCache[name] = { id: c.id, color };
  return c.id;
}

const utc = (ms) => ({ dateTime: new Date(ms).toISOString().slice(0, 23), timeZone: 'UTC' });

// Crea o actualiza el evento de la tarea. Devuelve { eventID, eventCal }.
function upsert(task, category) {
  return serial(async () => {
    const calID = await calendarFor(category);
    const body = {
      subject: task.title,
      body: { contentType: 'text', content: task.notes || '' },
      start: utc(task.start),
      end: utc(Math.max(task.end, task.start + 300000)),
      isReminderOn: false,
    };
    if (task.eventID && task.eventCal === calID) {
      try {
        await graph('PATCH', `/me/events/${task.eventID}`, body);
        return { eventID: task.eventID, eventCal: calID };
      } catch (e) { if (e.status !== 404) throw e; }
    } else if (task.eventID) {
      await graph('DELETE', `/me/events/${task.eventID}`).catch(() => {});
    }
    const ev = await graph('POST', `/me/calendars/${calID}/events`, body);
    return { eventID: ev.id, eventCal: calID };
  });
}

function remove(eventID) {
  if (!eventID) return Promise.resolve();
  return serial(() => graph('DELETE', `/me/events/${eventID}`).catch(() => {}));
}

module.exports = { status, connect, disconnect, upsert, remove };
