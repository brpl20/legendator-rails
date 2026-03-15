class Translation < ApplicationRecord
  has_one :payment, dependent: :destroy
  has_one_attached :original_file
  has_one_attached :translated_file

  enum :status, {
    pending_payment: 0,
    paid: 1,
    processing: 2,
    completed: 3,
    failed: 4,
    expired: 5
  }

  validates :original_filename, presence: true
  validates :target_language, presence: true
  validates :access_token, presence: true, uniqueness: true
  validate :validate_srt_file

  before_validation :generate_access_token, on: :create

  SUPPORTED_LANGUAGES = {
    "pt-BR" => "Portugues (Brasil)",
    "pt-PT" => "Portugues (Portugal)",
    "es"    => "Espanol",
    "fr"    => "Frances",
    "de"    => "Alemao",
    "it"    => "Italiano",
    "ja"    => "Japones",
    "ko"    => "Coreano",
    "zh"    => "Chines"
  }.freeze

  AVAILABLE_MODELS = {
    "gpt-4.1-mini"               => "GPT-4.1 Mini (padrao)",
    "gemini-2.5-flash"           => "Gemini Flash (rapido)",
    "gpt-4.1"                    => "GPT-4.1 (premium)",
    "claude-sonnet-4-5-20250929" => "Claude Sonnet 4.5 (premium)",
    "claude-3-5-haiku-20241022"  => "Claude Haiku (premium rapido)"
  }.freeze

  def to_param
    access_token
  end

  def formatted_code
    "LEG-#{access_token.upcase}"
  end

  def cost_brl
    cost_user
  end

  private

  def generate_access_token
    return if access_token.present?
    5.times do
      self.access_token = SecureRandom.alphanumeric(8).upcase
      return unless self.class.exists?(access_token: access_token)
    end
    raise "Could not generate unique access token after 5 attempts"
  end

  def validate_srt_file
    return unless original_file.attached?
    unless original_file.filename.to_s.match?(/\.srt\z/i)
      errors.add(:original_file, "deve ser um arquivo .srt")
    end
    if original_file.byte_size > 5.megabytes
      errors.add(:original_file, "deve ter no maximo 5MB")
    end
  end
end
