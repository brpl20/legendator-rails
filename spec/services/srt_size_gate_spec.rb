require "rails_helper"

RSpec.describe SrtSizeGate do
  # Fixed rate so the ceiling assertions don't depend on the live USD/BRL API.
  def gate(content, **opts)
    described_class.new(content, usd_brl: 5.40, **opts)
  end

  def srt(count, line: "Hello world, this is a subtitle line.")
    (1..count).map do |i|
      "#{i}\n00:00:#{format('%02d', i % 60)},000 --> 00:00:#{format('%02d', (i + 1) % 60)},000\n#{line}\n"
    end.join("\n")
  end

  it "accepts a normal file and reports what the AI will cost" do
    result = gate(srt(100)).measure

    expect(result).to be_ok
    expect(result.reason).to be_nil
    expect(result.subtitles).to eq(100)
    expect(result.ai_cost_brl).to be > 0
    expect(result.ai_cost_brl).to be <= described_class::MAX_AI_COST_BRL
  end

  # The reference file: a full-length feature, 3.072 subtitle blocks. This must
  # stay comfortably inside the ceiling or we have priced ourselves out of our
  # own product.
  it "accepts a full-length movie — the movie-big-example baseline" do
    result = gate(srt(3_072)).measure

    expect(result).to be_ok
    expect(result.subtitles).to eq(3_072)
    expect(result.ai_cost_brl).to be < described_class::MAX_AI_COST_BRL
  end

  it "refuses a file whose AI cost would pass the ceiling" do
    long_line = "This is a deliberately long subtitle line used to inflate the payload. " * 8
    result = gate(srt(6_000, line: long_line)).measure

    expect(result).not_to be_ok
    expect(result.reason).to include("custaria R$")
    expect(result.ai_cost_brl).to be > described_class::MAX_AI_COST_BRL
  end

  it "states the actual price in the refusal so the number is auditable" do
    long_line = "Another long subtitle line that inflates the token payload nicely. " * 8
    result = gate(srt(6_000, line: long_line)).measure

    expect(result.reason).to match(/custaria R\$ \d+\.\d{2} de IA \(limite R\$ 0\.70\)/)
  end

  it "refuses an absurd number of blocks before bothering to price it" do
    result = gate(srt(described_class::MAX_SUBTITLES + 1, line: "Hi")).measure

    expect(result).not_to be_ok
    expect(result.reason).to include("legendas")
  end

  it "prices against the chosen model, not always the default" do
    content = srt(2_000)
    cheap = gate(content, model: "deepseek/deepseek-v4-flash-0731").measure
    default = gate(content).measure

    expect(cheap.ai_cost_brl).to be < default.ai_cost_brl
  end

  # Verified against the real fixtures on 10/08/2026: ten copies of
  # movie-big-example.srt (2,2MB, 30.720 blocks) merged both ways.
  describe "several files merged into one" do
    let(:one_file) { srt(500) }

    it "refuses a naive concatenation, which would otherwise be silently truncated" do
      merged = ([one_file.strip] * 10).join("\n\n") + "\n"

      # The danger: extract_texts keys by ID, so the repeated 1..500 collapse
      # back to 500 entries. Cost looks fine; the customer gets a tenth of it.
      expect(Legendator::SrtParser.new(merged).parse.size).to eq(5_000)
      expect(Legendator::SrtParser.new(merged).extract_texts.size).to eq(500)

      result = gate(merged).measure
      expect(result).not_to be_ok
      expect(result.reason).to include("numeracao repetida")
    end

    # Ten movie-sized files renumbered end to end: 10 x 3.072 blocks. This is the
    # merge that actually costs money, since every block is a distinct ID.
    it "refuses a properly renumbered merge of ten movies" do
      result = gate(srt(30_720)).measure

      expect(result).not_to be_ok
      expect(result.reason).to include("maximo #{described_class::MAX_SUBTITLES}")
    end

    it "still accepts two full movies merged — that is inside the budget" do
      result = gate(srt(6_144)).measure

      expect(result).to be_ok
      expect(result.ai_cost_brl).to be < described_class::MAX_AI_COST_BRL
    end
  end

  it "rejects a file with no parseable subtitles" do
    result = gate("this is not an srt at all").measure

    expect(result).not_to be_ok
    expect(result.reason).to include("nao contem legendas validas")
  end

  it "rejects an empty file" do
    expect(gate("").measure).not_to be_ok
  end
end
