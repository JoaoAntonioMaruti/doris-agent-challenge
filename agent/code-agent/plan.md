# Plano — Doris Agent (Elixir/Phoenix)

## Context
Substituir o agente Python placeholder (`agent/app.py`, `agent/Dockerfile`, `requirements.txt`) por um agente Elixir/Phoenix API-only que segue o contrato OpenAI-SSE do README, chama as tools do proxy (`docs/proxy-api.md`) e usa OpenRouter. O plano do usuário (T01–T10) é a especificação; este arquivo registra como executá-lo dado o que o repositório contém.

## Fatos verificados no repo
- `docker-compose.yml`: `proxy` (porta 3000, `AGENT_URL=http://agent:8000`) e `agent` (`env_file: .env`, `PROXY_URL`). Branch `solucao` criada pelo usuário.
- Proxy suporta falhas determinísticas via `FAULTS_FILE` (JSON `{"rules":[{tool, match, times, effect: "empty"|{delay_ms}|{error:{status,code,retryable}}}]}`, `proxy/app/faults.py`) e `CATALOG_OVERRIDES_FILE` (patch de itens existentes, `proxy/app/seed.py:32`). Também `LATENCY_SCALE` e `TURN_TIMEOUT_S`.
- Isso permite testes de falha **sem tocar em `proxy/`**: adicionar no compose, sob `profiles: [eval]`, serviços novos `proxy-faults` (build `./proxy`, `FAULTS_FILE`/`CATALOG_OVERRIDES_FILE` montados de `agent/evals/fixtures/`, `AGENT_URL=http://agent-eval:8000`) e `agent-eval` (mesma imagem do agente, `PROXY_URL=http://proxy-faults:3000`). O serviço `proxy` original permanece intacto.
- Runner E2E usa `POST /chat` do proxy (`proxy/app/chat.py:142`) e `GET /admin/log` — só no runner.

## Execução
0. Branch `solucao` já criada pelo usuário: `git switch solucao` e confirmar. Registrar início oficial no `log.md`.
1. **T01** — `agent/` vira projeto Mix `doris` (Phoenix API-only, sem HTML/assets/mailer; deps Req, Ecto/Postgrex, Jason). Gerado *dentro* de container `elixir:1.18` (`docker run -v ./agent:/app`). Dockerfile multi-stage (build → release). Compose: serviço `db` (postgres:17 / pgvector image para T09), volume, healthcheck; `agent.depends_on: db: service_healthy`; migrations no entrypoint (`Doris.Release.migrate`). Serviço `agent-test` (profile `test`) para `mix test`. Remover `app.py`/`requirements.txt`. Criar `agent/code-agent/{plan,log,decisions,testing}.md`.
2. **T02** — `DorisWeb.ChatController` com `Plug.Conn.chunk/2`; `Doris.SSE` (encoder de chunk/feedback/erro/[DONE], fechamento em `try/after`); `Doris.LLM.OpenRouter` (Req, config em `runtime.exs`, fallback em falha). Testar tool calling do `gpt-6-luna` cedo e registrar em decisions.md.
3. **T03** — `Doris.Tools.Registry` (schemas JSON) + `Doris.Tools.Executor` (Req, envelope `ok/error`, retry só se `retryable`, injeta `conversation_id`). Testes com `Req.Test`.
4. **T04** — `Doris.Agent.Runner` (loop, max iterações, deadline 80 s) + `Doris.Agent.Orchestrators` (find_products, recommend_outfit, run_tryon_pipeline, show_products) expostos ao LLM como tools de alto nível; `Doris.Agent.Allowlist` de IDs por conversa; filtros de preço/cor no código; fallback PRODUCT em falha de try-on.
5. **T05** — Migrations/schemas conforme seção 5 do plano; `Doris.History` monta contexto sem quebrar pares tool_call/result; imagens base64 persistidas como placeholder; rejeita conversation_id de outro user.
6. **T06** — Fluxo no frontend via compose; evidência em testing.md.
7. **T07** — `Doris.Memory` (+ `Structured`), `MEMORY_MODE` validado no boot, extração síncrona com JSON validado, merge com correções.
8. **T08** — `agent/evals/` (runner em Elixir executado no container `agent-eval`/`agent-test`, cenários em JSON, fixtures de faults/overrides, relatórios em `agent/evals/reports/`).
9. **T09** (opcional) — pgvector, `Doris.Memory.Semantic`, dimensão lida da resposta.
10. **T10** — README, docs, `mix format --check-formatted`, `mix test`, `git status` restrito a `agent/` + compose.

Cada tarefa: teste pertinente em container → log.md com horário real (`date '+%F %T %:z'` em TZ America/Sao_Paulo) → `git diff/status` → commit `TNN: …` com trailer Co-Authored-By.

## Requisitos detalhados (checklist por tarefa)
- **T02:** chunk de erro `{"error":{"message","type":"agent_error"}}` seguido de encerramento; `image_url` (data URI) repassado ao LLM sem perda; `[DONE]` exatamente uma vez.
- **T04:** máx. 1 garment por `tryon` (garantido no código); múltiplos tool calls por resposta; `tool_call_id` preservado; texto do catálogo delimitado como dado não confiável no prompt (anti prompt injection); IDs fora da allowlist rejeitados antes de chamar o proxy.
- **T05:** índices/uniques da seção 5 (`unique (conversation_id, sequence)`, `unique (conversation_id, tool_call_id)`, `(user_id, updated_at)`); `user_id` completo, nunca normalizado; mensagem + tool results na mesma transação; base64 vira placeholder no histórico; conversation_id de outro usuário → erro sem expor histórico.
- **T07:** merge — correção explícita vence, fato ausente na extração é preservado; lock otimista por `version`; isolamento `u_ana__abc` × `u_ana__def` testado.
- **T09:** boot falha se `MEMORY_MODE=v2` sem extensão/migração; falha de embedding degrada para v1 sem derrubar o chat; idempotência por `source_key`; dimensão lida da resposta.
- **T08 — suíte de falhas** (fixtures em `agent/evals/fixtures/`, rodando via `proxy-faults`): erro `retryable=true` (retry), erro permanente (sem retry), busca vazia, preço acima do teto (`CATALOG_OVERRIDES_FILE`), descrição maliciosa, argumento inválido, ID alucinado, loop sem progresso (limite de iterações), deadline (`delay_ms`). Relatório por cenário: entrada, tools chamadas, produtos, cards, resultado, latência, motivo de falha, memory_mode, modelo, data/hora; p50/p95 só sobre amostras reais.
- **T06 — evidência no frontend:** validação automatizada no navegador (Claude in Chrome) em `http://localhost:3000`, com screenshots/descrição de texto, feedback, card de produto e try-on registrados em `testing.md`; se o navegador não estiver disponível, validação manual pelo usuário e registro explícito disso.
- **T10 — README:** `agent/README.md` com todas as seções exigidas (ideia e arquitetura, decisões e trade-offs, o que ficou de fora, próximos passos, uso de IA com acertos e erros, início/fim reais, como rodar) e links para `agent/code-agent/{plan,log,decisions,testing}.md` e `agent/evals/reports/`.

## Verificação
- `docker compose up --build -d && curl localhost:8000/health` (porta exposta só para debug, ou via `docker compose exec`).
- `docker compose --profile test run --rm agent-test mix test`.
- `docker compose --profile eval run --rm agent-eval mix doris.eval` → `agent/evals/reports/report.{json,md}` com p50/p95.
- Teste manual no `http://localhost:3000` para T06.

## Riscos
- Se `.env` sem `OPENROUTER_API_KEY` ou modelo não suportar tools, parar e reportar (não trocar modelo).
- `Plug.Conn.chunk` exige SSE sem buffering; validar com proxy real em T02.

## Status
- T01–T10 concluídas.
