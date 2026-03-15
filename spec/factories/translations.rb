FactoryBot.define do
  factory :translation do
    original_filename { "movie.srt" }
    target_language { "pt-BR" }
    model_used { "gpt-4.1-mini" }
  end
end
