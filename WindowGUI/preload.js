const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  runOption: (optionNumber) => ipcRenderer.invoke('run-option', optionNumber),
  openInteractive: (optionNumber) => ipcRenderer.invoke('open-interactive', optionNumber),
  quit: () => ipcRenderer.send('quit-app'),
});
