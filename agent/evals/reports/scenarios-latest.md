# Relatório E2E — scenarios

- Alvo: http://proxy:3000 · memória: v1 (padrão do agente) · modelo: openai/gpt-6-luna (padrão do agente)
- Início: 2026-11-16T01:26:34.649647Z · fim: 2026-11-16T01:28:40.184337Z
- Resultado: **6/6 passaram**, 0 falharam · 11 turnos · p50 7282 ms · p95 27399 ms (amostra pequena, não generalizar)

| Cenário | Status | Latência total (ms) | Tools por turno | Cards | Falhas |
| --- | --- | --- | --- | --- | --- |
| s1_camisa_linho | passed | 20302 | search_by_text→show_artifact→garment_creation→tryon→show_artifact | PRODUCT p01 R$249.9, TRYON_CARD cd3aac42 | — |
| s2_casamento_praia | passed | 27399 | search_by_text→search_by_text→search_by_text→search_by_text→show_artifact→show_artifact→show_artifact→garment_creation→tryon→show_artifact | PRODUCT p01 R$249.9, PRODUCT p06 R$279.0, PRODUCT p10 R$520.0, TRYON_CARD dbb4e6d1 | — |
| s3_ultimo_look | passed | 7282 | looks→show_artifact | TRYON_CARD look_car | — |
| s4_memoria | passed | 37854 |  ‖ search_by_text→search_by_text→search_by_text→show_artifact→garment_creation→tryon→show_artifact ‖  ‖  | PRODUCT p05 R$389.0, TRYON_CARD d4c1b688 | — |
| s5_jaquetas | passed | 26866 | search_by_text→show_artifact ‖ garment_creation→tryon→show_artifact | PRODUCT p07 R$899.0, TRYON_CARD 2ed65322 | — |
| s6_conversa | passed | 5815 |  ‖  | — | — |

## Turnos

### s1_camisa_linho — Camisa de linho branca até R$300
- `u_ana` / `eval-s1_camisa_linho-a-1794792394` — "Me acha uma camisa de linho branca até R$300" (20302 ms, outcome done)
  - resposta: Encontrei a Camisa de linho branca, do Ateliê Maré, por R$ 249,90 — dentro do seu orçamento. Também gerei um try-on para você ver como fica.

### s2_casamento_praia — Casamento na praia
- `u_bruno` / `eval-s2_casamento_praia-a-1794792394` — "Tenho um casamento na praia sábado, o que eu visto?" (27399 ms, outcome done)
  - resposta: Eu iria de camisa de linho branca com calça de alfaiataria bege, uma combinação leve e elegante para casamento na praia. Se quiser um toque mais arrumado, acrescente o blazer de linho off-white; a camisa custa R$ 249,90, a calça R$ 279 e o blazer R$ 520. Fiz um try-on da camisa para você conferir.

### s3_ultimo_look — Opinião sobre o último look
- `u_carla` / `eval-s3_ultimo_look-a-1794792394` — "O que você acha do meu último look?" (7282 ms, outcome done)
  - resposta: Carla, seu último look está cheio de personalidade! O vestido estampado e o cinto marcam bem a silhueta; os scarpins pretos deixam o visual mais elegante. Para um brunch, ficou alegre e arrumado na medida.

### s4_memoria — Preferências entre conversas
- `u_ana__eval1794792394` / `eval-s4_memoria-a-1794792394` — "Odeio amarelo, visto M e curto estilo minimalista." (5035 ms, outcome done)
  - resposta: Anotado, Ana: vou evitar amarelo, considerar tamanho M e priorizar peças minimalistas. Quer buscar uma peça ou montar um look?
- `u_ana__eval1794792394` / `eval-s4_memoria-b-1794792394` — "Me sugere algo pra um jantar" (26793 ms, outcome done)
  - resposta: Para o jantar, sugiro o vestido midi preto minimalista, de linhas elegantes e fáceis de combinar. Ele custa R$ 389,00 e já deixei uma prova virtual para você conferir.
- `u_ana__eval1794792394` / `eval-s4_memoria-c-1794792394` — "Que tamanho eu visto e qual cor eu evito?" (3417 ms, outcome done)
  - resposta: Você veste tamanho M e evita amarelo.
- `u_ana__other1794792394` / `eval-s4_memoria-d-1794792394` — "Que tamanho eu visto e qual cor eu evito?" (2609 ms, outcome done)
  - resposta: Ainda não tenho essa informação, Ana. Não sei seu tamanho nem qual cor você evita; se me contar, posso levar isso em conta nas próximas sugestões.

### s5_jaquetas — Jaqueta jeans e depois couro
- `u_ana` / `eval-s5_jaquetas-a-1794792394` — "Tem jaqueta jeans?" (9296 ms, outcome done)
  - resposta: Não encontrei jaqueta jeans no catálogo. A opção mais próxima é a Jaqueta de couro preta, por R$ 899.00.
- `u_ana` / `eval-s5_jaquetas-a-1794792394` — "Quero provar a jaqueta de couro preta" (17570 ms, outcome done)
  - resposta: Pronto, Ana! Aqui está o try-on da Jaqueta de couro preta, por R$ 899,00.

### s6_conversa — Oi e capital da França
- `u_bruno` / `eval-s6_conversa-a-1794792394` — "Oi" (3022 ms, outcome done)
  - resposta: Oi, Bruno! Como posso te ajudar com moda hoje?
- `u_bruno` / `eval-s6_conversa-a-1794792394` — "Qual a capital da França?" (2793 ms, outcome done)
  - resposta: A capital da França é Paris. Posso também te ajudar com alguma dúvida de moda!
