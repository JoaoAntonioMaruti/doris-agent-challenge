# Relatório E2E — scenarios

- Alvo: http://proxy:3000 · memória: v1 (padrão do agente) · modelo: openai/gpt-6-luna (padrão do agente)
- Início: 2026-11-16T01:03:28.749192Z · fim: 2026-11-16T01:05:40.288224Z
- Resultado: **6/6 passaram**, 0 falharam · 11 turnos · p50 7556 ms · p95 27846 ms (amostra pequena, não generalizar)

| Cenário | Status | Latência total (ms) | Tools por turno | Cards | Falhas |
| --- | --- | --- | --- | --- | --- |
| s1_camisa_linho | passed | 20758 | search_by_text→show_artifact→garment_creation→tryon→show_artifact | PRODUCT p01 R$249.9, TRYON_CARD cd3aac42 | — |
| s2_casamento_praia | passed | 27090 | search_by_text→search_by_text→search_by_text→show_artifact→show_artifact→garment_creation→tryon→show_artifact | PRODUCT p01 R$249.9, PRODUCT p06 R$279.0, TRYON_CARD dbb4e6d1 | — |
| s3_ultimo_look | passed | 7556 | looks→show_artifact | TRYON_CARD look_car | — |
| s4_memoria | passed | 38872 |  ‖ search_by_text→search_by_text→search_by_text→show_artifact→garment_creation→tryon→show_artifact ‖  ‖  | PRODUCT p05 R$389.0, TRYON_CARD 1ebad1b8 | — |
| s5_jaquetas | passed | 31980 | wardrobe→search_by_text→show_artifact ‖ garment_creation→tryon→show_artifact | PRODUCT p07 R$899.0, TRYON_CARD 2ed65322 | — |
| s6_conversa | passed | 5269 |  ‖  | — | — |

## Turnos

### s1_camisa_linho — Camisa de linho branca até R$300
- `u_ana` / `eval-s1_camisa_linho-a-1794791008` — "Me acha uma camisa de linho branca até R$300" (20758 ms, outcome done)
  - resposta: Encontrei a Camisa de linho branca, do Ateliê Maré, por R$ 249,90 — dentro do seu orçamento. Também gerei uma prova virtual para você ver como fica.

### s2_casamento_praia — Casamento na praia
- `u_bruno` / `eval-s2_casamento_praia-a-1794791008` — "Tenho um casamento na praia sábado, o que eu visto?" (27090 ms, outcome done)
  - resposta: Para um casamento na praia, eu iria de camisa de linho branca com calça de alfaiataria bege: leve, elegante e adequada para a ocasião. Mostrei a Camisa de linho branca por R$ 249,90 e a Calça de alfaiataria bege por R$ 279,00; fiz também um try-on da camisa.

### s3_ultimo_look — Opinião sobre o último look
- `u_carla` / `eval-s3_ultimo_look-a-1794791008` — "O que você acha do meu último look?" (7556 ms, outcome done)
  - resposta: Carla, achei seu vestido lindo e cheio de personalidade! A estampa colorida e a cintura marcada deixam o look ótimo para um brunch; o scarpin preto dá um toque elegante. Para um clima mais descontraído, uma sandália rasteira também combinaria super bem.

### s4_memoria — Preferências entre conversas
- `u_ana__eval1794791008` / `eval-s4_memoria-a-1794791008` — "Odeio amarelo, visto M e curto estilo minimalista." (4572 ms, outcome done)
  - resposta: Combinado, Ana: vou evitar amarelo e priorizar peças minimalistas no tamanho M. Quer montar um look ou buscar alguma peça?
- `u_ana__eval1794791008` / `eval-s4_memoria-b-1794791008` — "Me sugere algo pra um jantar" (27846 ms, outcome done)
  - resposta: Para o jantar, sugiro o vestido midi preto minimalista, de linhas elegantes e fáceis de complementar com acessórios discretos. Ele custa R$ 389, e já mostrei uma prova virtual.
- `u_ana__eval1794791008` / `eval-s4_memoria-c-1794791008` — "Que tamanho eu visto e qual cor eu evito?" (3764 ms, outcome done)
  - resposta: Você veste tamanho M e evita amarelo.
- `u_ana__other1794791008` / `eval-s4_memoria-d-1794791008` — "Que tamanho eu visto e qual cor eu evito?" (2690 ms, outcome done)
  - resposta: Ainda não tenho essa informação, Ana. Se você me disser seu tamanho e as cores que prefere evitar, levo isso em conta nas próximas sugestões.

### s5_jaquetas — Jaqueta jeans e depois couro
- `u_ana` / `eval-s5_jaquetas-a-1794791008` — "Tem jaqueta jeans?" (13403 ms, outcome done)
  - resposta: Não encontrei jaqueta jeans no catálogo nem no seu guarda-roupa. A alternativa mais próxima é a jaqueta de couro preta, por R$ 899,00.
- `u_ana` / `eval-s5_jaquetas-a-1794791008` — "Quero provar a jaqueta de couro preta" (18577 ms, outcome done)
  - resposta: Aqui está a jaqueta de couro preta da Couraça, por R$ 899,00, no seu try-on.

### s6_conversa — Oi e capital da França
- `u_bruno` / `eval-s6_conversa-a-1794791008` — "Oi" (3107 ms, outcome done)
  - resposta: Oi, Bruno! Como posso te ajudar com moda hoje?
- `u_bruno` / `eval-s6_conversa-a-1794791008` — "Qual a capital da França?" (2162 ms, outcome done)
  - resposta: A capital da França é Paris. Também posso ajudar com alguma dúvida de moda!
