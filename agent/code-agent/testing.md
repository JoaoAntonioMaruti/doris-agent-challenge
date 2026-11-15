# Testes

Todos os comandos rodam em Docker.

- Unit/integração: `docker compose --profile test run --rm agent-test`
- Runtime: `docker compose up --build -d` e `docker compose exec proxy python -c "import urllib.request as u;print(u.urlopen('http://agent:8000/health').read())"`

## T01
- `agent-test`: `3 tests, 0 failures` (inclui `HealthControllerTest`).
- `/health` via rede do compose: `200 {"status":"ok"}`. Agente `healthy` no `docker compose ps`.

## T02
- `agent-test`: 10 tests, 0 failures (`Doris.SSETest`, `DorisWeb.ChatControllerTest` com `Req.Test`: texto+finish+[DONE], imagem chega ao modelo, fallback 503→gemini, erro do modelo → evento `error` + `[DONE]`, body inválido).
- Real via proxy: `curl localhost:3000/chat -d '{"user_id":"u_bruno","conversation_id":"t02-smoke-1","message":"Oi"}'` → `{"type":"text","delta":"Oi, Bruno! 😊 Como posso ajudar com seu estilo hoje?"}` + `{"type":"done"}`.
- SSE bruto do agente (de dentro do container do proxy): `text/event-stream`, 1 chunk de texto, 1 `finish_reason: stop`, `[DONE]` exatamente 1 vez.

## T03
- `agent-test`: 15 tests, 0 failures (`Doris.Tools.ExecutorTest`: envelope/conversation_id, show_artifact sem data, retry de retryable, sem retry em permanente, argumentos inválidos não chamam o proxy).
- Real (rpc no container do agente, conversa `t02-smoke-1` de u_bruno): search_by_text 3 resultados (p01 "Camisa de linho branca" R$249.9) → garment_creation (TOP) → tryon (`tryons/u_bruno/p01.jpg`) → avatar 1 → looks 3 → wardrobe TOP 4 → show_artifact `{:ok, %{}}`; `nao-existe` → `not_found` retryable=false; conversa desconhecida → `conversation_not_found`.
