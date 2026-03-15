require "rails_helper"

RSpec.describe CostCalculator do
  describe "#estimate" do
    it "returns estimated cost in BRL" do
      dry_run_result = {
        subtitles: 100,
        chunks: { total_chunks: 2 },
        estimated_tokens: { input: 5000, output: 5000, total: 10000 }
      }
      allow(Legendator).to receive(:dry_run_content).and_return(dry_run_result)

      calculator = CostCalculator.new(model: "gpt-4.1-mini")
      allow(calculator).to receive(:fetch_exchange_rate).and_return(5.50)

      result = calculator.estimate("fake srt content")

      expect(result[:cost_user_brl]).to be_a(Numeric)
      expect(result[:cost_user_brl]).to be >= 2.00
    end

    it "enforces minimum R$ 2.00" do
      dry_run_result = {
        subtitles: 1,
        chunks: { total_chunks: 1 },
        estimated_tokens: { input: 10, output: 10, total: 20 }
      }
      allow(Legendator).to receive(:dry_run_content).and_return(dry_run_result)

      calculator = CostCalculator.new(model: "gpt-4.1-mini")
      allow(calculator).to receive(:fetch_exchange_rate).and_return(5.50)

      result = calculator.estimate("tiny srt")
      expect(result[:cost_user_brl]).to eq(2.00)
    end
  end

  describe "#calculate" do
    it "converts USD to BRL with markups" do
      calculator = CostCalculator.new(model: "gpt-4.1-mini")
      allow(calculator).to receive(:fetch_exchange_rate).and_return(5.50)

      result = calculator.calculate(0.01)
      expect(result[:cost_brl]).to eq(2.00)
    end

    it "calculates correctly for larger amounts" do
      calculator = CostCalculator.new(model: "gpt-4.1-mini")
      allow(calculator).to receive(:fetch_exchange_rate).and_return(5.50)

      # cost_usd=1.00 x 5.50 x 1.10 x 3.0 = 18.15, ceil(2) => 18.15 or 18.16 due to float
      result = calculator.calculate(1.00)
      expect(result[:cost_brl]).to be_within(0.02).of(18.15)
    end

    it "falls back to token estimation when cost is zero" do
      calculator = CostCalculator.new(model: "gpt-4.1-mini")
      allow(calculator).to receive(:fetch_exchange_rate).and_return(5.50)

      result = calculator.calculate(0.0, input_tokens: 5000, output_tokens: 5000)
      expect(result[:cost_brl]).to be >= 2.00
      expect(result[:fallback]).to be true
    end
  end

  describe "#fetch_exchange_rate" do
    it "returns fallback rate when API fails" do
      calculator = CostCalculator.new(model: "gpt-4.1-mini")
      allow(Net::HTTP).to receive(:get).and_raise(StandardError)

      rate = calculator.send(:fetch_exchange_rate)
      expect(rate).to eq(5.50)
    end
  end
end
