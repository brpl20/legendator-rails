require "rails_helper"

RSpec.describe "Translation flow", type: :request do
  before do
    allow(Legendator).to receive(:dry_run_content).and_return({
      subtitles: 2,
      chunks: { total_chunks: 1 },
      estimated_tokens: { input: 100, output: 100, total: 200 }
    })
    allow_any_instance_of(CostCalculator).to receive(:fetch_exchange_rate).and_return(5.50)
    allow_any_instance_of(PixService).to receive(:call_banco_inter_api).and_return({
      "txid" => "LEGINTEGRATION1",
      "pixCopiaECola" => "pix-code-here",
      "qrCode" => "qr-base64-here"
    })
  end

  it "completes the full upload -> payment -> translation -> download flow" do
    # 1. Upload
    srt_file = fixture_file_upload(
      Rails.root.join("spec/fixtures/files/sample.srt"),
      "text/plain"
    )

    post translations_path, params: {
      translation: {
        original_file: srt_file,
        target_language: "pt-BR",
        model_used: "gpt-4.1-mini"
      }
    }

    translation = Translation.last
    expect(translation).to be_pending_payment
    expect(translation.cost_user).to be >= 2.00
    expect(translation.payment).to be_present

    # 2. Show page with payment info
    get translation_path(translation)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(translation.formatted_code)

    # 3. Simulate PIX webhook
    post webhooks_pix_path, params: { txid: translation.payment.pix_txid }, as: :json
    expect(response).to have_http_status(:ok)
    expect(translation.reload).to be_paid

    # 4. Simulate job execution
    require "ostruct"
    fake_result = OpenStruct.new(
      srt_content: "1\n00:00:01,000 --> 00:00:04,000\nOla mundo\n",
      token_usage: { input_tokens: 100, output_tokens: 80, total_tokens: 180 },
      coverage: { total_subtitles: 1, translated: 1, coverage_percent: 100.0 },
      cost: 0.001
    )
    allow(Legendator).to receive(:translate_content).and_return(fake_result)
    allow_any_instance_of(CostCalculator).to receive(:calculate).and_return(
      { cost_brl: 2.00, cost_usd: 0.001, fallback: false }
    )

    TranslateSubtitleJob.perform_now(translation.id)

    translation.reload
    expect(translation).to be_completed
    expect(translation.translated_file).to be_attached

    # 5. Download
    get download_translation_path(translation)
    expect(response).to have_http_status(:redirect)

    # 6. Recovery flow
    post recover_path, params: { code: translation.formatted_code }
    expect(response).to redirect_to(translation_path(translation))
  end
end
