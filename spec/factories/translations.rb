FactoryBot.define do
  factory :translation do
    original_filename { "movie.srt" }
    target_language { "pt-BR" }
    model_used { AiModel::DEFAULT_SLUG }
  end
end
