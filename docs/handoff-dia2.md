# Legendator — Handoff Dia 2

Estado em 10/08/2026. Tudo que está em "Feito" foi verificado com as suítes rodando;
tudo em "Pendente" está descrito com arquivo, contrato e critério de aceite.

---

## 0. Bloqueadores — resolver antes de qualquer deploy

### 0.1 O gem local ainda não está publicado

`legendator-rails/Gemfile` aponta para `git: "https://github.com/brpl20/legendator-gem"`.
Todo o refactor está **só no working tree local** de `legendator-gem`. O app só
funciona hoje porque configurei um override:

```bash
bundle config set --local local.legendator /Users/brpl20/code/legendator-repos/legendator-gem
```

Isso vive em `.bundle/config`, que é gitignored — **o servidor não tem**. Sequência obrigatória:

```bash
cd legendator-gem
git add -A && git commit -m "refactor: OpenRouter-only, model fallback cascade"
git push origin master

cd ../legendator-rails
bundle config unset local.legendator     # volta a resolver do GitHub
bundle update legendator
bundle exec rspec                         # tem que continuar 56/56
git add -A && git commit -m "feat: catalogo unico de modelos, gate de tamanho, contexto do usuario"
```

Também adicionei `branch: "master"` na linha do Gemfile — o override local do bundler
exige `branch:` declarado. Mantenha.

### 0.2 Crédito da OpenRouter acabando

A key em `Rails.application.credentials.openrouter.api_key` já consumiu
**US$ 117,10 de US$ 129** — restam ~**US$ 11,90**. Recarregar antes de ligar
os testes diários.

### 0.3 Key da OpenAI está revogada

`legendator/.env` tem uma `OPENAI_API_KEY` que retorna **HTTP 401**. Depois do
refactor OpenRouter-only ela não é mais usada por nada. Pode apagar a variável.

---

## 1. Feito no Dia 1

### 1.1 Diagnóstico da "lentidão" (não era loop)

`movie-big-example.srt` = 3.072 legendas, 38.700 tokens de payload.

A janela de contexto maior **não resolve**. O limite que importa é o de **saída**,
que é muito menor que o de entrada:

| modelo | ctx entrada | max saída |
|---|---|---|
| gpt-4.1-mini (o que rodou) | 1.047.576 | **32.768** |
| gpt-5.6-luna | 1.050.000 | **128.000** |

O arquivo precisa de ~38.700 tokens de saída — **não cabe** em uma chamada do
gpt-4.1-mini, daí os 7 chunks sequenciais. E gerar 38.700 tokens leva o mesmo
tempo em 1 ou em 7 pedaços: geração é linear. **O que corta o tempo é paralelizar
os chunks** (item 2.1), não aumentá-los.

### 1.2 Gem: só OpenRouter

Removido o provider OpenAI inteiro. `provider` deixou de existir como conceito;
a cascata de fallback agora é lista de **modelos**.

| antes | agora |
|---|---|
| `config.provider = :openrouter` | (removido) |
| `config.openai_api_key` / `config.openrouter_api_key` | `config.api_key` |
| `config.fallback_providers = [{provider:, model:, api_key:}]` | `config.fallback_models = ["slug", ...]` |
| `AiClient.new(provider:, model:, api_key:)` | `AiClient.new(model:, api_key:)` |
| `Pipeline::Result#provider` | (removido) |
| `--provider=` no CLI | (removido) |

Isso **eliminou** o bug de vazamento de key: `api_key_for` devolvia a key genérica
para qualquer provider, então o fallback `provider: :openai` recebia `sk-or-...` e
tomava 401 sempre. Esse fallback nunca funcionou.

Também corrigido: o custo vinha `nil` porque o código lia `usage["total_cost"]`.
A OpenRouter devolve `usage.cost` quando se pede `usage: {include: true}` — agora
o request pede e o parser aceita as duas chaves. **Verificado ao vivo**: cost voltou
`$0.000388` num teste real.

`bundle exec rake test` → **107 testes, 0 falhas**.

### 1.3 Rails: catálogo único de modelos

Novo `app/models/ai_model.rb` é a única fonte de verdade (slug, label, preço,
teto de saída). Substituiu `Translation::AVAILABLE_MODELS` e a tabela
`CostCalculator::MODEL_PRICING`, que estavam divergentes entre si.

Catálogo antigo (5 modelos) tinha dois defeitos:
- `deepseek-ai/deepseek-chat` **não existe** na OpenRouter (slug certo é `deepseek/...`).
  Estava no menu do cliente *e* na cascata de fallback.
- `qwen/qwen3.5-9b` com preço de entrada errado (0,05 no código vs 0,10 real).

Catálogo novo:

| slug | label | in $/M | out $/M | max saída |
|---|---|---|---|---|
| `openai/gpt-5.6-luna` | Padrao (recomendado) | 0,10 | 0,60 | 128.000 |
| `deepseek/deepseek-v4-flash-0731` | Economico (mais lento) | 0,08 | 0,18 | 384.000 |

**`openai/gpt-5-nano` foi testado e rejeitado.** Medição real com 25 legendas:

| modelo | latência | tokens de saída | extrapolado p/ filme |
|---|---|---|---|
| gpt-5.6-luna | 5s | 571 | R$ 0,25 |
| deepseek-v4-flash-0731 | 124s | 1.145 | R$ 0,15 |
| gpt-5-nano | 44s | **7.118** | **R$ 1,90** |

O nano é modelo de raciocínio: queima tokens invisíveis. Apesar do menor preço por
token, sai **7,4× mais caro** que o Luna e ainda **estoura o próprio teto de 128k**
num filme inteiro. Preço por token não é custo.

### 1.4 Custo real medido de um arquivo completo

Rodada real de `movie-big-example.srt` (1 arquivo, 3.072 blocos, 7 chunks) com
`openai/gpt-5.6-luna`, config de produção, em 10/08/2026:

| | |
|---|---|
| tempo | 281s (4,7 min) |
| tokens entrada / saída | 39.904 / 43.679 |
| cobertura | 3.072/3.072 (100%) |
| consistência | passou |
| **custo real** | **US$ 0,031186 = R$ 0,17** |

Cobrando R$ 1,00: **margem de R$ 0,83, markup de 5,9×** no pior arquivo realista.
Decisão do dono: **manter R$ 1,00 fixo** — a folga cobre qualquer modelo do catálogo.

Nota: `CostCalculator#estimate` assume saída do mesmo tamanho da entrada (1,0×);
o real foi 1,325×. O estimador é otimista em ~33%. Como o piso de R$ 1,00 domina,
não afeta a cobrança hoje — mas se um dia o preço passar a ser calculado de fato,
alinhar com a constante `OUTPUT_RATIO` do `SrtSizeGate`.

### 1.5 Gate de custo (o furo econômico)

Novo `app/services/srt_size_gate.rb`. O problema que ele fecha: o limite de 5MB
sozinho permite ~69.000 blocos. No modelo padrão antigo isso era **R$ 9,39 de
custo de IA contra R$ 1,00 cobrado**.

O gate é expresso em **BRL, não em tokens** — `MAX_AI_COST_BRL = 0.70`. Precifica
o arquivo pelo mesmo catálogo `AiModel` que o job vai usar para cobrar, então
acompanha sozinho qualquer troca de modelo. Constantes calibradas contra a rodada
real do 1.4 (overhead 1.050/chunk, saída 1,40× o payload), arredondadas para cima:
o gate estima R$ 0,171 onde o real foi R$ 0,168, **+1,3% de folga**.

Três camadas:

1. **Numeração repetida** — `extract_texts` indexa por ID, então blocos com IDs
   repetidos se sobrescrevem. Dez cópias de um filme viram 30.720 blocos que
   colapsam em 3.072: passaria no gate, seria traduzido pela metade e o cliente
   pagaria integral por um décimo. Agora compara `parse.size` com
   `extract_texts.size` e recusa a diferença.
2. **`MAX_SUBTITLES = 12_000`** — guarda barata antes de tokenizar algo absurdo.
3. **`MAX_AI_COST_BRL = 0.70`** — o teto de negócio.

Onde corta (verificado com merges reais das fixtures, 10/08/2026):

| arquivo | blocos | custo IA | resultado |
|---|---|---|---|
| filme típico | 3.072 | R$ 0,24 | aceita |
| 2 filmes renumerados | 6.144 | R$ 0,34 | aceita |
| 3 filmes renumerados | 9.216 | R$ 0,51 | aceita |
| 10 filmes renumerados (2,25MB) | 30.720 | — | **recusa** (MAX_SUBTITLES) |
| 10 cópias concatenadas (2,22MB) | 30.720 → 3.072 | — | **recusa** (numeração repetida) |

**Preço**: mantido R$ 1,00 fixo por decisão do dono. O controller usa
`CostCalculator#estimate`, mas o piso `minimum_brl: 1.00` de `config/pricing.yml`
domina em praticamente todo arquivo — na prática é ele quem define o preço, não o
markup de 200% + 10%.

### 1.6 Contexto do usuário (nomes de personagens)

A feature existia pela metade: o gem sempre aceitou `context:` e o injeta no system
prompt (`ai_client.rb`), mas o job **nunca passava**. Agora:

- migration `add_context_to_translations`
- `Translation::MAX_CONTEXT_LENGTH = 1_000` com validação
- textarea em `translations/new.html.erb` com placeholder de exemplo
- `TranslateSubtitleJob` passa `context: translation.context.presence`

**Verificado ao vivo** com `context: "Traduzir 'Cheese' como 'Queijo'"` — 25/25 legendas.

### 1.7 Tradução não fica mais presa em "processing"

`retry_on ... attempts: 3` **sem bloco** re-levanta o erro na última tentativa: o job
morre e o registro fica em `processing` para sempre. E `show.html.erb` faz
`<meta http-equiv="refresh" content="5">` enquanto está em `processing` — ou seja,
a página gira eternamente. Agora ambos os `retry_on` têm bloco que chama
`mark_failed`, levando o registro a `failed`.

### 1.8 Outros defeitos corrigidos

- Default da coluna `model_used` era `"gpt-4.1-mini"` — **sem o prefixo `openai/`**,
  slug que a OpenRouter rejeitaria. A factory dos specs usava o mesmo valor, ou seja,
  os testes passavam com um valor impossível em produção. Migration corrige o default.
- `validates :model_used, inclusion:` só `on: :create`, senão registros antigos com
  slug aposentado ficariam impossíveis de atualizar (o job escreve status neles).
- Initializer envolvido em `to_prepare` — referenciar `AiModel` direto quebra no Zeitwerk.

**Verificação**: `bundle exec rspec` → **56 exemplos, 0 falhas** (eram 38).

---

## 2. Pendente — backlog do Dia 2

### 2.1 [ALTA] Paralelizar os chunks — o fix real da lentidão

**Arquivo**: `legendator-gem/lib/legendator/pipeline.rb`, método `run`, linha do `chunks.each_with_index`.

Hoje é estritamente sequencial, com `sleep(0.5)` entre chunks. Para o `movie-big`
com Luna: ~70k tokens de saída a ~114 tok/s ≈ **10 minutos**.

Proposta: pool de threads com concorrência limitada (4–6), preservando ordem no merge.

```ruby
POOL_SIZE = 5

results = chunks.each_slice(POOL_SIZE).flat_map do |batch|
  batch.map { |chunk| Thread.new { translate_chunk_with_fallback(...) } }.map(&:value)
end
```

Cuidados:
- `all_translations.merge!` e os acumuladores de token **não são thread-safe** —
  merge só depois do `.map(&:value)`, fora das threads.
- A OpenRouter não publica limite fixo de RPS nessa key (`rate_limit.requests: -1`,
  campo deprecado). Comece com 4 e observe 429 — o retry com backoff já existe.
- O `sleep(0.5)` entre chunks perde o sentido; remover.

**Aceite**: `movie-big-example.srt` de ponta a ponta em < 3 min, cobertura 100%,
mesma ordem de IDs no SRT final.

### 2.2 [ALTA] Escolher um fallback rápido

`deepseek/deepseek-v4-flash-0731` levou **124s para 25 legendas** (~9 tok/s).
Extrapolado, um filme levaria horas — é um fallback que na prática trava o job.

Medir latência de candidatos e trocar. `google/gemini-3.1-flash-lite`
($0,25/$1,50, 65k saída) foi descartado como padrão por custo, mas como fallback
(raro) o custo não importa — importa velocidade. **Medir antes de decidir.**

Script de medição pronto para adaptar: veja o padrão em `docs/` ou refaça com
`Legendator::AiClient.new(model:).translate(...)` cronometrado.

### 2.3 [ALTA] Testes automatizados diários + semanais

Decidido: fixture pequena todo dia, arquivo grande toda semana.

**Diário** (`serie-example.srt`, 464 legendas, ~US$ 0,003/dia ≈ US$ 1/ano):
- roda tradução real ponta a ponta contra o modelo padrão
- valida: cobertura 100%, consistência passa, custo volta não-nil, latência
- valida também sem custo: saldo da key (`GET /api/v1/key`) e existência de cada
  slug do catálogo (`GET /api/v1/models`) — **os 3 bugs que os 107 testes offline
  não pegaram eram todos desse tipo**

**Semanal** (`movie-big-example.srt`): vigia tempo de ponta a ponta e regressão de custo.

Onde: `lib/tasks/legendator_healthcheck.rake` + cron/solid_queue recurring.
Reportar via webhook (item 2.4).

### 2.4 [MÉDIA] Métricas diárias para o dashboard

O ai-dashboard já tem os dois endpoints prontos e vivos. **Confirmado:
`POST https://ffd.belzinhos.com.br/api/webhooks/token-usage` responde 401 sem
segredo** — o contrato funciona, só falta a credencial.

Auth (qualquer um dos três): `?token=<WEBHOOK_SECRET>`, header `x-webhook-token`,
ou header `x-webhook-secret`. O valor vive na NAS em
`/volume1/docker/ai-dashboard/.env`.

**(a) Uso diário** → `POST /api/webhooks/usage`

Replica o padrão do `prc_signer_a1`
(`src/main/java/.../usage/UsageReportJob.java`): cron diário, envia o dia anterior,
**envia mesmo com zero eventos** (serve de heartbeat), 3 tentativas com backoff
exponencial.

```json
{
  "service": "legendator",
  "date": "2026-08-09",
  "events": 12,
  "unique_users": 8,
  "top_repeats": [{ "user": "<hash>", "count": 3 }]
}
```

O dashboard renderiza como `"Uso diário: legendator — 12 eventos"` no feed de alertas.
`events` = traduções concluídas no dia. Para `unique_users`, o Legendator não tem
login — usar SHA-256(IP + salt), exatamente como o `UsageTracker` do signer faz
(ele nunca guarda IP em claro).

**(b) Custo por chamada** → `POST /api/webhooks/token-usage`

Idempotente por `request_id` (`ON CONFLICT DO NOTHING`), então retry é seguro.
Campo é `cost_raw_brl` — **BRL sem markup**, nunca `cost_usd`; o dashboard não
converte moeda. Emitir um evento por tradução, a partir do `Pipeline::Result`:

```json
{
  "request_id": "<access_token da translation>",
  "environment": "production",
  "feature": "subtitle_translation",
  "company": "openrouter",
  "model": "openai/gpt-5.6-luna",
  "tokens_in": 38900,
  "tokens_out": 70164,
  "cost_raw_brl": 0.25,
  "status": "success",
  "latency_ms": 182000
}
```

### 2.5 [MÉDIA] Health endpoint

O dashboard **não aceita POST de health** — ele faz *pull*: `GET /api/servers/[id]/health`
busca em `server.agentUrl + "/health"` com header `X-Api-Key`, e espera o shape do
`health-agent` (`overall_status`, `system.cpu_percent`, `system.memory.percent`, ...).

Dois caminhos:
- **(a) rápido**: reportar como `POST /api/webhooks/bot` — feito para relatório de
  execução de rotina, cai no feed de alertas. Shape:
  `{bot_name, runtime, runstatus, message, pr?}`. Encaixa bem com o resultado do
  teste diário do 2.3.
- **(b) correto**: expor `/health` no Rails e registrar o Legendator como server no
  dashboard com `agentUrl`. Mais trabalho, integra com o histórico e os alertas.

Recomendo **(a) agora, (b) depois**.

### 2.6 [BAIXA] Página não desiste nunca se o worker estiver parado

`show.html.erb` faz meta-refresh de 5s enquanto `pending_payment || paid || processing`.
O 1.6 resolveu o caso "job falhou". Falta o caso "worker nem rodou": o registro fica
em `paid` para sempre e a página gira igual.

Sugestão: se `updated_at` passou de N minutos em `paid`/`processing`, parar o refresh
e mostrar "estamos demorando mais que o normal, seu código é LEG-XXXX".

### 2.7 [BAIXA] Limpeza

- Repo `legendator/` está morto: working tree com tudo deletado sem commit desde
  14/mar, sobrou `.env` (key revogada) e a spec de 33KB. Arquivar ou apagar.
- `legendator-gem/README.md` foi atualizado para OpenRouter-only, mas a
  "Production Checklist" no fim ainda lista pendências antigas — revisar.
- `config/pricing.yml`: `minimum_brl: 1.00` com markup de 200% + 10%. Com o Luna a
  R$ 0,25 de custo num filme, o piso de R$ 1,00 é quem manda em quase todo arquivo.
  Vale revisar se o piso ainda faz sentido comercialmente.

---

## 3. Fase 3 — vídeo → transcrição → legenda

Ideia: o usuário sobe um **vídeo**, a plataforma transcreve (Whisper ou equivalente)
gerando legenda marcada no tempo, e daí em diante cai no pipeline que já existe.
Produto muito mais forte: legenda qualquer coisa, não só quem já tem `.srt`.

Complexidade real, em ordem:

1. **Upload de vídeo** — outra ordem de grandeza. Hoje o limite é 5MB de `.srt`;
   um filme são GBs. Implica upload direto para o storage (presigned URL), não
   passando pelo app, e um limite de duração, não de bytes.
2. **Extração de áudio** — `ffmpeg` para mp3/opus mono 16kHz. Corta o tamanho em
   ~100× e é o formato que os modelos de transcrição querem. Precisa de `ffmpeg`
   no container e de um job separado, porque é CPU-bound e demorado.
3. **Transcrição marcada** — precisa de timestamps por segmento, não texto corrido.
   O `whisper-1` da OpenAI aceita `response_format: "srt"` ou `"verbose_json"` com
   segmentos, o que já sai quase pronto. **A OpenRouter não serve aqui** — ela é
   só chat/completions, não tem endpoint de áudio. Isso significa **reintroduzir
   um segundo provider**, exatamente o que acabamos de remover. Vale planejar a
   fronteira: `Legendator` continua OpenRouter-only para tradução, e a transcrição
   vira um serviço separado com sua própria key.
4. **Tradução** — a partir daqui é o pipeline atual, sem mudança.

**Precificação**: é o ponto crítico. A transcrição custa por **minuto de áudio**,
não por token — o `whisper-1` cobra por volta de US$ 0,006/min, ou seja ~US$ 0,72
por um filme de 2h (~R$ 3,90), **sozinho, sem contar a tradução**. Isso é 23× o
custo de uma tradução de `.srt`. O R$ 1,00 fixo **não sobrevive** a esta fase:
- gate por **duração do vídeo**, não por tamanho de arquivo
- faixa de preço separada da tradução de `.srt`
- confirmar o preço/min do modelo escolhido antes de fechar a conta

**Ordem sugerida**: fatiar em (a) upload + extração de áudio + transcrição gerando
um `.srt` para download, e só depois (b) encadear com a tradução. A fase (a) já é
um produto vendável sozinho.

---

## 4. Como rodar as verificações

```bash
# gem — 107 testes, todos offline
cd legendator-gem && bundle exec rake test

# rails — 56 exemplos
cd legendator-rails && bundle exec rspec

# CLI, sem custo
cd legendator-gem && bundle exec ruby bin/legendator dry-run test/fixtures/serie-example.srt

# saldo e validade da key, sem custo
curl -s https://openrouter.ai/api/v1/key -H "Authorization: Bearer $OPENROUTER_API_KEY"
```
