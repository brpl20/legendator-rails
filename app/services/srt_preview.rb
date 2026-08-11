# Cheap look at the opening of an SRT, run before the customer pays, to tell
# them what we think they uploaded and to seed the context field they can edit.
#
# Deliberately NOT the full glossary pass. That one reads the entire file and is
# paid for out of a confirmed sale; this one runs on every upload, including the
# ones that are abandoned before payment, so it reads only the opening minutes.
# Roughly R$ 0,002 a call against R$ 0,027 for the full pass.
#
# A film establishes its cast and setting early, which is why the head is enough
# to name the work — the full pass after payment is what catches late arrivals.
class SrtPreview
  # Enough to cover the opening scenes without paying to read the film.
  SAMPLE_BLOCKS = 150

  Preview = Struct.new(:title, :summary, :suggested_context, :ok, keyword_init: true) do
    alias_method :ok?, :ok
  end

  def initialize(content, model: AiModel::DEFAULT_SLUG)
    @content = content
    @model = model
  end

  # Never raises and never blocks the sale: a failed preview just means the
  # customer sees no summary and writes their own context.
  def call
    texts = Legendator::SrtParser.new(@content).extract_texts
    return blank if texts.empty?

    head = texts.keys.sort.first(SAMPLE_BLOCKS).to_h { |id| [id, texts[id]] }

    result = Legendator::Glossary.new(
      head,
      target_language: "pt-BR",
      model: @model,
      api_key: Legendator.configuration.resolved_api_key
    ).build

    return blank if result.title.to_s.strip.empty? && result.summary.to_s.strip.empty?

    Preview.new(
      title: result.title.to_s.strip,
      summary: result.summary.to_s.strip,
      suggested_context: suggestion_from(result),
      ok: true
    )
  rescue StandardError => e
    Rails.logger.warn("[SrtPreview] preview failed: #{e.class}: #{e.message}")
    blank
  end

  private

  def blank
    Preview.new(title: nil, summary: nil, suggested_context: nil, ok: false)
  end

  # Prefill the context box with the terms we already spotted, so the customer
  # edits a concrete list instead of facing an empty field.
  def suggestion_from(result)
    return nil if result.terms.blank?

    lines = result.terms.first(8).map { |t| "#{t['source']} = #{t['target']}" }
    "Traduzir: #{lines.join('; ')}."
  end
end
