require "rails_helper"

RSpec.describe PixService do
  let(:translation) { create(:translation, cost_user: 5.00) }

  describe "#create_charge" do
    it "creates a payment record for the translation" do
      service = PixService.new
      allow(service).to receive(:call_banco_inter_api).and_return({
        "txid" => "LEG12345678",
        "pixCopiaECola" => "00020126...",
        "qrCode" => "base64encodedqr..."
      })

      expect { service.create_charge(translation) }.to change(Payment, :count).by(1)

      payment = translation.reload.payment
      expect(payment).to be_pending
      expect(payment.amount_brl).to eq(5.00)
      expect(payment.expires_at).to be_present
      expect(payment.expires_at).to be > Time.current
    end
  end

  describe "#confirm_payment" do
    it "marks payment as confirmed and enqueues translation job" do
      payment = create(:payment, translation: translation, pix_txid: "LEGTESTTOKEN123")
      service = PixService.new

      expect {
        result = service.confirm_payment(txid: "LEGTESTTOKEN123")
        expect(result).to be true
      }.to have_enqueued_job(TranslateSubtitleJob).with(translation.id)

      expect(payment.reload).to be_confirmed
      expect(payment.paid_at).to be_present
      expect(translation.reload).to be_paid
    end

    it "returns false for unknown txid" do
      service = PixService.new
      result = service.confirm_payment(txid: "UNKNOWN")
      expect(result).to be false
    end
  end
end
