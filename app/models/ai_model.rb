# Single source of truth for which AI models we offer, what they cost and how
# big a job they can take. Everything is reached through OpenRouter, so a model
# is identified by its OpenRouter slug.
#
# Prices are USD per 1M tokens, as published by OpenRouter. `max_output_tokens`
# is the provider's completion ceiling — it, not the context window, is what
# limits how many subtitles fit in one request.
class AiModel
  Spec = Struct.new(:slug, :label, :input_usd, :output_usd, :max_output_tokens, keyword_init: true)

  CATALOG = [
    Spec.new(
      slug: "openai/gpt-5.6-luna",
      label: "Padrao (recomendado)",
      input_usd: 0.10, output_usd: 0.60, max_output_tokens: 128_000
    ),
    Spec.new(
      slug: "deepseek/deepseek-v4-flash-0731",
      label: "Economico (mais lento)",
      input_usd: 0.08, output_usd: 0.18, max_output_tokens: 384_000
    )
  ].freeze

  # Measured on a 25-subtitle sample (2026-08-10), which is why openai/gpt-5-nano
  # is NOT in the catalog despite the cheapest per-token price. It is a reasoning
  # model and emitted 7.118 output tokens where luna emitted 571 — extrapolated
  # to a full movie that is R$ 1,90 of AI cost against R$ 1,00 charged, and it
  # blows past its own 128k output ceiling. Per-token price is not the cost.
  #
  #   model                            25-sub latency   out tokens   full movie
  #   openai/gpt-5.6-luna                       5s            571      R$ 0,25
  #   deepseek/deepseek-v4-flash-0731         124s           1145      R$ 0,15
  #   openai/gpt-5-nano  (rejected)            44s           7118      R$ 1,90

  BY_SLUG = CATALOG.index_by(&:slug).freeze

  DEFAULT_SLUG = "openai/gpt-5.6-luna".freeze

  class << self
    def default
      BY_SLUG.fetch(DEFAULT_SLUG)
    end

    # Unknown slugs fall back to the default rather than raising — an old
    # record with a retired slug must still render and still be priced.
    def find(slug)
      BY_SLUG[slug.to_s] || default
    end

    def exists?(slug)
      BY_SLUG.key?(slug.to_s)
    end

    def slugs
      BY_SLUG.keys
    end

    # Cascade used when the primary model fails: cheapest survivors first.
    def fallback_slugs
      slugs - [DEFAULT_SLUG]
    end

    # [[label, slug], ...] for a form select.
    def options_for_select
      CATALOG.map { |spec| [spec.label, spec.slug] }
    end
  end
end
