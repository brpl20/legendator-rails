require "rails_helper"

RSpec.describe "Context before payment", type: :request do
  before do
    allow_any_instance_of(CostCalculator).to receive(:fetch_exchange_rate).and_return(5.50)
    allow_any_instance_of(PixService).to receive(:create_charge)
  end

  def small_srt
    (1..20).map { |i| "#{i}\n00:00:01,000 --> 00:00:04,000\nHello world\n" }.join("\n")
  end

  def upload
    Rack::Test::UploadedFile.new(StringIO.new(small_srt), "text/plain", original_filename: "movie.srt")
  end

  def stub_preview(title: "Rocky", summary: "Drama de boxe.", suggested: "Traduzir: Champ = Campeao.")
    allow_any_instance_of(SrtPreview).to receive(:call).and_return(
      SrtPreview::Preview.new(title: title, summary: summary, suggested_context: suggested, ok: true)
    )
  end

  def create_translation(context: nil)
    post translations_path, params: {
      translation: { original_file: upload, target_language: "pt-BR",
                     model_used: AiModel::DEFAULT_SLUG, context: context }.compact
    }
    Translation.last
  end

  describe "detection on upload" do
    it "stores what it detected and seeds the context" do
      stub_preview
      translation = create_translation

      expect(translation.detected_title).to eq("Rocky")
      expect(translation.detected_summary).to eq("Drama de boxe.")
      expect(translation.context).to eq("Traduzir: Champ = Campeao.")
    end

    it "does not overwrite a context the customer already wrote" do
      stub_preview
      translation = create_translation(context: "Meu contexto proprio")

      expect(translation.context).to eq("Meu contexto proprio")
    end

    it "still completes the sale when detection fails" do
      allow_any_instance_of(SrtPreview).to receive(:call).and_raise(StandardError, "down")

      expect { create_translation }.not_to raise_error
      expect(response).to have_http_status(:redirect)
      expect(Translation.count).to eq(1)
    end
  end

  describe "editing before payment" do
    it "accepts a new context while payment is pending" do
      stub_preview
      translation = create_translation

      patch update_context_translation_path(translation),
            params: { translation: { context: "Manter Hodor sem traducao." } }

      expect(translation.reload.context).to eq("Manter Hodor sem traducao.")
    end

    it "refuses once the translation has started" do
      stub_preview
      translation = create_translation
      translation.update!(status: :processing)

      patch update_context_translation_path(translation),
            params: { translation: { context: "tarde demais" } }

      expect(translation.reload.context).not_to eq("tarde demais")
      expect(flash[:alert]).to be_present
    end

    it "rejects a context past the cap" do
      stub_preview
      translation = create_translation
      original = translation.context

      patch update_context_translation_path(translation),
            params: { translation: { context: "x" * (Translation::MAX_CONTEXT_LENGTH + 1) } }

      expect(translation.reload.context).to eq(original)
      expect(flash[:alert]).to be_present
    end
  end

  describe "the pending page" do
    it "shows the detection and an editable context box" do
      stub_preview
      translation = create_translation

      get translation_path(translation)

      expect(response.body).to include("Rocky")
      expect(response.body).to include("Drama de boxe.")
      expect(response.body).to include("context-box")
    end

    # The poller must not clobber what the customer is typing.
    it "polls with a script that skips reloading mid-edit" do
      stub_preview
      translation = create_translation

      get translation_path(translation)

      expect(response.body).not_to include('http-equiv="refresh"')
      expect(response.body).to include("editing()")
    end
  end
end
