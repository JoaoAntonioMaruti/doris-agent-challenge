# Agente da Doris (Elixir/Phoenix)

Documentos de apoio, mais detalhados:

- [`code-agent/plan.md`](code-agent/plan.md): plano executado e status.
- [`code-agent/log.md`](code-agent/log.md): horário real de cada tarefa, evidência, SHA do commit e ocorrências.
- [`code-agent/decisions.md`](code-agent/decisions.md): decisões por tarefa.
- [`code-agent/testing.md`](code-agent/testing.md): o que foi testado e o resultado.
- [`evals/reports/`](evals/reports/): relatórios E2E (`*-latest.md`).

## Ideia e arquitetura

**O LLM decide a intenção e escolhe entre candidatos; o código garante as regras.** O modelo nunca chama as tools
do proxy diretamente. Ele vê 7 tools de alto nível, e cada uma é um pipeline determinístico em Elixir:

| Tool do modelo | O que o código faz |
| --- | --- |
| `find_products` | `search_by_text` → filtro rígido de preço e cores evitadas → resumo com a descrição marcada como não confiável |
| `recommend_outfit` | uma busca por peça (camisa, calça, sapato…) → candidatos agrupados |
| `show_products` | confere a allowlist, o teto e as cores → `show_artifact(PRODUCT)` |
| `try_on` | `garment_creation` → `tryon` (sempre 1 peça) → `show_artifact(TRYON_CARD)`; se falhar, mostra o card do produto |
| `get_looks` / `show_look` | `looks` + imagens anexadas ao modelo de visão → `show_artifact(TRYON_CARD)` |
| `get_wardrobe` | `wardrobe` |

```
proxy ──POST /v1/chat/completions──▶ ChatController (SSE, try/after → 1 evento final + [DONE])
                                       │ History.open (dono da conversa) · Memory.load
                                       │ Task: Memory.update (em paralelo, aguardada antes do [DONE])
                                       ▼
                         Agent.Runner (≤ 6 iterações, deadline 80 s)
                         LLM ⇄ Agent.Tools → Orchestrators → Tools.Executor ──▶ proxy /tools/*
                                       │                        (valida args, retry só se retryable)
                                       ▼
                         History.save_turn (transação: mensagens + tool_executions)
Postgres (pgvector/pg17): users · conversations · messages · tool_executions · user_preferences · semantic_memories
```

- **Allowlist de IDs:** produtos, peças, try-ons e looks só podem ser usados se vieram de uma resposta do proxy na
  mesma conversa. A allowlist é reconstruída de `tool_executions` a cada turno. Um ID inventado volta como erro
  para o modelo, sem chamar o proxy.
- **Histórico:** o agente guarda a conversa, já que o proxy só envia a mensagem atual. A janela de contexto sempre
  começa numa mensagem `user`, então nunca separa uma `tool_call` do seu resultado. Imagens em base64 viram
  placeholder no banco.
- **Memória v1** (`MEMORY_MODE=v1`, padrão): `user_preferences` com tamanho, cores evitadas, estilos, orçamento e
  notas. O LLM só propõe um *change set* em JSON; validação, merge e lock otimista ficam no código. As cores
  evitadas viram filtro rígido.
- **Memória v2** (`MEMORY_MODE=v2`, opt-in): v1 mais fatos livres com embeddings (`text-embedding-3-small` via
  OpenRouter, 1536 dims, pgvector), top-3 do mesmo usuário por similaridade. As restrições continuam vindo da v1.

## Decisões e trade-offs

- **Elixir/Phoenix sem framework de agente.** O loop é uma função recursiva de ~100 linhas, e o estado do turno é
  uma struct. Não usei GenServer, Oban nem macros. Em troca, perde-se o ecossistema LangGraph (checkpoints,
  tracing prontos).
- **Tools de alto nível em vez de expor as 7 tools cruas.** Menos liberdade para o modelo e menos tokens por
  turno. O que não pode falhar (ordem garment→tryon, 1 peça, mostrar o try-on, teto de preço) fica fora do
  prompt.
- **LLM não-streaming, SSE para o proxy.** O texto chega inteiro no fim, não token a token, mas o loop de tools
  fica simples. Os feedbacks `doris` cobrem a espera.
- **Extração de memória síncrona ao turno, em paralelo ao loop.** Uma conversa nova sempre vê o que foi dito, sem
  race silenciosa, e a latência extra é quase nula. O custo é uma chamada de LLM a mais por turno.
- **Modelos:** `openai/gpt-6-luna` no agente, com fallback `google/gemini-3.8-flash` só em erro 5xx, 429 ou de
  transporte. **Desvio do plano:** a memória usa `gpt-6-luna`, porque o gemini truncou o JSON em ~50% das
  extrações medidas. Os dois são configuráveis por env. `max_tokens` é sempre explícito, porque sem ele a
  OpenRouter reserva o máximo do modelo e o limite de crédito da chave devolve 402.
- **Filtro de cor por palavras e tons** (amarelo → mostarda/ocre…), porque a busca não devolve tags. É simples e
  previsível, mas é uma lista fixa.
- **E2E em Elixir dentro do container**, falando só com `POST /chat` do proxy. A suíte de falhas usa uma segunda
  cópia do proxy (`proxy-faults`) com os mecanismos que ele já tem (`FAULTS_FILE`, `CATALOG_OVERRIDES_FILE`),
  sem tocar em `proxy/`.

## Resultados medidos

As amostras são pequenas; servem como evidência, não como benchmark (detalhes em `code-agent/testing.md`).

| Suíte | Resultado | p50 / p95 por turno |
| --- | --- | --- |
| 6 cenários do README (2 rodadas) | 6/6 e 6/6 | 5,8 s / 32,0 s (última) |
| Falhas: retryable, erro permanente, busca vazia, preço alterado, prompt injection, deadline | 6/6 (1ª rodada 5/6 por asserção errada no teste) | 21,3 s / 66,9 s |
| Memória v1 × v2 (cenário 4, fato indireto, fatos acumulados) | v1 2/3 · v2 3/3 | — |
| Testes unitários/integração (`mix test`) | 45 testes, 0 falhas | — |

ID alucinado, argumento inválido, loop sem progresso e deadline vencido estão cobertos só por testes com LLM
roteirizado; não dá para forçá-los de forma determinística com o modelo real.

## O que ficou de fora e por quê

- **Streaming token a token do LLM:** priorizei um loop de tools correto. Os feedbacks dão sinal de progresso.
- **Try-on de várias peças:** o proxy não suporta, então o agente veste só a peça principal e mostra as demais
  como cards.
- **`garment_creation` a partir de foto enviada:** o proxy não suporta. A imagem anexada vai para o modelo de
  visão, só para opinar.
- **Avaliação automática da "coerência" do look:** o E2E checa tools, cards, preço e cores, mas não o gosto.
- **Memória v2:** sem deduplicação semântica, sem expiração e sem índice vetorial (poucas linhas por usuário).
- **Observabilidade** (tracing/métricas por turno): por enquanto só logs e `tool_executions`.

## Próximos passos

1. Streaming do texto final, emitindo os deltas da última chamada ao LLM.
2. Juntar extração de memória e resposta numa chamada só, ou pular a extração quando a mensagem não tem
   informação pessoal, para economizar uma chamada por turno.
3. Na v1, trocar `notes` única por lista de fatos, ou ativar a v2 por padrão depois de mais medição.
4. Avaliação com LLM-juiz para a coerência dos looks e mais variações dos cenários.
5. Reranking e uso do guarda-roupa nas recomendações ("combina com sua calça jeans").
6. Telemetria por turno: latência por tool, tokens e custo.

## Como usei IA

> Seção a revisar pelo João com a experiência dele. Abaixo, os fatos registrados no `log.md`.

O código, os testes e os documentos foram escritos com o Claude Code (Claude Opus 5.5), seguindo o plano de
tarefas T01–T10 que eu escrevi. Cada tarefa só foi fechada com teste executado em Docker e evidência real.

- **Onde ajudou:** scaffolding do Phoenix e do Docker, orquestradores e testes com stubs (`Req.Test`), runner
  E2E e relatórios, e investigação de falhas com medição (taxa de JSON inválido por modelo, dimensão real dos
  embeddings).
- **Onde errou ou precisou de correção** (todos no `log.md`):
  - `String.to_existing_atom` no despacho de tools quebrava os testes.
  - O `prod.exs` gerado forçava SSL.
  - A imagem de runtime era incompatível (glibc).
  - As respostas vinham em markdown, que o frontend não renderiza.
  - Na primeira execução do cenário 4, a memória não salvou e a resposta "acertou" por coincidência. Só uma
    checagem do banco revelou isso.
  - Uma asserção do E2E estava errada (f3).
  - Os fatos da v2 supunham gênero ("Ela…").

## Início e fim

- Início: 2026-11-15 20:31:12 -03:00 (início oficial registrado no `log.md`)
- Fim: 2026-11-15 21:25:47 -03:00

## Como rodar

Só é preciso Docker com Compose e Git.

```bash
cp .env.example .env                 # OPENROUTER_API_KEY=...
docker compose up --build            # frontend+proxy (:3000), agente, Postgres
# abra http://localhost:3000
```

| Para… | Comando |
| --- | --- |
| Testes | `docker compose --profile test run --rm agent-test` |
| E2E (6 cenários) | `docker compose --profile test run --rm agent-test mix run --no-start evals/run.exs evals/scenarios.json` |
| E2E de falhas | `docker compose --profile eval up --build -d proxy-faults agent-eval` e depois `… evals/run.exs evals/faults.json` |
| Memória v2 | `MEMORY_MODE=v2 docker compose up --build -d agent` (e `… evals/run.exs evals/memory.json` com `-e MEMORY_MODE=v2`) |

Variáveis opcionais: `AGENT_MODEL`, `FALLBACK_MODEL`, `MEMORY_MODEL`, `EMBEDDING_MODEL`, `LLM_MAX_TOKENS`,
`MEMORY_MODE` (`v1`|`v2`; outro valor impede o boot).
