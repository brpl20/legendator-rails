require "rails_helper"
require "ostruct"

RSpec.describe TranslateSubtitleJob, type: :job do
  let(:translation) do
    t = create(:translation, status: :paid, model_used: AiModel::DEFAULT_SLUG)
    t.original_file.attach(
      io: StringIO.new("1\n00:00:01,000 --> 00:00:04,000\nHello world\n"),
      filename: "test.srt",
      content_type: "text/plain"
    )
    t
  end

  let(:fake_result) do
    OpenStruct.new(
      srt_content: "1\n00:00:01,000 --> 00:00:04,000\nOla mundo\n",
      token_usage: { input_tokens: 100, output_tokens: 80, total_tokens: 180 },
      coverage: { total_subtitles: 1, translated: 1, coverage_percent: 100.0 },
      cost: 0.001
    )
  end

  describe "#perform" do
    it "translates and updates translation to completed" do
      allow(Legendator).to receive(:translate_content).and_return(fake_result)
      allow_any_instance_of(CostCalculator).to receive(:calculate).and_return(
        { cost_brl: 2.00, cost_usd: 0.001, fallback: false }
      )

      TranslateSubtitleJob.perform_now(translation.id)

      translation.reload
      expect(translation).to be_completed
      expect(translation.translated_file).to be_attached
      expect(translation.tokens_input).to eq(100)
      expect(translation.tokens_output).to eq(80)
      expect(translation.cost_ai).to eq(0.001)
      expect(translation.cost_ai_brl).to eq(2.00)
      expect(translation.processing_time).to be > 0
    end

    it "marks translation as failed on error" do
      allow(Legendator).to receive(:translate_content).and_raise("API Error")

      TranslateSubtitleJob.perform_now(translation.id)

      translation.reload
      expect(translation).to be_failed
      expect(translation.error_message).to eq("API Error")
    end

    # The gem has always accepted a context (it builds it into the system
    # prompt), but the job never passed one — so character-name guidance
    # entered by the user went nowhere.
    it "forwards the user's context to the translator" do
      translation.update!(context: "Traduzir 'Snow' como 'Neve'.")

      expect(Legendator).to receive(:translate_content).with(
        anything,
        hash_including(context: "Traduzir 'Snow' como 'Neve'.")
      ).and_return(fake_result)
      allow_any_instance_of(CostCalculator).to receive(:calculate).and_return(
        { cost_brl: 2.00, cost_usd: 0.001, fallback: false }
      )

      TranslateSubtitleJob.perform_now(translation.id)
    end

    it "passes no context when the user left the field blank" do
      translation.update!(context: "")

      expect(Legendator).to receive(:translate_content).with(
        anything,
        hash_including(context: nil)
      ).and_return(fake_result)
      allow_any_instance_of(CostCalculator).to receive(:calculate).and_return(
        { cost_brl: 2.00, cost_usd: 0.001, fallback: false }
      )

      TranslateSubtitleJob.perform_now(translation.id)
    end
  end
end
