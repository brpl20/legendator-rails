require "rails_helper"

RSpec.describe "Webhooks", type: :request do
  describe "POST /webhooks/pix" do
    it "returns 200 for valid payment" do
      translation = create(:translation, status: :pending_payment)
      payment = create(:payment, translation: translation, pix_txid: "LEGTEST123")

      post webhooks_pix_path, params: { txid: "LEGTEST123" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(payment.reload).to be_confirmed
    end

    it "returns 404 for unknown txid" do
      post webhooks_pix_path, params: { txid: "UNKNOWN" }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end
end
