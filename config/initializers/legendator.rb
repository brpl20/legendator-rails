# Everything goes through OpenRouter — one key, one wire format, one bill.
#
# Wrapped in to_prepare because AiModel is autoloaded: referencing it directly
# at initializer time raises under Zeitwerk. to_prepare also re-applies the
# config after a dev reload, so editing AiModel takes effect without a restart.
Rails.application.config.to_prepare do
  Legendator.configure do |config|
    config.api_key = Rails.application.credentials.dig(:openrouter, :api_key)
    config.model   = AiModel::DEFAULT_SLUG
    config.target_language = "pt-BR"

    # If the primary model fails, cascade to these. Each gets max_retries
    # attempts with exponential backoff before moving to the next.
    config.fallback_models = AiModel.fallback_slugs

    config.max_retries = 3
    config.retry_base_delay = 2
  end
end
