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

    # Input carries the system prompt once per chunk; output runs longer than the
    # source because JSON wrapping and Portuguese both expand it. OUTPUT_RATIO is
    # calibrated against a real full-file run, not guessed.
    chunks = [(payload_tokens.to_f / Legendator::Config.max_tokens_per_chunk).ceil, 1].max
    input_tokens  = payload_tokens + (PROMPT_OVERHEAD_PER_CHUNK * chunks)
    output_tokens = (payload_tokens * OUTPUT_RATIO).ceil

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
  # openai/gpt-5.6-luna on 10/08/2026 (3.072 blocks, 7 chunks):
  #
  #   payload measured here   32.954 tokens
  #   input reported by API   39.904  ->   993 overhead per chunk
  #   output reported by API  43.679  ->  1,325x the payload
  #   cost reported by API    US$ 0,031186
  #
  # Both constants are rounded up from the measurement so the gate errs toward
  # refusing a borderline file rather than accepting one that loses money.
  PROMPT_OVERHEAD_PER_CHUNK = 1_050
  OUTPUT_RATIO = 1.40

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
