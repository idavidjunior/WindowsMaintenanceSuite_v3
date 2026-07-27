# Ecossistema — Inteligência Contínua

## Missão
Manter o ecossistema evoluindo com resiliência e objetividade. Cada sessão deve deixar o sistema mais inteligente que antes.

## Regras
1. **Nunca duplicar instâncias** — o launcher `OpenCode-Launcher.cmd` já garante single instance. Respeitar.
2. **Sempre documentar descobertas** — qualquer ajuste, configuração, ou aprendizado relevante vai para este arquivo.
3. **Resiliência primeiro** — antes de adicionar complexidade, garantir que o que existe não quebra.
4. **Objetividade** — cada ação deve ter propósito claro. Sem firula, sem código morto.
5. **Evoluir o ecossistema** — integrações, automações, MCP servers, scripts — tudo que automatizar e fortalecer o ambiente.

## Histórico de Aprendizados
- 27/07/2026: Single instance launcher criado para OpenCode (OpenCode-Launcher.cmd)
- 27/07/2026: 10 novos repositórios criados e sincronizados no GitHub
- 27/07/2026: ADB via Tailscale configurado e funcional (100.64.71.9:5555)
- 27/07/2026: Proxy NVIDIA integrado no opencode.jsonc

## Stack Atual
- OpenCode Desktop (single instance)
- Tailscale (rede overlay para dispositivos móveis)
- ADB (debug Android via Tailscale)
- PowerShell 5.1 (runtime principal)
- Python (MCP servers e automações)
