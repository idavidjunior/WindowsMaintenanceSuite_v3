const statusText = document.getElementById('statusText');
const statusIndicator = document.getElementById('statusIndicator');
const btnExit = document.getElementById('btnExit');
const apiError = document.getElementById('apiError');
const adminBanner = document.getElementById('adminBanner');

const interactiveOptions = [2, 3, 4, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20, 21];

const optionNames = {
  1:'Manutenção Essencial',2:'Manutenção Completa',3:'Limpeza Profunda',
  4:'Sistema Leve',5:'Diagnóstico Aprofundado',6:'Diagnóstico Inteligente (SMART)',
  7:'Monitor de Desempenho',8:'Gerenciador de Drivers',9:'Ajustes de Sistema (Tweaks)',
  10:'Backup do Registro',11:'Restaurar Registro',12:'Manutenção Agendada',
  13:'Verificação de Vírus',14:'Varredura e Limpeza do Registro',
  15:'Ferramentas Nativas do Windows',16:'Analisador de Espaço em Disco',
  17:'Auto-Atualização',18:'Gerenciador de Pacotes',19:'Perfis de Otimização',
  20:'Hardening de Segurança',21:'Gerenciador de Memória RAM',
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
(function() {
  try {
    var tip = document.getElementById('tooltip');
    if (!tip) return;
    document.querySelectorAll('[data-tip]').forEach(function(el) {
      el.addEventListener('mouseenter', function() {
        var txt = el.getAttribute('data-tip');
        if (!txt) return;
        tip.textContent = txt;
        var r = el.getBoundingClientRect();
        var tw = tip.offsetWidth;
        var th = tip.offsetHeight;
        var l = r.left + r.width / 2 - tw / 2;
        if (l < 4) l = 4;
        if (l + tw > window.innerWidth - 4) l = window.innerWidth - tw - 4;
        var t = r.top - th - 8;
        if (t < 4) t = r.bottom + 8;
        tip.style.left = l + 'px';
        tip.style.top = t + 'px';
        tip.classList.remove('hidden');
      });
      el.addEventListener('mouseleave', function() {
        tip.classList.add('hidden');
      });
    });
  } catch(e) { console.error('Tooltip:', e); }
})();

/* Health Monitor */
(function() {
  var cpuEl = document.getElementById('hmCpu');
  var cpuVal = document.getElementById('hmCpuVal');
  var ramEl = document.getElementById('hmRam');
  var ramVal = document.getElementById('hmRamVal');
  var diskEl = document.getElementById('hmDisk');
  var diskVal = document.getElementById('hmDiskVal');
  var uptimeEl = document.getElementById('hmUptime');
  var scoreEl = document.getElementById('hmScore');
  var fills = {};

  function color(pct) {
    if (pct < 50) return '#6bcb77';
    if (pct < 75) return '#ffd93d';
    if (pct < 90) return '#ff9f43';
    return '#ff6b6b';
  }

  function update(data) {
    [cpuEl, cpuVal, 'cpu'].forEach(function(v,i,a) {
      if (i===0) { a[0].style.width = data.cpu + '%'; a[0].style.background = color(data.cpu); }
      if (i===1) a[1].textContent = data.cpu + '%';
    });
    ramEl.style.width = data.ramPct + '%'; ramEl.style.background = color(data.ramPct);
    ramVal.textContent = data.ramPct + '%';
    diskEl.style.width = data.diskPct + '%'; diskEl.style.background = color(data.diskPct);
    diskVal.textContent = data.diskPct + '%';
    uptimeEl.textContent = data.uptimeHours + 'h';
    scoreEl.textContent = data.score;
    scoreEl.style.color = data.score >= 80 ? '#6bcb77' : data.score >= 50 ? '#ffd93d' : '#ff6b6b';
  }

  function fallback() {
    cpuEl.style.width = '0%'; cpuEl.style.background = '#4a5568';
    cpuVal.textContent = '--%';
    ramEl.style.width = '0%'; ramEl.style.background = '#4a5568';
    ramVal.textContent = '--%';
    diskEl.style.width = '0%'; diskEl.style.background = '#4a5568';
    diskVal.textContent = '--%';
    uptimeEl.textContent = '--h';
    scoreEl.textContent = '--';
    scoreEl.style.color = '#4a5568';
  }

  function poll() {
    if (window.api && window.api.getHealthData) {
      window.api.getHealthData().then(function(d) { if (d) update(d); else fallback(); }).catch(fallback);
    } else {
      try {
        fetch('/api/health').then(function(r) { return r.json(); }).then(function(d) { if (d) update(d); else fallback(); }).catch(fallback);
      } catch(e) { fallback(); }
    }
  }

  poll();
  setInterval(poll, 5000);
})();
