const { app, BrowserWindow, Tray, Menu, globalShortcut, ipcMain, screen, nativeImage, dialog } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const { autoUpdater } = require('electron-updater');
const calendar = require('./calendar');

if (!app.requestSingleInstanceLock()) { app.quit(); return; }

const WIDTH = 380;
const SHORTCUT = 'Alt+T';
const dataFile = () => path.join(app.getPath('userData'), 'data.json');
// Acrílico (translucidez) solo en Windows 11 22H2 o superior.
const acrylic = process.platform === 'win32' && parseInt(os.release().split('.')[2], 10) >= 22621;

let win, tray, hotkeyOK = true, positioned = false;

function createWindow() {
  win = new BrowserWindow({
    width: WIDTH, height: 700,
    frame: false, show: false, resizable: false, maximizable: false, minimizable: false, fullscreenable: false,
    skipTaskbar: true, alwaysOnTop: true, hasShadow: true,
    ...(acrylic ? { backgroundMaterial: 'acrylic' } : { backgroundColor: '#202124' }),
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: false },
  });
  win.setAlwaysOnTop(true, 'floating');
  win.setVisibleOnAllWorkspaces(true);
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.on('close', (e) => { if (!app.isQuitting) { e.preventDefault(); hide(); } });
}

function position() {
  const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea;
  const h = Math.min(780, area.height - 32);
  win.setBounds({ x: area.x + area.width - WIDTH - 14, y: Math.round(area.y + (area.height - h) / 2), width: WIDTH, height: h });
}

function show() {
  position();
  win.show();
  win.focus();
  win.webContents.send('shown');
}
function hide() { win.hide(); }
function toggle() { win.isVisible() && win.isFocused() ? hide() : show(); }

function buildTray() {
  const icon = nativeImage.createFromPath(path.join(__dirname, 'assets', 'icon.png')).resize({ width: 16, height: 16 });
  tray = new Tray(icon);
  tray.setToolTip('TaskOut');
  tray.on('click', toggle);
  const login = () => app.getLoginItemSettings().openAtLogin;
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: hotkeyOK ? `Mostrar / ocultar  (${SHORTCUT})` : `Mostrar / ocultar  (${SHORTCUT} está ocupado por otra app)`, click: toggle },
    { label: 'Abrir al iniciar sesión', type: 'checkbox', checked: login(), click: (i) => app.setLoginItemSettings({ openAtLogin: i.checked }) },
    { label: 'Desconectar calendario', click: () => { calendar.disconnect(); win.webContents.send('cal:disconnected'); } },
    { label: 'Buscar actualizaciones…', click: () => checkUpdates(true) },
    { type: 'separator' },
    { label: 'Salir de TaskOut', click: () => { app.isQuitting = true; app.quit(); } },
  ]));
}

function checkUpdates(manual) {
  if (!app.isPackaged) { if (manual) dialog.showMessageBox({ message: 'Las actualizaciones solo funcionan en la app instalada.' }); return; }
  autoUpdater.checkForUpdates().then((r) => {
    if (manual && !r?.isUpdateAvailable) dialog.showMessageBox({ message: 'TaskOut está al día.' });
  }).catch(() => { if (manual) dialog.showMessageBox({ message: 'No se pudo buscar actualizaciones.' }); });
}

function setupUpdates() {
  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.on('update-downloaded', async () => {
    const r = await dialog.showMessageBox({ message: 'Hay una versión nueva de TaskOut lista.', buttons: ['Reiniciar ahora', 'Más tarde'], defaultId: 0 });
    if (r.response === 0) { app.isQuitting = true; autoUpdater.quitAndInstall(); }
  });
  if (app.isPackaged) { checkUpdates(false); setInterval(() => checkUpdates(false), 6 * 3600 * 1000); }
}

ipcMain.handle('data:load', () => {
  try { return JSON.parse(fs.readFileSync(dataFile(), 'utf8')); } catch { return null; }
});
ipcMain.on('data:save', (_e, data) => {
  const tmp = dataFile() + '.tmp';
  try { fs.writeFileSync(tmp, JSON.stringify(data)); fs.renameSync(tmp, dataFile()); } catch {}
});
ipcMain.handle('hotkey:ok', () => hotkeyOK);
ipcMain.on('ui:acrylic', (e) => { e.returnValue = acrylic; });
ipcMain.handle('cal:status', () => calendar.status());
ipcMain.handle('cal:connect', async () => {
  try { return { ok: true, ...(await calendar.connect()) }; } catch (e) { return { ok: false, error: e.message }; }
});
ipcMain.handle('cal:upsert', async (_e, task, category) => {
  try { return { ok: true, ...(await calendar.upsert(task, category)) }; } catch (e) { return { ok: false, error: e.message }; }
});
ipcMain.handle('cal:remove', async (_e, id) => { await calendar.remove(id); return true; });

app.on('second-instance', show);
app.whenReady().then(() => {
  createWindow();
  hotkeyOK = globalShortcut.register(SHORTCUT, toggle);
  buildTray();
  setupUpdates();
  win.webContents.once('did-finish-load', show);
});
app.on('window-all-closed', (e) => e.preventDefault());
app.on('will-quit', () => globalShortcut.unregisterAll());
