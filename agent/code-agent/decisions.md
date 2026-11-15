# Decisões

## T01
- Phoenix 1.8 API-only (`--no-html --no-assets --no-mailer --no-dashboard --no-gettext --no-live`), Bandit, Ecto/Postgrex, Req. Projeto gerado dentro de container `elixir:1.18`.
- Dockerfile multi-stage: `dev` (toolchain + deps, usado pelo `agent-test`), `build` (release prod), `runtime` (`debian:trixie-slim`, só a release). Migrations rodam via `Doris.Release.migrate/0` antes do `start`.
- Postgres via `pgvector/pgvector:pg17`: é Postgres comum, mas já deixa a extensão disponível para a T09 opcional sem trocar a imagem.
- `/health` responde 200 só se o banco responder `SELECT 1` (503 caso contrário). O healthcheck do compose usa `bin/doris rpc`, porque a imagem runtime não tem curl.
- Plug.Parsers só JSON, com limite de 40 MB (imagens chegam como data URI base64). Sessão/cookies removidos (API pura).
- `SECRET_KEY_BASE` tem default só de dev no compose (não há cookies/sessão); pode ser sobrescrito via env.

## T02
- Tool calling nativo verificado em 2026-11-15: `openai/gpt-6-luna` devolveu `tool_calls` válidos (1,8 s); `google/gemini-3.8-flash` também, após definir `max_tokens`.
- Chamadas ao LLM são **não-streaming**; o agente faz o streaming SSE para o proxy. Trade-off: o texto final aparece de uma vez (não token a token), em troca de um loop de tools mais simples e determinístico. Os feedbacks `doris` cobrem a espera.
- Fallback: só tenta o `FALLBACK_MODEL` em erro de transporte, 429 ou 5xx (uma vez). Erros 4xx não trocam de modelo.
- `max_tokens` sempre explícito (ver ocorrência 402 no log).
- Conteúdo da mensagem do usuário é repassado ao modelo exatamente como chegou (partes `text` + `image_url`).
- Encerramento: `try/rescue/after` no controller garante um evento terminal (`finish_reason` ou `error`) e exatamente um `[DONE]`. Se o cliente desconectar, o chunk falha silenciosamente e o turno termina (para a persistência completar).

## T03
- `Doris.Tools.Registry`: contratos das 7 tools do proxy como dados (schema JSON + validador simples, sem lib de JSON Schema). `tryon` aceita no máximo 1 garment já na validação; `avatar_pose` só `NORMAL`; `show_artifact.type` só `PRODUCT|GARMENT|TRYON_CARD`.
- `Doris.Tools.Executor.call(conversation_id, tool, args)`: argumento inválido nunca chega ao proxy (`invalid_arguments`); `conversation_id` sempre injetado; retry só para `retryable: true` (até 2 tentativas, backoff linear, não tenta se faltar <2 s para o deadline); 5xx sem envelope e erro de transporte contam como retryable.
- Estas são as tools *de baixo nível*. O LLM verá tools de alto nível (T04) que as orquestram.

## T04
- O LLM vê 7 tools de alto nível (`Doris.Agent.Tools`): `find_products`, `recommend_outfit`, `show_products`, `try_on`, `get_looks`, `show_look`, `get_wardrobe`. Cada uma é um pipeline determinístico em `Doris.Agent.Orchestrators` sobre as tools do proxy. `run_tryon_pipeline` do plano é o `try_on`: garment_creation → tryon (sempre 1 garment) → show_artifact(TRYON_CARD), com fallback para show_artifact(PRODUCT).
- Allowlist em `Doris.Agent.State`: produtos, garments, try-ons e looks só entram quando retornados pelo proxy. IDs desconhecidos voltam como erro para o modelo **sem chamar o proxy**.
- Restrições no código: teto de preço e cores evitadas filtram a busca (`Doris.Agent.Filters`, com variações de gênero/número e sem acento) e são **rechecados** no `show_products`/`try_on`. Dentro do turno as restrições só apertam.
- Prompt injection: descrições do catálogo vão truncadas (240 chars) no campo `untrusted_store_description`, e o system prompt manda tratá-las como dado.
- Visão para looks: resultados de tool são só texto, então `get_looks` anexa as imagens dos 2 looks mais recentes numa mensagem `user` logo após os tool results.
- Limites: 6 iterações, deadline interno de 80 s (`turn_budget_ms`), timeout do LLM limitado ao tempo restante, e chamada idêntica repetida no turno não é reexecutada. Ao estourar, o turno termina com texto amigável (nunca fica sem resposta).
- Erro do LLM na 1ª iteração → evento `error`; depois de tools já executadas → texto de fallback (os cards já mostrados ficam).

## T05
- Tabelas `users`, `conversations`, `messages`, `tool_executions` (migration única), com uniques `(conversation_id, sequence)` e parcial `(conversation_id, tool_call_id) WHERE tool_call_id IS NOT NULL`, além do índice `(user_id, updated_at)`. `user_preferences` fica para a T07.
- `user_id` = `request.user` integral. O dono da conversa é quem a criou (`INSERT … ON CONFLICT DO NOTHING` + leitura). Outro usuário com o mesmo `conversation_id` recebe erro e nenhum histórico.
- `messages.content` guarda a mensagem no formato do modelo (inclui `tool_calls`). O contexto pega as últimas 40 e descarta o início até a primeira mensagem `user`, então nunca começa no meio de um par tool_call/tool.
- Imagens: data URI base64 vira placeholder no banco. A mensagem corrente vai inteira ao modelo. URLs públicas (looks) viram referência textual.
- `save_turn` é uma transação com `SELECT … FOR UPDATE` na conversa (serializa turnos concorrentes). Execuções com `tool_call_id` repetido são ignoradas (idempotência).
- Registro de execuções: os orquestradores mandam `{:doris_tool_execution, …}` para o próprio processo e o Runner coleta depois de cada tool call, com id `<tool_call_id>#n`. Evita threading de estado em cada pipeline, e o canal é local ao processo do turno.
- A allowlist de IDs da conversa é reconstruída a partir de `tool_executions` com status ok (search, garment_creation, wardrobe, tryon, looks).
