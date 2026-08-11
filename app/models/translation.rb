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

  # Free-text guidance the user can give the translator: character name
  # translations, tone, setting. Capped so it cannot become a prompt-sized
  # payload of its own.
  MAX_CONTEXT_LENGTH = 1_000

  validates :original_filename, presence: true
  validates :target_language, presence: true
  validates :access_token, presence: true, uniqueness: true
  validates :context, length: { maximum: MAX_CONTEXT_LENGTH }
  validate :validate_srt_file

  # Inclusion checks only on create: existing rows may carry a retired slug or
  # language and must stay updatable — the job writes status and token counts
  # back to them after translating.
  validates :target_language, inclusion: { in: SUPPORTED_LANGUAGES.keys }, on: :create
  validates :model_used, inclusion: { in: ->(_) { AiModel.slugs } }, on: :create

  before_validation :generate_access_token, on: :create

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
