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
