# Relatório E2E — scenarios

- Alvo: http://proxy:3000 · memória: v1 (padrão do agente) · modelo: openai/gpt-6-luna (padrão do agente)
- Início: 2026-11-16T00:05:50.689355Z · fim: 2026-11-16T00:08:06.207116Z
- Resultado: **6/6 passaram**, 0 falharam · 11 turnos · p50 5835 ms · p95 32047 ms (amostra pequena, não generalizar)

| Cenário | Status | Latência total (ms) | Tools por turno | Cards | Falhas |
| --- | --- | --- | --- | --- | --- |
| s1_camisa_linho | passed | 25389 | search_by_text→show_artifact→garment_creation→tryon→show_artifact | PRODUCT p01 R$249.9, TRYON_CARD cd3aac42 | — |
| s2_casamento_praia | passed | 32047 | search_by_text→search_by_text→search_by_text→search_by_text→show_artifact→show_artifact→garment_creation→tryon→show_artifact | PRODUCT p01 R$249.9, PRODUCT p06 R$279.0, TRYON_CARD dbb4e6d1 | — |
| s3_ultimo_look | passed | 5835 | looks→show_artifact | TRYON_CARD look_car | — |
| s4_memoria | passed | 38738 |  ‖ search_by_text→search_by_text→show_artifact→garment_creation→tryon→show_artifact ‖  ‖  | PRODUCT p05 R$389.0, TRYON_CARD 5cbbcd6c | — |
| s5_jaquetas | passed | 30136 | search_by_text→show_artifact ‖ garment_creation→tryon→show_artifact | PRODUCT p07 R$899.0, TRYON_CARD 2ed65322 | — |
| s6_conversa | passed | 3357 |  ‖  | — | — |

## Turnos

### s1_camisa_linho — Camisa de linho branca até R$300
- `u_ana` / `eval-s1_camisa_linho-a-1794787550` — "Me acha uma camisa de linho branca até R$300" (25389 ms, outcome done)
  - resposta: Encontrei a Camisa de linho branca, do Ateliê Maré, por R$ 249,90 — dentro do seu orçamento. Também gerei uma prova virtual para você ver como fica.

### s2_casamento_praia — Casamento na praia
- `u_bruno` / `eval-s2_casamento_praia-a-1794787550` — "Tenho um casamento na praia sábado, o que eu visto?" (32047 ms, outcome done)
  - resposta: Para o casamento na praia, eu usaria a Camisa de linho branca (R$ 249,90) com a Calça de alfaiataria bege (R$ 279). Não encontrei um sapato adequado no catálogo; o try-on da camisa já está pronto.

### s3_ultimo_look — Opinião sobre o último look
- `u_carla` / `eval-s3_ultimo_look-a-1794787550` — "O que você acha do meu último look?" (5835 ms, outcome done)
  - resposta: Carla, adorei! O vestido tem uma estampa vibrante e cheia de personalidade, e o cinto marca bem a silhueta. Os scarpins pretos deixam o look elegante — uma ótima escolha para um brunch.

### s4_memoria — Preferências entre conversas
- `u_ana__eval1794787550` / `eval-s4_memoria-a-1794787550` — "Odeio amarelo, visto M e curto estilo minimalista." (3290 ms, outcome done)
  - resposta: Combinado, Ana! Vou evitar amarelo e priorizar peças minimalistas no tamanho M. O que você gostaria de encontrar ou montar?
- `u_ana__eval1794787550` / `eval-s4_memoria-b-1794787550` — "Me sugere algo pra um jantar" (31074 ms, outcome done)
  - resposta: Para o jantar, sugiro o Vestido midi preto minimalista, da Linha Reta, por R$ 389. O corte clean deixa o look elegante sem esforço — já mostrei como fica em você.
- `u_ana__eval1794787550` / `eval-s4_memoria-c-1794787550` — "Que tamanho eu visto e qual cor eu evito?" (1800 ms, outcome done)
  - resposta: Você veste tamanho M e evita a cor amarelo. Quer ajuda para escolher uma peça?
- `u_ana__other1794787550` / `eval-s4_memoria-d-1794787550` — "Que tamanho eu visto e qual cor eu evito?" (2574 ms, outcome done)
  - resposta: Ainda não tenho essa informação, Ana. Se você me disser seu tamanho habitual e as cores que prefere evitar, levo isso em conta nas próximas sugestões.

### s5_jaquetas — Jaqueta jeans e depois couro
- `u_ana` / `eval-s5_jaquetas-a-1794787550` — "Tem jaqueta jeans?" (9823 ms, outcome done)
  - resposta: Não encontrei jaqueta jeans no catálogo. A alternativa mais próxima é a jaqueta de couro preta, por R$ 899.00.
- `u_ana` / `eval-s5_jaquetas-a-1794787550` — "Quero provar a jaqueta de couro preta" (20313 ms, outcome done)
  - resposta: Aqui está a jaqueta de couro preta da Couraça no seu try-on. Ela custa R$ 899,00.

### s6_conversa — Oi e capital da França
- `u_bruno` / `eval-s6_conversa-a-1794787550` — "Oi" (1861 ms, outcome done)
  - resposta: Oi, Bruno! Como posso te ajudar com moda hoje?
- `u_bruno` / `eval-s6_conversa-a-1794787550` — "Qual a capital da França?" (1496 ms, outcome done)
  - resposta: A capital da França é Paris. Posso ajudar com alguma dúvida de moda também!
