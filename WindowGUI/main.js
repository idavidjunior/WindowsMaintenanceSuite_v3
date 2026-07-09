const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const { exec, spawn } = require('child_process');
const fs = require('fs');

let mainWindow;

function getPreloadPath() {
  if (app.isPackaged) {
    const asarPath = path.join(process.resourcesPath, 'app.asar');
    if (fs.existsSync(asarPath)) {
      return path.join(asarPath, 'preload.js');
    }
    return path.join(process.resourcesPath, 'app', 'preload.js');
  }
  return path.join(__dirname, 'preload.js');
}

function getAppRoot() {
  if (app.isPackaged) {
    return path.dirname(app.getPath('exe'));
  }
  return path.dirname(__dirname);
}

function getGuiRunPath() {
  if (app.isPackaged) {
    const candidates = [
      path.join(process.resourcesPath, 'app', 'WindowGUI', 'gui-run.ps1'),
      path.join(process.resourcesPath, 'app', 'gui-run.ps1'),
      path.join(path.dirname(app.getPath('exe')), 'WindowGUI', 'gui-run.ps1'),
    ];
    for (const c of candidates) {
      if (fs.existsSync(c)) return c;
    }
  }
  return path.join(__dirname, 'gui-run.ps1');
}

function getIndexPath() {
  if (app.isPackaged) {
    const asarPath = path.join(process.resourcesPath, 'app.asar');
    if (fs.existsSync(asarPath)) {
      return path.join(asarPath, 'index.html');
    }
    return path.join(process.resourcesPath, 'app', 'index.html');
  }
  return path.join(__dirname, 'index.html');
}

function getCwd() {
  if (app.isPackaged) {
    return path.dirname(app.getPath('exe'));
  }
  return path.dirname(__dirname);
}

function createWindow() {
  const preloadPath = getPreloadPath();
  mainWindow = new BrowserWindow({
    width: 750,
    height: 650,
    minWidth: 600,
    minHeight: 500,
    title: 'Windows Maintenance Suite',
    autoHideMenuBar: true,
    show: false,
    backgroundColor: '#0f0f1a',
    webPreferences: {
      preload: preloadPath,
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  mainWindow.loadFile(getIndexPath());

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    mainWindow.center();
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (mainWindow === null) createWindow();
});

ipcMain.handle('run-option', async (event, optionNumber) => {
  const scriptPath = getGuiRunPath();
  const psCmd = `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${scriptPath}" -Option ${optionNumber}`;
  const interactive = [3, 4, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20].includes(optionNumber);

  return new Promise((resolve) => {
    if (interactive) {
      const child = spawn('powershell.exe', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', scriptPath,
        '-Option', String(optionNumber)
      ], {
        cwd: getCwd(),
        windowsHide: false,
        stdio: 'inherit',
      });
      child.on('close', (code) => resolve({ code, output: '' }));
      child.on('error', (err) => resolve({ code: -1, output: `Erro: ${err.message}` }));
    } else {
      exec(psCmd, {
        cwd: getCwd(),
        windowsHide: true,
        timeout: 300000,
        maxBuffer: 1024 * 1024,
      }, (error, stdout, stderr) => {
        const output = (stdout || '') + (stderr || '');
        const code = error ? (error.code || error.status || 1) : 0;
        resolve({ code, output: output.slice(0, 2000) });
      });
    }
  });
});

ipcMain.on('quit-app', () => { app.quit(); });

ipcMain.handle('open-interactive', async (event, optionNumber) => {
  const scriptPath = getGuiRunPath();
  const child = spawn('powershell.exe', [
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', scriptPath,
    '-Option', String(optionNumber)
  ], {
    cwd: getCwd(),
    windowsHide: false,
    stdio: 'inherit',
  });
  return new Promise((resolve) => {
    child.on('close', (code) => resolve(code));
    child.on('error', () => resolve(-1));
  });
});
