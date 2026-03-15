class Payment < ApplicationRecord
  belongs_to :translation

  enum :status, {
    pending: 0,
    confirmed: 1,
    failed: 2,
    refunded: 3
  }

  def expired?
    expires_at.present? && expires_at < Time.current
  end
end
