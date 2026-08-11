require "rails_helper"

RSpec.describe "Translation size gate", type: :request do
  before do
    allow_any_instance_of(CostCalculator).to receive(:fetch_exchange_rate).and_return(5.50)
    allow_any_instance_of(PixService).to receive(:create_charge)
  end

  def upload(content, filename: "movie.srt")
    Rack::Test::UploadedFile.new(StringIO.new(content), "text/plain", original_filename: filename)
  end

  def oversized_srt
    line = "This is a deliberately long subtitle line used to inflate the payload. " * 6
    (1..4_000).map { |i| "#{i}\n00:00:01,000 --> 00:00:04,000\n#{line}\n" }.join("\n")
  end

  def small_srt
    (1..20).map { |i| "#{i}\n00:00:01,000 --> 00:00:04,000\nHello world\n" }.join("\n")
  end

  it "refuses an oversized file instead of charging the minimum for it" do
    post translations_path, params: {
      translation: { original_file: upload(oversized_srt), target_language: "pt-BR", model_used: AiModel::DEFAULT_SLUG }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Translation.count).to eq(0)
  end

  it "prices an accepted file from its measured size, not a flat rate" do
    post translations_path, params: {
      translation: { original_file: upload(small_srt), target_language: "pt-BR", model_used: AiModel::DEFAULT_SLUG }
    }

    expect(response).to have_http_status(:redirect)
    translation = Translation.last
    expect(translation.cost_user).to be >= 1.00
    expect(translation.subtitle_count).to eq(20)
  end

  it "stores the user's context so the translator can use it" do
    post translations_path, params: {
      translation: {
        original_file: upload(small_srt),
        target_language: "pt-BR",
        model_used: AiModel::DEFAULT_SLUG,
        context: "Traduzir 'Snow' como 'Neve'. Manter 'Hodor'."
      }
    }

    expect(Translation.last.context).to eq("Traduzir 'Snow' como 'Neve'. Manter 'Hodor'.")
  end

  it "rejects a context longer than the cap" do
    post translations_path, params: {
      translation: {
        original_file: upload(small_srt),
        target_language: "pt-BR",
        model_used: AiModel::DEFAULT_SLUG,
        context: "x" * (Translation::MAX_CONTEXT_LENGTH + 1)
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Translation.count).to eq(0)
  end

  it "rejects a model slug that is not in the catalog" do
    post translations_path, params: {
      translation: { original_file: upload(small_srt), target_language: "pt-BR", model_used: "deepseek-ai/deepseek-chat" }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Translation.count).to eq(0)
  end
end
