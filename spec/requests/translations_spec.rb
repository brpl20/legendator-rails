require "rails_helper"

RSpec.describe "Translations", type: :request do
  describe "GET /translations/new" do
    it "renders the upload form" do
      get new_translation_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /translations" do
    let(:srt_file) do
      fixture_file_upload(
        Rails.root.join("spec/fixtures/files/sample.srt"),
        "text/plain"
      )
    end

    before do
      allow(Legendator).to receive(:dry_run_content).and_return({
        subtitles: 10,
        chunks: { total_chunks: 1 },
        estimated_tokens: { input: 500, output: 500, total: 1000 }
      })
      allow_any_instance_of(CostCalculator).to receive(:fetch_exchange_rate).and_return(5.50)
      allow_any_instance_of(PixService).to receive(:create_charge)
    end

    it "creates a translation and redirects to show" do
      post translations_path, params: {
        translation: {
          original_file: srt_file,
          target_language: "pt-BR",
          model_used: "gpt-4.1-mini"
        }
      }
      expect(response).to have_http_status(:redirect)
      expect(Translation.count).to eq(1)
    end
  end

  describe "GET /translations/:access_token" do
    it "shows the translation status" do
      translation = create(:translation)
      get translation_path(translation)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /recover" do
    it "redirects to translation when code is valid" do
      translation = create(:translation)
      post recover_path, params: { code: "LEG-#{translation.access_token}" }
      expect(response).to redirect_to(translation_path(translation))
    end

    it "renders form with alert when code is invalid" do
      post recover_path, params: { code: "LEG-INVALID1" }
      expect(response).to have_http_status(:ok)
    end
  end
end
