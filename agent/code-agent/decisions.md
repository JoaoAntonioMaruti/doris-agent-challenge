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

## T07
- `Doris.Memory` (fachada) escolhe a estratégia por `MEMORY_MODE` (`v1` padrão, `v2`), validado em `runtime.exs` (valor inválido derruba o boot). `Doris.Memory.Semantic` ainda delega para v1 (T09).
- v1 = `user_preferences` (size, disliked_colors, preferred_styles, budget_max, notes, version), chave = `user_id` completo.
- Extração: o LLM só propõe um *change set* em JSON a partir da **mensagem do usuário** (`add_*`/`remove_*`, null = não mencionado). Validação de tipo/tamanho no código, merge no código (`Preferences.merge/2`): correção explícita vence, ausência preserva, remoção só explícita. Persistência com lock otimista (`version`), 2 tentativas.
- Momento: a extração roda em `Task.Supervisor.async_nolink` **em paralelo** ao loop do agente e é aguardada (até 15 s) antes do `[DONE]`. Uma conversa nova, aberta depois que o turno termina, sempre vê o dado, sem race silenciosa e quase sem latência extra. Falha/timeout é logado e o perfil anterior fica intacto.
- Uso: preferências entram no system prompt. `disliked_colors` também entram em `State.avoid_colors`, ou seja, filtro rígido em busca/show/try-on. `budget_max` é só dica no prompt (o teto rígido vem do pedido do turno).
- **Desvio do plano:** `MEMORY_MODEL` padrão = `openai/gpt-6-luna`, não `google/gemini-3.8-flash`. Medido em 2026-11-15: gemini truncou o JSON em ~50% das chamadas; luna 8/8. Continua configurável.

## T08
- Runner E2E caixa-preta em Elixir (`agent/evals/run.exs`), executado no container `agent-test` com `mix run --no-start`. Fala só com `POST /chat` do proxy e usa `GET /admin/log` apenas para verificação (nunca em `agent/lib`).
- Cenários em JSON (`evals/scenarios.json`, `evals/faults.json`) com asserções declarativas por turno (tools exigidas/proibidas, tipos de card, teto de preço, produtos proibidos/exigidos, termos proibidos em cards, contagem de chamadas, feedback de erro, outcome, latência, regex no texto). Invariantes checados em todo turno: sem erro no stream, outcome `done`, tryon ≤1 peça, try-on gerado sempre mostrado, erro `retryable=false` não repetido, PRODUCT mostrado veio de uma busca.
- Falhas sem tocar em `proxy/`: profile `eval` sobe `proxy-faults` (o mesmo `./proxy`, com `FAULTS_FILE`/`CATALOG_OVERRIDES_FILE` de `agent/evals/fixtures/`) + `agent-eval` apontando para ele. O `proxy` original segue sem faults.
- Relatórios: `evals/reports/<suite>-<timestamp>.{json,md}` e `<suite>-latest.*`, com p50/p95 só sobre as latências medidas (amostras pequenas, não generalizar).
- Asserções de texto são regex simples; a avaliação de "coerência" do look (cenário 2) não é automatizada além de tools/cards.

## T09 (MEMORY_MODE=v2, opt-in)
- Referência: `~/Developer/poc_embedding` (indicada pelo usuário). Mesmo padrão: `pgvector` (`Pgvector.Ecto.Vector`, `Doris.PostgrexTypes`), validação da dimensão no cliente, busca por `cosine_distance` filtrada por `user_id`.
- Embeddings só via OpenRouter (`/embeddings`, `openai/text-embedding-3-small`). Dimensão **1536 verificada** na resposta real em 2026-11-15; vetores de outro tamanho são rejeitados (`{:unexpected_dimensions, …}`).
- Migração habilita `vector` e cria `semantic_memories` (unique `user_id, source_key`; índice por `user_id`; sem índice vetorial — poucas linhas por usuário, scan filtrado basta).
- v2 = v1 + fatos. `Semantic.update` roda a extração v1 e a de fatos em paralelo (na mesma tarefa supervisionada e aguardada do turno, então não há entrega assíncrona perdida em restart). Fatos: até 3 por mensagem, ≤200 chars, "A pessoa…", extraídos pelo `MEMORY_MODEL`.
- Recall: embedding da mensagem atual → top-3 do mesmo usuário com distância ≤ 0,65 → anexados ao prompt como "Lembranças relevantes". Cores evitadas continuam vindo só de `user_preferences` (regra rígida não depende de top-k).
- Idempotência: `source_key = "facts-v1:" <> sha256(fato normalizado)`, `ON CONFLICT DO NOTHING`; `pg_advisory_xact_lock` por usuário serializa escritas concorrentes.
- Degradação: qualquer falha (extração, embedding, banco) é logada e o turno segue com v1; `user_preferences` não é tocada. Boot com `MEMORY_MODE=v2` sem extensão/tabela falha cedo (`Doris.Application`).
- Limite conhecido: a v1 guarda só uma `notes` (sobrescrita). Por isso v2 ganha em fatos acumulados (m3). Não há deduplicação semântica (fatos parecidos com texto diferente viram linhas distintas) nem expiração.
