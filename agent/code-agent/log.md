# Log de execução

- Início oficial: 2026-11-15 20:31:12 -03:00
- Término: 2026-11-15 21:25:47 -03:00
- Fuso: America/Sao_Paulo

| ID | Tarefa | Estado | Início real | Conclusão real | Evidência | Commit SHA |
| --- | --- | --- | --- | --- | --- | --- |
| T01 | Docker e contrato mínimo | Concluída | 2026-11-15 20:31:12 -03:00 | 2026-11-15 20:37:18 -03:00 | `agent-test`: 3 tests, 0 failures; `GET http://agent:8000/health` → 200 `{"status":"ok"}` a partir do container do proxy | 2c707e1 |
| T02 | OpenRouter + resposta SSE | Concluída | 2026-11-15 20:37:32 -03:00 | 2026-11-15 20:40:06 -03:00 | 10 tests, 0 failures; `POST /chat` (proxy) "Oi" → texto real do gpt-6-luna + `done`; SSE bruto: 1 texto, 1 `finish_reason: stop`, `[DONE]` ×1 | 575bbf3 |
| T03 | Tools HTTP | Concluída | 2026-11-15 20:40:10 -03:00 | 2026-11-15 20:41:51 -03:00 | 15 tests, 0 failures; 7 tools chamadas no proxy real (search→p01 R$249.9, garment, tryon, avatar, looks, wardrobe, show_artifact `ok`; `not_found` e `conversation_not_found` com retryable=false) | 2c491c4 |
| T04 | Agent Loop e artifacts | Concluída | 2026-11-15 20:42:15 -03:00 | 2026-11-15 20:45:59 -03:00 | 26 tests, 0 failures; real cenário 1 (`t04-s1-20061`): search_by_text → show_artifact PRODUCT p01 → garment_creation → tryon (1 garment) → show_artifact TRYON_CARD, 20,5 s, p02 R$459 filtrado; "capital da França" sem tools, 1,3 s | 285d9a6 |
| T05 | Histórico persistente | Concluída | 2026-11-15 20:46:24 -03:00 | 2026-11-15 20:49:25 -03:00 | 33 tests, 0 failures; real cenário 5 (2 turnos, mesma conversa): turno 2 usou p07 vindo da busca do turno 1 (allowlist persistida) → garment_creation → tryon → show TRYON_CARD; 8 mensagens com pares tool_call/tool íntegros, 4 tool_executions | ec875cf |
| T06 | Teste integrado do fluxo principal | Concluída | 2026-11-15 20:50:28 -03:00 | 2026-11-15 20:52:18 -03:00 | Frontend `localhost:3000` via Claude in Chrome: cenário 1 mostrou feedback ✓ busca/try-on, card p01 R$249,90 e imagem do try-on (`code-agent/evidence/t06-cenario1-frontend.jpg`); cenário 5 após ajuste de prompt: texto sem markdown + alternativa p07 com card; 33 tests, 0 failures | aad9395 |
| T07 | Memória estruturada v1 com feature flag | Concluída | 2026-11-15 20:53:02 -03:00 | 2026-11-15 21:00:25 -03:00 | 40 tests, 0 failures; real cenário 4: `u_ana__t071873` salvou M/amarelo/minimalista; conversa nova respondeu "Você veste tamanho M e evita amarelo."; `u_ana__x071873` não sabe nada; "vestidos midi": proxy retornou p04 (amarelo) em 1º e o filtro removeu; `MEMORY_MODE=v3` falha no boot | e410688 |
| T08 | Runner E2E e cenários adversariais | Concluída | 2026-11-15 21:00:38 -03:00 | 2026-11-15 21:15:17 -03:00 | 41 tests, 0 failures; `evals/run.exs` via proxy real: cenários 6/6 em 2 rodadas (p50 5,8 s / p95 32,0 s na última, 11 turnos); falhas 6/6 após corrigir asserção do f3 (1ª rodada 5/6) — `evals/reports/*-latest.md` | 3e20d5b |
| T09 | Memória semântica v2 (opcional) | Concluída | 2026-11-15 21:15:20 -03:00 | 2026-11-15 21:24:39 -03:00 | 45 tests, 0 failures; dimensão 1536 confirmada na OpenRouter; `evals/memory.json` v1 2/3 (m3: nota sobrescrita, esqueceu "bicicleta") × v2 3/3 (recupera bicicleta + alergia a lã); falha de embedding degrada para v1 (teste) | b75d39a |
| T10 | Documentação de entrega | Concluída | 2026-11-15 21:24:44 -03:00 | 2026-11-15 21:25:47 -03:00 | README de entrega; `mix format --check-formatted` ok; `compile --warnings-as-errors` ok; 45 tests, 0 failures (banco de teste recriado); 3 migrations aplicadas; `/health` 200; fora de `agent/` só `docker-compose.yml` (serviço `agent` + `db`, `agent-test`, `proxy-faults`, `agent-eval`) | eb4f380 |

## Ocorrências
- T09: usuário indicou `~/Developer/poc_embedding` como referência; seguido o padrão (pgvector Ecto type, `Postgrex.Types`, validação de dimensão, `cosine_distance`), com o endpoint `/embeddings` da OpenRouter.
- T09: 1ª sonda de embeddings via Req no container deu timeout (pontual); repetida em 1,3 s. Cliente usa `receive_timeout` 20 s.
- T09: fatos extraídos vinham como "Ela trabalha…" para Bruno (gênero suposto). Prompt passou a exigir "A pessoa…".
- T09: na 1ª comparação o caso indireto (m2) passou também em v1, porque `notes` guardou o fato. A diferença só aparece com fatos acumulados (m3): v1 guarda uma única `notes`, sobrescrita.
- T08: catálogo revelou p25 "Polo de tricô mostarda" (tag amarelo, sem "amarelo" no nome/descrição, e a busca não retorna tags). Filtro de cor ganhou tabela de tons (amarelo→mostarda/ocre/…).
- T08: 1ª rodada da suíte de falhas 5/6: f3 ("smoking", busca vazia) falhou por `artifacts_max: 0`, mas o agente disse "Não encontrei smoking" e ofereceu alternativa real (blazer p26) — comportamento pedido pelo prompt. A asserção estava errada; trocada por texto honesto + nenhum card de smoking. Rodada seguinte 6/6.
- T08: IDs alucinados, argumento inválido e loop sem progresso não são reproduzíveis de forma determinística com o modelo real; estão cobertos por testes unitários com LLM roteirizado (`RunnerTest`, `ExecutorTest`), não pelo E2E.
- T07: 1ª execução real do cenário 4 não salvou nada (`memory update failed: :invalid_json`); a conversa B "acertou" por coincidência. Causa: `google/gemini-3.8-flash` com `response_format: json_object` devolvia JSON truncado (3/6 falhas com max_tokens 300; ~4/8 mesmo com 1500 e `reasoning.enabled=false`). `openai/gpt-6-luna` acertou 8/8 (~2,6 s). Padrão de `MEMORY_MODEL` trocado para gpt-6-luna (desvio do plano, documentado em decisions.md). Saída inválida agora é logada (300 chars).
- T06: frontend não renderiza markdown; o texto do cenário 1 mostrou `**…**` cru. Prompt passou a exigir texto simples.
- T05: `String.to_existing_atom/1` no despacho das tools falhava quando `Orchestrators` ainda não estava carregado (só apareceu nos testes; release carrega tudo no boot). Trocado por mapa explícito nome → função.
- T05: catálogo não tem jaqueta jeans (só p07 couro); a Doris respondeu corretamente que não encontrou, mas não ofereceu a de couro como alternativa. Resolvido na T06 (prompt).
- T01: release falhou com `GLIBC_2.38 not found` (imagem `elixir:1.18` é Debian trixie; runtime era bookworm). Corrigido usando `debian:trixie-slim`.
- T01: `prod.exs` gerado com `force_ssl` redirecionava `/health` (301). Removido: o agente só é acessado via HTTP na rede interna do compose.
- `.env` sem chave no início; usuário preencheu antes da T02.
- T02: `gemini-3.8-flash` com tools retornou 402 ("You requested up to 65536 tokens, but can only afford 10666"): sem `max_tokens` a OpenRouter reserva o máximo do modelo contra o limite de crédito da chave. Resolvido com `max_tokens` explícito (`LLM_MAX_TOKENS`, padrão 2048).
- T02: no adaptador de teste do Plug, `chunk/2` devolve conn nova; o emissor do controller guarda a conn mais recente.
