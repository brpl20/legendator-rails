FactoryBot.define do
  factory :payment do
    translation
    amount_brl { 2.00 }
    pix_txid { "LEG#{SecureRandom.alphanumeric(8)}#{Time.current.to_i}" }
  end
end
