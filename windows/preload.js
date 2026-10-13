const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('taskout', {
  load: () => ipcRenderer.invoke('data:load'),
  save: (data) => ipcRenderer.send('data:save', data),
  cal: {
    status: () => ipcRenderer.invoke('cal:status'),
    connect: () => ipcRenderer.invoke('cal:connect'),
    upsert: (task, category) => ipcRenderer.invoke('cal:upsert', task, category),
    remove: (eventID) => ipcRenderer.invoke('cal:remove', eventID),
  },
  hotkeyOK: () => ipcRenderer.invoke('hotkey:ok'),
  onShown: (cb) => ipcRenderer.on('shown', cb),
  onCalDisconnected: (cb) => ipcRenderer.on('cal:disconnected', cb),
  acrylic: () => ipcRenderer.sendSync('ui:acrylic'),
});
