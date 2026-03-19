class PixService
  OAUTH_PATH = "/oauth/v2/token"
  PIX_COB_PATH = "/pix/v2/cob"

  def initialize
    @base_url = ENV.fetch("INTER_BASE_URL")
    @client_id = ENV.fetch("INTER_CLIENT_ID")
    @client_secret = ENV.fetch("INTER_CLIENT_SECRET")
    @chave_pix = ENV.fetch("INTER_CHAVE_PIX")
    @cert_path = Rails.root.join(ENV.fetch("INTER_CERT_PATH"))
    @key_path = Rails.root.join(ENV.fetch("INTER_KEY_PATH"))
  end

  def create_charge(translation)
    # PIX txid must be 26-35 alphanumeric chars [a-zA-Z0-9]
    raw = "LEG#{translation.access_token}#{Time.current.to_i}"
    txid = raw.gsub(/[^a-zA-Z0-9]/, "").ljust(26, SecureRandom.alphanumeric(26))[0, 35]

    payload = {
      calendario: { expiracao: 3600 },
      valor: { original: format("%.2f", translation.cost_brl) },
      chave: @chave_pix,
      solicitacaoPagador: "Legendator #{translation.formatted_code} - legendator.com.br",
      infoAdicionais: [
        { nome: "Codigo", valor: translation.formatted_code }
      ]
    }

    response = create_pix_cobranca(txid, payload)
    pix_code = response["pixCopiaECola"]

    translation.create_payment!(
      pix_txid: txid,
      pix_copia_e_cola: pix_code,
      pix_qr_code_base64: generate_qr_base64(pix_code),
      amount_brl: translation.cost_brl,
      status: :pending,
      expires_at: 1.hour.from_now
    )
  end

  def check_payment(payment)
    return false unless payment&.pending?

    response = fetch_cobranca(payment.pix_txid)
    return false unless response["status"] == "CONCLUIDA"

    payment.update!(status: :confirmed, paid_at: Time.current)
    payment.translation.paid!
    TranslateSubtitleJob.perform_later(payment.translation.id)
    true
  rescue => e
    Rails.logger.warn("[PixService] check_payment failed: #{e.message}")
    false
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

  def create_pix_cobranca(txid, payload)
    token = fetch_access_token
    uri = URI("#{@base_url}#{PIX_COB_PATH}/#{txid}")

    http = build_mtls_http(uri)
    request = Net::HTTP::Put.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = payload.to_json

    response = http.request(request)

    body = response.body.force_encoding("UTF-8")

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("[PixService] Cobranca failed: #{response.code} - #{body}")
      raise "Inter PIX API error: #{response.code} - #{body}"
    end

    JSON.parse(body)
  end

  def fetch_access_token
    Rails.cache.fetch("inter_oauth_token", expires_in: 50.minutes) do
      uri = URI("#{@base_url}#{OAUTH_PATH}")

      http = build_mtls_http(uri)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(
        client_id: @client_id,
        client_secret: @client_secret,
        scope: "cob.write cob.read pix.read",
        grant_type: "client_credentials"
      )

      response = http.request(request)
      body = response.body.force_encoding("UTF-8")

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.error("[PixService] OAuth failed: #{response.code} - #{body}")
        raise "Inter OAuth error: #{response.code} - #{body}"
      end

      JSON.parse(body)["access_token"]
    end
  end

  def fetch_cobranca(txid)
    token = fetch_access_token
    uri = URI("#{@base_url}#{PIX_COB_PATH}/#{txid}")

    http = build_mtls_http(uri)
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"

    response = http.request(request)
    body = response.body.force_encoding("UTF-8")

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("[PixService] Check cobranca failed: #{response.code} - #{body}")
      return {}
    end

    JSON.parse(body)
  end

  def generate_qr_base64(pix_code)
    qr = RQRCode::QRCode.new(pix_code)
    png = qr.as_png(size: 400, border_modules: 2)
    Base64.strict_encode64(png.to_s)
  end

  def build_mtls_http(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.cert = OpenSSL::X509::Certificate.new(File.read(@cert_path))
    http.key = OpenSSL::PKey::RSA.new(File.read(@key_path))
    http.open_timeout = 10
    http.read_timeout = 15
    http
  end
end
