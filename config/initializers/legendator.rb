Legendator.configure do |config|
  config.provider = :openrouter
  config.api_key  = Rails.application.credentials.dig(:openrouter, :api_key)
  config.model    = "openai/gpt-4.1-mini"
  config.target_language = "pt-BR"

  # Fallback cascade: if OpenRouter fails, try OpenAI direct, then OpenRouter with a cheaper model.
  # Each provider gets 3 retry attempts with exponential backoff before moving to the next.
  config.fallback_providers = [
    { provider: :openrouter, model: "google/gemini-2.5-flash", api_key: Rails.application.credentials.dig(:openrouter, :api_key) },
    { provider: :openrouter, model: "deepseek-ai/deepseek-chat", api_key: Rails.application.credentials.dig(:openrouter, :api_key) },
    { provider: :openai, model: "gpt-4.1-mini", api_key: Rails.application.credentials.dig(:openai, :api_key) }
  ]

  config.max_retries = 3
  config.retry_base_delay = 2
end
