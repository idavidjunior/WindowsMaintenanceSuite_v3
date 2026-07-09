try {
  const { contextBridge, ipcRenderer } = require('electron');
  contextBridge.exposeInMainWorld('api', {
    runOption: (n) => ipcRenderer.invoke('run-option', n),
    openInteractive: (n) => ipcRenderer.invoke('open-interactive', n),
    quit: () => ipcRenderer.send('quit-app'),
  });
} catch (e) {
  console.error('[WMS] preload error:', e);
}
