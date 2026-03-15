require "rails_helper"

RSpec.describe ExpireTranslationsJob, type: :job do
  describe "#perform" do
    it "expires pending_payment translations older than 30 days" do
      old = create(:translation, status: :pending_payment, created_at: 31.days.ago)
      old.original_file.attach(
        io: StringIO.new("content"),
        filename: "old.srt",
        content_type: "text/plain"
      )

      ExpireTranslationsJob.perform_now

      old.reload
      expect(old).to be_expired
      expect(old.original_file).not_to be_attached
    end

    it "does not expire recent pending_payment translations" do
      recent = create(:translation, status: :pending_payment, created_at: 1.day.ago)

      ExpireTranslationsJob.perform_now

      expect(recent.reload).to be_pending_payment
    end

    it "does not expire completed translations" do
      completed = create(:translation, status: :completed, created_at: 60.days.ago)

      ExpireTranslationsJob.perform_now

      expect(completed.reload).to be_completed
    end
  end
end
