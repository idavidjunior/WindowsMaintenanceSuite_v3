const statusText = document.getElementById('statusText');
const statusIndicator = document.getElementById('statusIndicator');
const btnExit = document.getElementById('btnExit');
const apiError = document.getElementById('apiError');
const adminBanner = document.getElementById('adminBanner');

const interactiveOptions = [2, 3, 4, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20];

const optionNames = {
  1:'Manutenção Essencial',2:'Manutenção Completa',3:'Limpeza Profunda',
  4:'Sistema Leve',5:'Diagnóstico Aprofundado',6:'Diagnóstico Inteligente (SMART)',
  7:'Monitor de Desempenho',8:'Gerenciador de Drivers',9:'Ajustes de Sistema (Tweaks)',
  10:'Backup do Registro',11:'Restaurar Registro',12:'Manutenção Agendada',
  13:'Verificação de Vírus',14:'Varredura e Limpeza do Registro',
  15:'Ferramentas Nativas do Windows',16:'Analisador de Espaço em Disco',
  17:'Auto-Atualização',18:'Gerenciador de Pacotes',19:'Perfis de Otimização',
  20:'Hardening de Segurança',
};

function setStatus(state, text) {
  statusIndicator.className = 'status-indicator ' + state;
  statusText.textContent = text;
}

async function checkAdmin() {
  try {
    if (window.api && window.api.checkAdmin) {
      const admin = await window.api.checkAdmin();
      if (!admin) {
        adminBanner.classList.remove('hidden');
        setStatus('error', 'Execute como Administrador.');
      }
    }
  } catch (e) {}
}

function checkApi() {
  const ok = typeof window.api !== 'undefined' && window.api.runOption;
  if (!ok) {
    apiError.classList.remove('hidden');
    apiError.textContent = 'API desconectada. Os botões não funcionarão. Execute via "npm start" ou reconstrua o .exe.';
    setStatus('error', 'API não disponível. Recompile o app com "npx electron-builder --win dir".');
  }
  return ok;
}

async function runOption(opt) {
  if (!checkApi()) {
    alert('[WMS] API não conectada. O Electron não expõe o window.api corretamente.\nExecute via "npm start" ou use o win-unpacked compilado.');
    return;
  }
  const name = optionNames[opt] || 'Opção ' + opt;
  setStatus('running', 'Executando: ' + name + '...');

  try {
    if (interactiveOptions.includes(opt)) {
      setStatus('running', name + ' será executado em uma janela separada. Aguarde...');
      const code = await window.api.openInteractive(opt);
      setStatus(code === 0 ? 'success' : 'error',
        code === 0 ? name + ' concluída!' : name + ' finalizada (código ' + code + ').');
    } else {
      const r = await window.api.runOption(opt);
      setStatus(r.code === 0 ? 'success' : 'error',
        r.code === 0 ? (r.output || name + ' concluída com sucesso!') : (r.output || name + ' erro (' + r.code + ')'));
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
setTimeout(checkAdmin, 800);
setStatus('idle', 'Pronto. Selecione uma opção acima.');

/* Tooltip customizado */
const tooltip = document.getElementById('tooltip');
let tooltipTimeout;

document.addEventListener('mouseover', function(e) {
  var btn = e.target.closest('[data-tip]');
  if (!btn) { tooltip.classList.add('hidden'); return; }
  clearTimeout(tooltipTimeout);
  tooltipTimeout = setTimeout(function() {
    tooltip.textContent = btn.getAttribute('data-tip');
    var rect = btn.getBoundingClientRect();
    var top = rect.top - tooltip.offsetHeight - 8;
    tooltip.style.left = Math.max(4, Math.min(rect.left + rect.width / 2 - tooltip.offsetWidth / 2, window.innerWidth - tooltip.offsetWidth - 4)) + 'px';
    tooltip.style.top = (top < 4 ? rect.bottom + 8 : top) + 'px';
    tooltip.classList.remove('hidden');
  }, 300);
});

document.addEventListener('mouseout', function(e) {
  if (e.target.closest('[data-tip]')) {
    clearTimeout(tooltipTimeout);
    tooltip.classList.add('hidden');
  }
});
