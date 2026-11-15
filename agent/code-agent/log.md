# Log de execução

- Início oficial: 2026-11-15 20:31:12 -03:00
- Término: PENDENTE
- Fuso: America/Sao_Paulo

| ID | Tarefa | Estado | Início real | Conclusão real | Evidência | Commit SHA |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | Docker e contrato mínimo | Concluída | 2026-11-15 20:31:12 -03:00 | 2026-11-15 20:37:18 -03:00 | `agent-test`: 3 tests, 0 failures; `GET http://agent:8000/health` → 200 `{"status":"ok"}` a partir do container do proxy | — |
| T02 | OpenRouter + resposta SSE | Pendente | — | — | — | — |
| T03 | Tools HTTP | Pendente | — | — | — | — |
| T04 | Agent Loop e artifacts | Pendente | — | — | — | — |
| T05 | Histórico persistente | Pendente | — | — | — | — |
| T06 | Teste integrado do fluxo principal | Pendente | — | — | — | — |
| T07 | Memória estruturada v1 com feature flag | Pendente | — | — | — | — |
| T08 | Runner E2E e cenários adversariais | Pendente | — | — | — | — |
| T09 | Memória semântica v2 (opcional) | Pendente | — | — | — | — |
| T10 | Documentação de entrega | Pendente | — | — | — | — |

## Ocorrências
- T01: release falhou com `GLIBC_2.38 not found` (imagem `elixir:1.18` é Debian trixie; runtime era bookworm). Corrigido usando `debian:trixie-slim`.
- T01: `prod.exs` gerado com `force_ssl` redirecionava `/health` (301). Removido: o agente só é acessado via HTTP na rede interna do compose.
- `.env` existe localmente, mas `OPENROUTER_API_KEY` estava vazia no início; é necessária a partir da T02.
