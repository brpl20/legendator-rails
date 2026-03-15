class TranslateSubtitleJob < ApplicationJob
  queue_as :default

  def perform(translation_id)
    # Will be implemented in Task 8
  end
end
