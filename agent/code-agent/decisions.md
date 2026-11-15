# Decisões

## T01
- Phoenix 1.8 API-only (`--no-html --no-assets --no-mailer --no-dashboard --no-gettext --no-live`), Bandit, Ecto/Postgrex, Req. Projeto gerado dentro de container `elixir:1.18`.
- Dockerfile multi-stage: `dev` (toolchain + deps, usado pelo `agent-test`), `build` (release prod), `runtime` (`debian:trixie-slim`, só a release). Migrations rodam via `Doris.Release.migrate/0` antes do `start`.
- Postgres via `pgvector/pgvector:pg17`: é Postgres comum, mas já deixa a extensão disponível para a T09 opcional sem trocar a imagem.
- `/health` responde 200 só se o banco responder `SELECT 1` (503 caso contrário). O healthcheck do compose usa `bin/doris rpc`, porque a imagem runtime não tem curl.
- Plug.Parsers só JSON, com limite de 40 MB (imagens chegam como data URI base64). Sessão/cookies removidos (API pura).
- `SECRET_KEY_BASE` tem default só de dev no compose (não há cookies/sessão); pode ser sobrescrito via env.
