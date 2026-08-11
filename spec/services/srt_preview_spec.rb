require "rails_helper"

RSpec.describe SrtPreview do
  # rails_helper stubs SrtPreview#call suite-wide so the upload flow never calls
  # a provider. This is the one file that must exercise the real method.
  before { allow_any_instance_of(described_class).to receive(:call).and_call_original }

  def srt(count)
    (1..count).map { |i| "#{i}\n00:00:01,000 --> 00:00:04,000\nLinha #{i}\n" }.join("\n")
  end

  def stub_glossary(title:, summary:, terms: [])
    result = Legendator::Glossary::Result.new(
      title: title, summary: summary, terms: terms,
      input_tokens: 100, output_tokens: 50, cost: 0.0001
    )
    allow(Legendator::Glossary).to receive(:new).and_return(
      instance_double(Legendator::Glossary, build: result)
    )
    result
  end

  it "returns the detected work and summary" do
    stub_glossary(title: "Rocky", summary: "Drama de boxe.")

    preview = described_class.new(srt(200)).call

    expect(preview).to be_ok
    expect(preview.title).to eq("Rocky")
    expect(preview.summary).to eq("Drama de boxe.")
  end

  it "seeds a context suggestion from the terms it spotted" do
    stub_glossary(
      title: "Rocky", summary: "Drama de boxe.",
      terms: [
        { "source" => "Champ", "target" => "Campeao" },
        { "source" => "Kid",   "target" => "Garoto" }
      ]
    )

    preview = described_class.new(srt(200)).call

    expect(preview.suggested_context).to include("Champ = Campeao")
    expect(preview.suggested_context).to include("Kid = Garoto")
  end

  # This runs on every upload, including abandoned ones, so it must read the
  # opening only — not the whole film the customer has not paid for yet.
  it "only sends the opening of the file" do
    captured = nil
    allow(Legendator::Glossary).to receive(:new) do |texts, **|
      captured = texts
      instance_double(Legendator::Glossary, build: Legendator::Glossary::Result.new(
        title: "x", summary: "y", terms: [], input_tokens: 1, output_tokens: 1, cost: 0.0
      ))
    end

    described_class.new(srt(2_000)).call

    expect(captured.size).to eq(described_class::SAMPLE_BLOCKS)
    expect(captured.keys.max).to be <= described_class::SAMPLE_BLOCKS
  end

  it "reports not-ok for a file with no subtitles" do
    expect(described_class.new("nao e um srt").call).not_to be_ok
  end

  it "reports not-ok when the model returns nothing useful" do
    stub_glossary(title: "", summary: "")

    expect(described_class.new(srt(50)).call).not_to be_ok
  end

  # A failed preview must never cost the sale.
  it "swallows errors instead of raising" do
    allow(Legendator::Glossary).to receive(:new).and_raise(StandardError, "provider down")

    expect { described_class.new(srt(50)).call }.not_to raise_error
    expect(described_class.new(srt(50)).call).not_to be_ok
  end
end
