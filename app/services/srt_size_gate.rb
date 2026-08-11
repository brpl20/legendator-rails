# Measures an SRT before we agree to translate it, and refuses files whose AI
# cost would eat the margin on the R$ 1,00 we charge per file.
#
# The gate is expressed in BRL, not in tokens, because BRL is the actual business
# rule: one .srt file costs the customer R$ 1,00, and we want at most
# MAX_AI_COST_BRL of that going to the AI provider. A token ceiling would have to
# be re-derived by hand every time a model price changes; a cost ceiling adapts
# on its own, since it prices the file through the same AiModel catalog the job
# will actually bill against.
#
# Why this exists: the controller used to charge a flat R$ 1,00 regardless of
# size, and the 5MB upload limit alone allows roughly 69.000 subtitle blocks.
# On the old default model that was R$ 9,39 of AI cost against R$ 1,00 charged.
class SrtSizeGate
  # Ceiling for the raw AI cost of a single file, in BRL.
  MAX_AI_COST_BRL = 0.70

  # Secondary guard: a file this large is not a movie, it is an attack or a
  # mistake. Keeps us from tokenizing something absurd just to price it.
  MAX_SUBTITLES = 12_000

  Measurement = Struct.new(
    :subtitles, :input_tokens, :output_tokens, :ai_cost_brl, :ok, :reason,
    keyword_init: true
  ) do
    alias_method :ok?, :ok
  end

  def initialize(content, model: AiModel::DEFAULT_SLUG, usd_brl: nil)
    @content = content
    @spec = AiModel.find(model)
    @usd_brl = usd_brl
  end

  def measure
    parser = Legendator::SrtParser.new(@content)
    blocks = parser.parse
    texts  = parser.extract_texts

    return failure("nao contem legendas validas") if texts.empty?

    # extract_texts keys by subtitle ID, so repeated IDs silently overwrite each
    # other. Concatenating ten copies of a movie yields 30.720 blocks that
    # collapse into 3.072 — the file would be accepted, translated in part, and
    # the customer would pay in full for a tenth of their subtitles. Refuse
    # instead of truncating without telling anyone.
    if blocks.size > texts.size
      return failure(
        "tem #{blocks.size - texts.size} legendas com numeracao repetida — " \
        "parece varios arquivos juntos. Renumere ou envie separadamente",
        subtitles: texts.size
      )
    end

    if texts.size > MAX_SUBTITLES
      return failure("tem #{texts.size} legendas (maximo #{MAX_SUBTITLES})",
                     subtitles: texts.size)
    end

    payload = texts.map { |id, text| "#{id}|#{text}" }.join("\n")
    payload_tokens = token_counter.count(payload)

    # Two costs, not one:
    #
    # 1. The glossary pass reads the file once and returns a short term list —
    #    heavy input, light output.
    # 2. Each chunk then carries the system prompt AND the glossary block, and
    #    its output runs longer than the source because JSON wrapping and
    #    Portuguese both expand it.
    chunks = [(payload_tokens.to_f / Legendator::Config.max_tokens_per_chunk).ceil, 1].max

    glossary_input  = [payload_tokens, Legendator::Glossary::MAX_SAMPLE_TOKENS].min
    glossary_output = GLOSSARY_OUTPUT_TOKENS

    input_tokens  = glossary_input + payload_tokens + (PROMPT_OVERHEAD_PER_CHUNK * chunks)
    output_tokens = glossary_output + (payload_tokens * OUTPUT_RATIO).ceil

    cost_brl = (
      (input_tokens * @spec.input_usd + output_tokens * @spec.output_usd) / 1_000_000.0
    ) * exchange_rate

    if cost_brl > MAX_AI_COST_BRL
      return failure(
        "e grande demais: custaria R$ #{format('%.2f', cost_brl)} de IA " \
        "(limite R$ #{format('%.2f', MAX_AI_COST_BRL)})",
        subtitles: texts.size, input_tokens: input_tokens,
        output_tokens: output_tokens, ai_cost_brl: cost_brl
      )
    end

    Measurement.new(
      subtitles: texts.size, input_tokens: input_tokens,
      output_tokens: output_tokens, ai_cost_brl: cost_brl, ok: true, reason: nil
    )
  rescue StandardError => e
    Rails.logger.warn("[SrtSizeGate] could not measure SRT: #{e.class}: #{e.message}")
    failure("nao pode ser lido")
  end

  private

  # Calibrated against a real full-file run of movie-big-example.srt through
  # openai/gpt-5.6-luna on 11/08/2026, with the glossary pass and 4-way
  # parallelism in place (3.072 blocks, 7 chunks, US$ 0,036895 total):
  #
  #   payload measured here      32.954 tokens
  #   glossary pass              in 30.989 / out 1.787
  #   chunks                     in 44.741 / out 43.928
  #     -> overhead per chunk    1.684  (system prompt + glossary block)
  #     -> output ratio          1,333x the payload
  #
  # Rounded up from the measurement so the gate errs toward refusing a
  # borderline file rather than accepting one that loses money.
  PROMPT_OVERHEAD_PER_CHUNK = 1_800
  OUTPUT_RATIO = 1.45
  GLOSSARY_OUTPUT_TOKENS = 2_000

  def failure(reason, **attrs)
    Measurement.new(
      subtitles: 0, input_tokens: 0, output_tokens: 0, ai_cost_brl: 0.0,
      ok: false, reason: reason, **attrs
    )
  end

  def token_counter
    @token_counter ||= Legendator::TokenCounter.new(model: @spec.slug)
  end

  def exchange_rate
    @usd_brl ||= CostCalculator.usd_brl_rate
  end
end
