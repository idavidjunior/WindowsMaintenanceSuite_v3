const statusText = document.getElementById('statusText');
const statusIndicator = document.getElementById('statusIndicator');
const btnExit = document.getElementById('btnExit');
const apiError = document.getElementById('apiError');

const interactiveOptions = [2, 3, 4, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20];

const optionNames = {
  1:'Manuteno Essencial',2:'Manuteno Completa',3:'Limpeza Profunda',
  4:'Sistema Leve',5:'Diagnstico Aprofundado',6:'Diagnstico Inteligente (SMART)',
  7:'Monitor de Desempenho',8:'Gerenciador de Drivers',9:'Ajustes de Sistema (Tweaks)',
  10:'Backup do Registro',11:'Restaurar Registro',12:'Manuteno Agendada',
  13:'Verificao de Vrus',14:'Varredura e Limpeza do Registro',
  15:'Ferramentas Nativas do Windows',16:'Analisador de Espao em Disco',
  17:'Auto-Atualizao',18:'Gerenciador de Pacotes',19:'Perfis de Otimizao',
  20:'Hardening de Segurana',
};

function setStatus(state, text) {
  statusIndicator.className = 'status-indicator ' + state;
  statusText.textContent = text;
}

function checkApi() {
  const ok = typeof window.api !== 'undefined' && window.api.runOption;
  if (!ok) {
    apiError.classList.remove('hidden');
    apiError.textContent = 'API desconectada. Os botes no funcionaro. Execute via "npm start" ou reconstrua o .exe.';
    setStatus('error', 'API no disponvel. Recompile o app com "npx electron-builder --win dir".');
  }
  return ok;
}

async function runOption(opt) {
  if (!checkApi()) {
    alert('[WMS] API no conectada. O Electron no exps o window.api corretamente.\nExecute via "npm start" ou use o win-unpacked compilado.');
    return;
  }
  const name = optionNames[opt] || 'Opo ' + opt;
  setStatus('running', 'Executando: ' + name + '...');

  try {
    if (interactiveOptions.includes(opt)) {
      setStatus('running', name + ' ser executado em uma janela separada. Aguarde...');
      const code = await window.api.openInteractive(opt);
      setStatus(code === 0 ? 'success' : 'error',
        code === 0 ? name + ' concluda!' : name + ' finalizada (cdigo ' + code + ').');
    } else {
      const r = await window.api.runOption(opt);
      setStatus(r.code === 0 ? 'success' : 'error',
        r.code === 0 ? (r.output || name + ' concluda com sucesso!') : (r.output || name + ' erro (' + r.code + ')'));
    }
  } catch (err) {
    setStatus('error', 'Erro: ' + (err.message || err));
  }
}

document.querySelectorAll('.btn[data-opt]').forEach(function(b) {
  b.addEventListener('click', function() { runOption(parseInt(b.dataset.opt, 10)); });
});

btnExit.addEventListener('click', function() {
  if (window.api && window.api.quit) window.api.quit();
  else window.close();
});

setTimeout(checkApi, 500);
setStatus('idle', 'Pronto. Selecione uma opo acima.');
