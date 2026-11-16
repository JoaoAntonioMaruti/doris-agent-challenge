# Relatório E2E — memory

- Alvo: http://proxy:3000 · memória: v1 · modelo: openai/gpt-6-luna (padrão do agente)
- Início: 2026-11-16T00:20:58.424144Z · fim: 2026-11-16T00:22:20.782852Z
- Resultado: **2/3 passaram**, 1 falharam · 9 turnos · p50 3382 ms · p95 34033 ms (amostra pequena, não generalizar)

| Cenário | Status | Latência total (ms) | Tools por turno | Cards | Falhas |
| --- | --- | --- | --- | --- | --- |
| m1_preferencias | passed | 30455 |  ‖ search_by_text→search_by_text→search_by_text→show_artifact→garment_creation→tryon→show_artifact ‖  | PRODUCT p05 R$389.0, TRYON_CARD 008b4424 | — |
| m2_linguagem_indireta | passed | 8646 |  ‖  | — | — |
| m3_fatos_acumulados | failed | 43247 |  ‖  ‖ search_by_text→search_by_text→search_by_text→search_by_text→show_artifact→show_artifact→garment_creation→tryon→show_artifact ‖  | PRODUCT p23 R$59.9, PRODUCT p22 R$219.0, TRYON_CARD 9af018e3 | turno 4: texto não casa /bicicleta/pedal/ |

## Turnos

### m1_preferencias — Cenário 4 (preferências explícitas)
- `u_ana__mem1794788458` / `eval-m1_preferencias-a-1794788458` — "Odeio amarelo, visto M e curto estilo minimalista." (3505 ms, outcome done)
  - resposta: Combinado, Ana: vou evitar amarelo, considerar tamanho M e priorizar peças minimalistas. O que você está procurando?
- `u_ana__mem1794788458` / `eval-m1_preferencias-b-1794788458` — "Me sugere algo pra um jantar" (23650 ms, outcome done)
  - resposta: Ana, o vestido midi preto minimalista (R$ 389) é uma escolha elegante e versátil para o jantar. Já mostrei a peça e o try-on para você conferir.
- `u_ana__memx1794788458` / `eval-m1_preferencias-c-1794788458` — "Que tamanho eu visto e qual cor eu evito?" (3300 ms, outcome done)
  - resposta: Ainda não tenho essa informação, Ana. Me diga seu tamanho habitual e quais cores prefere evitar, que levo isso em conta nas próximas sugestões.

### m2_linguagem_indireta — Fato indireto lembrado em outra conversa
- `u_bruno__mem1794788458` / `eval-m2_linguagem_indireta-a-1794788458` — "Trabalho num escritório de advocacia bem tradicional e moro em Curitiba, que é muito frio." (5264 ms, outcome done)
  - resposta: Entendi, Bruno: vou considerar um estilo mais clássico e profissional, com peças quentes para o frio de Curitiba. Quer montar um look para o escritório ou buscar alguma peça específica?
- `u_bruno__mem1794788458` / `eval-m2_linguagem_indireta-b-1794788458` — "O que você lembra sobre meu trabalho e onde eu moro?" (3382 ms, outcome done)
  - resposta: Lembro que você trabalha em um escritório de advocacia tradicional. Sobre onde mora, tenho informações diferentes: minhas notas dizem Curitiba, mas seu perfil indica Rio de Janeiro.

### m3_fatos_acumulados — Vários fatos em conversas diferentes (v1 guarda só uma nota)
- `u_bruno__acc1794788458` / `eval-m3_fatos_acumulados-a-1794788458` — "Eu pedalo para o trabalho todo dia." (3104 ms, outcome done)
  - resposta: Boa, Bruno! Posso sugerir roupas confortáveis e práticas para pedalar até o trabalho. Você busca um look para o trajeto ou peças específicas?
- `u_bruno__acc1794788458` / `eval-m3_fatos_acumulados-b-1794788458` — "Ah, e tenho alergia a lã." (2975 ms, outcome done)
  - resposta: Entendido, Bruno! Vou evitar peças de lã nas próximas recomendações.
- `u_bruno__acc1794788458` / `eval-m3_fatos_acumulados-c-1794788458` — "Vou para o trabalho de bicicleta amanhã, que roupa é prática pra isso?" (34033 ms, outcome done)
  - resposta: Para pedalar até o trabalho, eu iria de camiseta leve e calça flexível, sem peças soltas que possam prender na bicicleta. Mostrei a Camiseta branca básica por R$ 59,90 e a Calça chino cáqui por R$ 219,00; não encontrei um tênis adequado na busca. Use um tênis fechado que você já tenha e leve uma camisa para trocar, se quiser chegar mais arrumado.
- `u_bruno__acc1794788458` / `eval-m3_fatos_acumulados-d-1794788458` — "Você lembra como eu vou para o trabalho e de alguma alergia minha?" (3135 ms, outcome done)
  - resposta: Lembro que você tem alergia a lã. Não tenho anotado como você vai para o trabalho.
