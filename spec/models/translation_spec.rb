require "rails_helper"

RSpec.describe Translation, type: :model do
  describe "validations" do
    it "requires original_filename" do
      translation = Translation.new(original_filename: nil, target_language: "pt-BR")
      expect(translation).not_to be_valid
      expect(translation.errors[:original_filename]).to include("can't be blank")
    end

    it "requires target_language" do
      translation = Translation.new(original_filename: "test.srt", target_language: nil)
      expect(translation).not_to be_valid
      expect(translation.errors[:target_language]).to include("can't be blank")
    end
  end

  describe "#generate_access_token" do
    it "generates an 8-char uppercase alphanumeric token on create" do
      translation = Translation.create!(original_filename: "test.srt", target_language: "pt-BR")
      expect(translation.access_token).to match(/\A[A-Z0-9]{8}\z/)
    end

    it "generates unique tokens" do
      t1 = Translation.create!(original_filename: "a.srt", target_language: "pt-BR")
      t2 = Translation.create!(original_filename: "b.srt", target_language: "pt-BR")
      expect(t1.access_token).not_to eq(t2.access_token)
    end
  end

  describe "#to_param" do
    it "returns access_token" do
      translation = Translation.create!(original_filename: "test.srt", target_language: "pt-BR")
      expect(translation.to_param).to eq(translation.access_token)
    end
  end

  describe "#formatted_code" do
    it "returns LEG- prefixed token" do
      translation = Translation.create!(original_filename: "test.srt", target_language: "pt-BR")
      expect(translation.formatted_code).to eq("LEG-#{translation.access_token}")
    end
  end

  describe "status enum" do
    it "defaults to pending_payment" do
      translation = Translation.create!(original_filename: "test.srt", target_language: "pt-BR")
      expect(translation).to be_pending_payment
    end

    it "supports all status transitions" do
      translation = Translation.create!(original_filename: "test.srt", target_language: "pt-BR")
      %w[paid processing completed failed expired].each do |status|
        expect { translation.update!(status: status) }.not_to raise_error
      end
    end
  end

  describe "constants" do
    it "has 9 supported languages" do
      expect(Translation::SUPPORTED_LANGUAGES.size).to eq(9)
    end

    it "has 5 available models" do
      expect(Translation::AVAILABLE_MODELS.size).to eq(5)
      expect(Translation::AVAILABLE_MODELS.keys).to include("gpt-4.1-mini", "gpt-4.1")
    end
  end
end
