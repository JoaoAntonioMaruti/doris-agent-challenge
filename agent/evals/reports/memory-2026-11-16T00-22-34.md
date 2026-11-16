# Relatório E2E — memory

- Alvo: http://proxy:3000 · memória: v2 · modelo: openai/gpt-6-luna (padrão do agente)
- Início: 2026-11-16T00:22:34.782605Z · fim: 2026-11-16T00:23:56.065219Z
- Resultado: **3/3 passaram**, 0 falharam · 9 turnos · p50 4076 ms · p95 27508 ms (amostra pequena, não generalizar)

| Cenário | Status | Latência total (ms) | Tools por turno | Cards | Falhas |
| --- | --- | --- | --- | --- | --- |
| m1_preferencias | passed | 35109 |  ‖ search_by_text→search_by_text→search_by_text→show_artifact→show_artifact→garment_creation→tryon→show_artifact ‖  | PRODUCT p15 R$119.9, PRODUCT p06 R$279.0, TRYON_CARD 80e16d55 | — |
| m2_linguagem_indireta | passed | 7753 |  ‖  | — | — |
| m3_fatos_acumulados | passed | 38412 |  ‖  ‖ search_by_text→search_by_text→search_by_text→show_artifact→show_artifact→garment_creation→tryon→show_artifact ‖  | PRODUCT p23 R$59.9, PRODUCT p22 R$219.0, TRYON_CARD 01bae4de | — |

## Turnos

### m1_preferencias — Cenário 4 (preferências explícitas)
- `u_ana__mem1794788554` / `eval-m1_preferencias-a-1794788554` — "Odeio amarelo, visto M e curto estilo minimalista." (4561 ms, outcome done)
  - resposta: Entendido, Ana: vou evitar amarelo e priorizar peças tamanho M com estilo minimalista. O que você está procurando hoje?
- `u_ana__mem1794788554` / `eval-m1_preferencias-b-1794788554` — "Me sugere algo pra um jantar" (27118 ms, outcome done)
  - resposta: Para um jantar, eu combinaria a blusa branca ombro a ombro (R$ 119,90) com a calça de alfaiataria bege (R$ 279). A blusa já está no try-on; fica um look minimalista e elegante.
- `u_ana__memx1794788554` / `eval-m1_preferencias-c-1794788554` — "Que tamanho eu visto e qual cor eu evito?" (3430 ms, outcome done)
  - resposta: Ainda não tenho seu tamanho nem a cor que você evita. Se me contar, levo isso em conta nas próximas sugestões.

### m2_linguagem_indireta — Fato indireto lembrado em outra conversa
- `u_bruno__mem1794788554` / `eval-m2_linguagem_indireta-a-1794788554` — "Trabalho num escritório de advocacia bem tradicional e moro em Curitiba, que é muito frio." (4076 ms, outcome done)
  - resposta: Entendi, Bruno: para um escritório tradicional em Curitiba, vale apostar em alfaiataria clássica com camadas quentes e discretas. Posso sugerir um look para o trabalho ou buscar uma peça específica.
- `u_bruno__mem1794788554` / `eval-m2_linguagem_indireta-b-1794788554` — "O que você lembra sobre meu trabalho e onde eu moro?" (3677 ms, outcome done)
  - resposta: Lembro que você trabalha em um escritório de advocacia tradicional. Sobre onde mora, tenho uma informação anotada como Curitiba, mas seu perfil também indica Rio de Janeiro — então posso estar com esse dado desatualizado.

### m3_fatos_acumulados — Vários fatos em conversas diferentes (v1 guarda só uma nota)
- `u_bruno__acc1794788554` / `eval-m3_fatos_acumulados-a-1794788554` — "Eu pedalo para o trabalho todo dia." (3423 ms, outcome done)
  - resposta: Boa, Bruno! Posso sugerir roupas confortáveis e práticas para pedalar até o trabalho. Você quer um look para algum clima ou ocasião específica?
- `u_bruno__acc1794788554` / `eval-m3_fatos_acumulados-b-1794788554` — "Ah, e tenho alergia a lã." (4194 ms, outcome done)
  - resposta: Entendido, Bruno! Vou evitar peças de lã nas minhas sugestões.
- `u_bruno__acc1794788554` / `eval-m3_fatos_acumulados-c-1794788554` — "Vou para o trabalho de bicicleta amanhã, que roupa é prática pra isso?" (27508 ms, outcome done)
  - resposta: Para pedalar, eu escolheria a camiseta branca básica (R$ 59,90) com a calça chino cáqui (R$ 219,00): uma combinação leve e confortável, sem lã. Só faltou aparecer uma opção de tênis adequado; prefira um calçado firme e confortável para pedalar.
- `u_bruno__acc1794788554` / `eval-m3_fatos_acumulados-d-1794788554` — "Você lembra como eu vou para o trabalho e de alguma alergia minha?" (3287 ms, outcome done)
  - resposta: Sim! Você vai de bicicleta para o trabalho todos os dias e tem alergia a lã.
