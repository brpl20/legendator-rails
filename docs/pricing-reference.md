# Referência de Custos — Legendator

Dados coletados em 2026-03-15 via OpenRouter.

## Dados reais medidos

### Episódio de série curta (~5.600 tokens input)

| Modelo                | Input → Output     | Custo API (USD) | Velocidade |
|-----------------------|--------------------|-----------------|------------|
| GPT-4.1 Mini          | 4.735 → 5.706     | $0.011          | 57 tps     |
| Gemini 2.5 Flash      | 6.200 → 7.382     | $0.020          | 247 tps    |
| Claude Haiku 4.5      | 5.596 → 8.090     | $0.046          | 110 tps    |
| Claude Sonnet 4.5     | 5.596 → 8.205     | $0.140          | 63 tps     |

### Filme normal (~45.000 tokens input, GPT-4.1 Mini em ~7 chunks)

| Modelo                | Custo por chunk   | Chunks | Custo total (USD) |
|-----------------------|-------------------|--------|--------------------|
| GPT-4.1 Mini          | ~$0.013           | ~7     | ~$0.095            |

### Estimativa por tipo de conteúdo (extrapolada)

Baseado nos dados reais acima, projeção para arquivo inteiro (sem split):

| Modelo                | Episódio (~5k tok) | Filme normal (~45k tok) | Filme longo (~70k tok) |
|-----------------------|--------------------|-------------------------|------------------------|
| GPT-4.1 Mini          | $0.011             | ~$0.095                 | ~$0.15                 |
| Gemini 2.5 Flash      | $0.020             | ~$0.17                  | ~$0.27                 |
| Claude Haiku 4.5      | $0.046             | ~$0.39                  | ~$0.61                 |
| Claude Sonnet 4.5     | $0.140             | ~$1.19                  | ~$1.86                 |
| GPT-4.1               | ~$0.055            | ~$0.47                  | ~$0.73                 |

> Projeção linear: custo_filme = custo_episodio * (tokens_filme / tokens_episodio)

## Markup aplicado (custo final ao usuário em BRL)

Fórmula do `CostCalculator`:

```
custo_brl = custo_usd * taxa_cambio * 1.10 (markup financeiro) * 3.00 (markup negócio 200%)
minimo = R$ 2.00
```

Com câmbio a R$ 5.50:

| Modelo                | Episódio (BRL) | Filme normal (BRL) | Filme longo (BRL) |
|-----------------------|----------------|--------------------|--------------------|
| GPT-4.1 Mini          | R$ 2.00*       | R$ 2.00*           | R$ 2.73           |
| Gemini 2.5 Flash      | R$ 2.00*       | R$ 3.09            | R$ 4.90           |
| Claude Haiku 4.5      | R$ 2.00*       | R$ 7.09            | R$ 11.08          |
| Claude Sonnet 4.5     | R$ 2.55        | R$ 21.61           | R$ 33.78          |
| GPT-4.1               | R$ 2.00*       | R$ 8.54            | R$ 13.26          |

> *Valores abaixo do mínimo de R$ 2.00 são arredondados para cima.

## Referência de tokens por tipo de conteúdo

| Tipo                  | Tokens input estimados | Exemplo                          |
|-----------------------|------------------------|----------------------------------|
| Episódio série curta  | ~5.000 - 6.000         | Episódio 22min anime/sitcom      |
| Filme normal          | ~40.000 - 50.000       | Filme 1h30 - 2h                  |
| Filme longo           | ~60.000 - 80.000       | Filme 2h30+ / documentário longo |
