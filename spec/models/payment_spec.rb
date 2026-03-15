require "rails_helper"

RSpec.describe Payment, type: :model do
  let(:translation) { create(:translation) }

  describe "associations" do
    it "belongs to translation" do
      payment = Payment.new(translation: translation, amount_brl: 2.00)
      expect(payment.translation).to eq(translation)
    end
  end

  describe "status enum" do
    it "defaults to pending" do
      payment = Payment.create!(translation: translation, amount_brl: 2.00)
      expect(payment).to be_pending
    end
  end

  describe "#expired?" do
    it "returns false when expires_at is in the future" do
      payment = Payment.new(expires_at: 1.hour.from_now)
      expect(payment).not_to be_expired
    end

    it "returns true when expires_at is in the past" do
      payment = Payment.new(expires_at: 1.hour.ago)
      expect(payment).to be_expired
    end

    it "returns false when expires_at is nil" do
      payment = Payment.new(expires_at: nil)
      expect(payment).not_to be_expired
    end
  end
end
