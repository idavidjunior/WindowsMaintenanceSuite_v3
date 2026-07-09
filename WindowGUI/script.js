const statusText = document.getElementById('statusText');
const statusIndicator = document.getElementById('statusIndicator');
const btnExit = document.getElementById('btnExit');

const interactiveOptions = [3, 4, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 20];

const optionNames = {
  1: 'Manutenção Essencial',
  2: 'Manutenção Completa',
  3: 'Limpeza Profunda',
  4: 'Sistema Leve',
  5: 'Diagnóstico Aprofundado',
  6: 'Diagnóstico Inteligente (SMART)',
  7: 'Monitor de Desempenho',
  8: 'Gerenciador de Drivers',
  9: 'Ajustes de Sistema (Tweaks)',
  10: 'Backup do Registro',
  11: 'Restaurar Registro',
  12: 'Manutenção Agendada',
  13: 'Verificação de Vírus',
  14: 'Varredura e Limpeza do Registro',
  15: 'Ferramentas Nativas do Windows',
  16: 'Analisador de Espaço em Disco',
  17: 'Auto-Atualização',
  18: 'Gerenciador de Pacotes',
  19: 'Perfis de Otimização',
  20: 'Hardening de Segurança',
};

function setStatus(state, text) {
  statusIndicator.className = 'status-indicator ' + state;
  statusText.textContent = text;
}

function formatOutput(output) {
  return output
    .replace(/\[WMS-OK\] /g, '')
    .replace(/\[WMS-ERRO\] /g, '')
    .trim();
}

async function runOption(opt) {
  const name = optionNames[opt] || `Opção ${opt}`;

  setStatus('running', `Executando: ${name}...`);

  try {
    if (interactiveOptions.includes(opt)) {
      setStatus('running', `${name} será executado em uma janela separada. Aguarde o término...`);
      const exitCode = await window.api.openInteractive(opt);
      if (exitCode === 0) {
        setStatus('success', `${name} concluída com sucesso!`);
      } else {
        setStatus('error', `${name} finalizada (código ${exitCode}). Verifique a janela do PowerShell.`);
      }
    } else {
      const result = await window.api.runOption(opt);
      if (result.code === 0) {
        const msg = formatOutput(result.output) || `${name} concluída com sucesso!`;
        setStatus('success', msg);
      } else {
        const msg = formatOutput(result.output) || `${name} — erro (código ${result.code})`;
        setStatus('error', msg);
      }
    }
  } catch (err) {
    setStatus('error', `Erro ao executar ${name}: ${err.message}`);
  }
}

document.querySelectorAll('.btn[data-opt]').forEach((btn) => {
  btn.addEventListener('click', () => {
    const opt = parseInt(btn.dataset.opt, 10);
    runOption(opt);
  });
});

btnExit.addEventListener('click', () => {
  if (typeof window.api !== 'undefined' && window.api.quit) {
    window.api.quit();
  } else {
    window.close();
  }
});

setStatus('idle', 'Pronto. Selecione uma opção acima.');
