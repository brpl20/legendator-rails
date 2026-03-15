Legendator.configure do |config|
  config.provider = :openrouter
  config.api_key  = Rails.application.credentials.dig(:openrouter, :api_key)
  config.model    = "gpt-4.1-mini"
  config.target_language = "pt-BR"
end
