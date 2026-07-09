const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const { exec, spawn } = require('child_process');
const fs = require('fs');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 750,
    height: 650,
    minWidth: 480,
    minHeight: 400,
    title: 'Windows Maintenance Suite',
    autoHideMenuBar: true,
    show: false,
    backgroundColor: '#0f0f1a',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'index.html'));

  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    mainWindow.center();
  });

  mainWindow.on('closed', () => { mainWindow = null; });
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('activate', () => { if (mainWindow === null) createWindow(); });

function getProjectRoot() {
  if (app.isPackaged) {
    const resourcesApp = path.join(process.resourcesPath, 'app');
    if (fs.existsSync(resourcesApp)) return resourcesApp;
    return path.dirname(app.getPath('exe'));
  }
  return path.dirname(__dirname);
}

function getGuiRunPath() {
  const root = getProjectRoot();
  const candidates = [
    path.join(root, 'WindowGUI', 'gui-run.ps1'),
    path.join(root, 'gui-run.ps1'),
  ];
  for (const c of candidates) { if (fs.existsSync(c)) return c; }
  return path.join(__dirname, 'gui-run.ps1');
}

ipcMain.handle('run-option', async (event, optionNumber) => {
  const scriptPath = getGuiRunPath();
  const psCmd = `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${scriptPath}" -Option ${optionNumber}`;
  const interactive = [2, 3, 4, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20].includes(optionNumber);

  return new Promise((resolve) => {
    if (interactive) {
      const child = spawn('powershell.exe', [
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', scriptPath, '-Option', String(optionNumber)
      ], { cwd: getProjectRoot(), windowsHide: false, stdio: 'inherit' });
      child.on('close', (code) => resolve({ code, output: '' }));
      child.on('error', (err) => resolve({ code: -1, output: 'Erro: ' + err.message }));
    } else {
      exec(psCmd, { cwd: getProjectRoot(), windowsHide: true, timeout: 300000, maxBuffer: 1024 * 1024 },
        (error, stdout, stderr) => {
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
    '-File', scriptPath, '-Option', String(optionNumber)
  ], { cwd: getProjectRoot(), windowsHide: false, stdio: 'inherit' });
  return new Promise((resolve) => {
    child.on('close', (code) => resolve(code));
    child.on('error', () => resolve(-1));
  });
});
