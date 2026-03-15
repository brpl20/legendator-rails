class PixService
  def initialize
    @base_url = Rails.application.credentials.dig(:pix, :base_url)
    @client_id = Rails.application.credentials.dig(:pix, :client_id)
    @client_secret = Rails.application.credentials.dig(:pix, :client_secret)
    @chave_pix = Rails.application.credentials.dig(:pix, :chave_pix)
  end

  def create_charge(translation)
    txid = "LEG#{translation.access_token}#{Time.current.to_i}"

    payload = {
      calendario: { expiracao: 3600 },
      valor: { original: format("%.2f", translation.cost_brl) },
      chave: @chave_pix,
      solicitacaoPagador: "Legendator #{translation.formatted_code} - legendator.com.br",
      infoAdicionais: [
        { nome: "Codigo", valor: translation.formatted_code }
      ]
    }

    response = call_banco_inter_api(txid, payload)

    translation.create_payment!(
      pix_txid: txid,
      pix_copia_e_cola: response["pixCopiaECola"],
      pix_qr_code_base64: response["qrCode"],
      amount_brl: translation.cost_brl,
      status: :pending,
      expires_at: 1.hour.from_now
    )
  end

  def confirm_payment(pix_data)
    txid = pix_data[:txid]
    payment = Payment.find_by(pix_txid: txid)
    return false unless payment

    payment.update!(status: :confirmed, paid_at: Time.current)
    payment.translation.paid!

    TranslateSubtitleJob.perform_later(payment.translation.id)
    true
  end

  private

  def call_banco_inter_api(txid, payload)
    # TODO: Implement real Banco Inter API call
    {
      "txid" => txid,
      "pixCopiaECola" => "PLACEHOLDER_PIX_COPIA_E_COLA",
      "qrCode" => "PLACEHOLDER_QR_CODE_BASE64"
    }
  end
end
