class ExpireTranslationsJob < ApplicationJob
  queue_as :default

  def perform
    Translation.pending_payment
      .where("created_at < ?", 30.days.ago)
      .find_each do |translation|
        translation.expired!
        translation.original_file.purge if translation.original_file.attached?
      end
  end
end
