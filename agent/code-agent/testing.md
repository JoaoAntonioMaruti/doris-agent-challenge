# Testes

Todos os comandos rodam em Docker.

- Unit/integração: `docker compose --profile test run --rm agent-test`
- Runtime: `docker compose up --build -d` e `docker compose exec proxy python -c "import urllib.request as u;print(u.urlopen('http://agent:8000/health').read())"`

## T01
- `agent-test`: `3 tests, 0 failures` (inclui `HealthControllerTest`).
- `/health` via rede do compose: `200 {"status":"ok"}`. Agente `healthy` no `docker compose ps`.
