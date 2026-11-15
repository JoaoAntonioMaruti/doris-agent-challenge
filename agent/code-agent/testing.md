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
