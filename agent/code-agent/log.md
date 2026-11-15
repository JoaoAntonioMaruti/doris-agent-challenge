# Log de execução

- Início oficial: 2026-11-15 20:31:12 -03:00
- Término: PENDENTE
- Fuso: America/Sao_Paulo

| ID | Tarefa | Estado | Início real | Conclusão real | Evidência | Commit SHA |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | Docker e contrato mínimo | Concluída | 2026-11-15 20:31:12 -03:00 | 2026-11-15 20:37:18 -03:00 | `agent-test`: 3 tests, 0 failures; `GET http://agent:8000/health` → 200 `{"status":"ok"}` a partir do container do proxy | 2c707e1 |
| T02 | OpenRouter + resposta SSE | Concluída | 2026-11-15 20:37:32 -03:00 | 2026-11-15 20:40:06 -03:00 | 10 tests, 0 failures; `POST /chat` (proxy) "Oi" → texto real do gpt-6-luna + `done`; SSE bruto: 1 texto, 1 `finish_reason: stop`, `[DONE]` ×1 | 575bbf3 |
| T03 | Tools HTTP | Concluída | 2026-11-15 20:40:10 -03:00 | 2026-11-15 20:41:51 -03:00 | 15 tests, 0 failures; 7 tools chamadas no proxy real (search→p01 R$249.9, garment, tryon, avatar, looks, wardrobe, show_artifact `ok`; `not_found` e `conversation_not_found` com retryable=false) | — |
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
- `.env` sem chave no início; usuário preencheu antes da T02.
- T02: `gemini-3.8-flash` com tools retornou 402 ("You requested up to 65536 tokens, but can only afford 10666"): sem `max_tokens` a OpenRouter reserva o máximo do modelo contra o limite de crédito da chave. Resolvido com `max_tokens` explícito (`LLM_MAX_TOKENS`, padrão 2048).
- T02: no adaptador de teste do Plug, `chunk/2` devolve conn nova; o emissor do controller guarda a conn mais recente.
