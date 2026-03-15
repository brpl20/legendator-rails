class CostCalculator
  MODEL_PRICING = {
    "openai/gpt-4.1-mini"        => { input: 0.40,  output: 1.60 },
    "google/gemini-2.5-flash"    => { input: 0.30,  output: 2.50 },
    "openai/gpt-4.1"             => { input: 2.00,  output: 8.00 },
    "deepseek-ai/deepseek-chat"  => { input: 0.14,  output: 0.28 },
    "qwen/qwen3.5-9b"           => { input: 0.05,  output: 0.15 }
  }.freeze

  def initialize(model: "openai/gpt-4.1-mini")
    @model = model
    @pricing = MODEL_PRICING[@model] || MODEL_PRICING["openai/gpt-4.1-mini"]
    @markup_percentage = Rails.application.credentials.dig(:pricing, :markup_percentage) || 200
    @financial_markup = Rails.application.credentials.dig(:pricing, :financial_markup) || 10
    @minimum_brl = Rails.application.credentials.dig(:pricing, :minimum_brl) || 2.00
    @fallback_rate = Rails.application.credentials.dig(:pricing, :fallback_exchange_rate) || 5.50
  end

  def estimate(srt_content)
    info = Legendator.dry_run_content(srt_content, model: @model)
    tokens = info[:estimated_tokens]

    input_cost = tokens[:input] * @pricing[:input] / 1_000_000.0
    output_cost = tokens[:output] * @pricing[:output] / 1_000_000.0
    estimated_usd = input_cost + output_cost

    cost_brl = apply_markups(estimated_usd)

    {
      cost_user_brl: cost_brl,
      estimated_usd: estimated_usd,
      estimated_tokens: tokens,
      model: @model
    }
  end

  def calculate(openrouter_cost_usd, input_tokens: nil, output_tokens: nil)
    if openrouter_cost_usd.nil? || openrouter_cost_usd.zero?
      if input_tokens && output_tokens
        input_cost = input_tokens * @pricing[:input] / 1_000_000.0
        output_cost = output_tokens * @pricing[:output] / 1_000_000.0
        estimated_usd = input_cost + output_cost
        cost_brl = apply_markups(estimated_usd)
        return { cost_brl: cost_brl, cost_usd: estimated_usd, fallback: true }
      else
        return { cost_brl: @minimum_brl, cost_usd: 0.0, fallback: true }
      end
    end

    cost_brl = apply_markups(openrouter_cost_usd)
    { cost_brl: cost_brl, cost_usd: openrouter_cost_usd, fallback: false }
  end

  private

  def apply_markups(cost_usd)
    rate = fetch_exchange_rate
    business_multiplier = 1 + (@markup_percentage / 100.0)
    financial_multiplier = 1 + (@financial_markup / 100.0)

    cost_brl = cost_usd * rate * financial_multiplier * business_multiplier
    cost_brl = cost_brl.ceil(2)
    [cost_brl, @minimum_brl].max
  end

  def fetch_exchange_rate
    Rails.cache.fetch("usd_brl_exchange_rate", expires_in: 1.hour) do
      fetch_rate_from_api
    end
  rescue StandardError => e
    Rails.logger.warn "[CostCalculator] Exchange rate API failed: #{e.message}. Using fallback."
    @fallback_rate
  end

  def fetch_rate_from_api
    uri = URI("https://economia.awesomeapi.com.br/json/last/USD-BRL")
    response = Net::HTTP.get(uri)
    data = JSON.parse(response)
    data.dig("USDBRL", "bid").to_f
  end
end
