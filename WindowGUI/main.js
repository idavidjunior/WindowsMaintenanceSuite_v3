const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const { exec, spawn } = require('child_process');
const fs = require('fs');

let mainWindow;

function isAdmin() {
  try {
    const { execSync } = require('child_process');
    execSync('net session', { stdio: 'ignore', timeout: 2000 });
    return true;
  } catch { return false; }
}

// Auto-elevate to admin (packaged mode only — .bat already handles elevation)
if (app.isPackaged && !isAdmin()) {
  const exePath = app.getPath('exe');
  try {
    require('child_process').execSync(
      `powershell -NoProfile -Command "Start-Process '${exePath}' -Verb RunAs -WindowStyle Hidden"`,
      { timeout: 5000 }
    );
  } catch (e) {}
  app.quit();
  return;
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 780,
    height: 720,
    minWidth: 480,
    minHeight: 540,
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
    mainWindow.maximize();
    mainWindow.show();
  });

  mainWindow.on('closed', () => { mainWindow = null; });
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('activate', () => { if (mainWindow === null) createWindow(); });

function getProjectRoot() {
  if (app.isPackaged) {
    const resourcesApp = path.join(process.resourcesPath, 'app');
    if (fs.existsSync(path.join(resourcesApp, 'Core'))) return resourcesApp;
    const exeDir = path.dirname(app.getPath('exe'));
    if (fs.existsSync(path.join(exeDir, 'Core'))) return exeDir;
    if (fs.existsSync(path.join(exeDir, '..', 'Core'))) return path.resolve(exeDir, '..');
    return resourcesApp;
  }
  return path.dirname(__dirname);
}

function getGuiRunPath() {
  if (app.isPackaged) {
    const inApp = path.join(process.resourcesPath, 'app', 'gui-run.ps1');
    if (fs.existsSync(inApp)) return inApp;
    const inCore = path.join(getProjectRoot(), 'WindowGUI', 'gui-run.ps1');
    if (fs.existsSync(inCore)) return inCore;
    return path.join(getProjectRoot(), 'gui-run.ps1');
  }
  return path.join(__dirname, 'gui-run.ps1');
}

function runInteractive(scriptPath, optionNumber, projectRoot) {
  return new Promise((resolve) => {
    const child = spawn('cmd.exe', [
      '/c', 'start', '/wait', '',
      'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
      '-File', scriptPath, '-Option', String(optionNumber), '-KeepOpen'
    ], { cwd: projectRoot, windowsHide: false, stdio: 'ignore' });
    child.on('close', (code) => resolve(code));
    child.on('error', () => resolve(-1));
  });
}

ipcMain.handle('check-admin', () => isAdmin());

ipcMain.handle('run-option', async (event, optionNumber) => {
  const scriptPath = getGuiRunPath();
  if (!fs.existsSync(scriptPath)) {
    return { code: -1, output: 'Script não encontrado: ' + scriptPath };
  }
  const projectRoot = getProjectRoot();
  if (!fs.existsSync(path.join(projectRoot, 'Core'))) {
    return { code: -1, output: 'Pasta Core não encontrada em: ' + projectRoot };
  }
  const psCmd = `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${scriptPath}" -Option ${optionNumber}`;
  const interactive = [2, 3, 4, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20, 21].includes(optionNumber);

  return new Promise((resolve) => {
    if (interactive) {
      runInteractive(scriptPath, optionNumber, projectRoot)
        .then((code) => resolve({ code, output: '' }));
    } else {
      exec(psCmd, { cwd: projectRoot, windowsHide: true, timeout: 300000, maxBuffer: 1024 * 1024 },
        (error, stdout, stderr) => {
          const output = (stdout || '') + (stderr || '');
          const code = error ? (error.code || error.status || 1) : 0;
          resolve({ code, output: output.slice(0, 2000) });
        });
    }
  });
});

ipcMain.handle('get-health-data', async () => {
  const scriptPath = path.join(__dirname, 'get-health.ps1');
  if (!fs.existsSync(scriptPath)) return null;
  return new Promise((resolve) => {
    exec(`powershell -NoProfile -ExecutionPolicy Bypass -File "${scriptPath}"`, { timeout: 10000, windowsHide: true },
      (err, stdout) => {
        if (err) { resolve(null); return; }
        try { resolve(JSON.parse(stdout.trim())); } catch { resolve(null); }
      });
  });
});

ipcMain.on('quit-app', () => { app.quit(); });

ipcMain.handle('open-interactive', async (event, optionNumber) => {
  const scriptPath = getGuiRunPath();
  if (!fs.existsSync(scriptPath)) {
    return -1;
  }
  return runInteractive(scriptPath, optionNumber, getProjectRoot());
});
