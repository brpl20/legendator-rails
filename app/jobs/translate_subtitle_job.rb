class TranslateSubtitleJob < ApplicationJob
  queue_as :default

  # Retry on transient AI failures (after gem-level retries + model fallback are
  # exhausted). On the final attempt the block runs instead of re-raising, so the
  # record lands in :failed — otherwise it stays :processing forever and the show
  # page, which meta-refreshes every 5s while processing, spins with no end.
  retry_on Legendator::TranslationError, wait: :polynomially_longer, attempts: 3 do |job, error|
    mark_failed(job.arguments.first, error)
  end
  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 30.seconds, attempts: 3 do |job, error|
    mark_failed(job.arguments.first, error)
  end

  # Don't retry on permanent failures
  discard_on ActiveJob::DeserializationError

  def self.mark_failed(translation_id, error)
    translation = Translation.find_by(id: translation_id)
    return unless translation

    Rails.logger.error("[TranslateSubtitleJob] giving up on translation #{translation_id}: #{error.class}: #{error.message}")
    translation.update!(status: :failed, error_message: error.message)
  end

  def perform(translation_id)
    translation = Translation.find(translation_id)
    translation.processing! unless translation.processing?

    start_time = Time.current
    content = translation.original_file.download

    result = Legendator.translate_content(
      content,
      lang: translation.target_language,
      model: translation.model_used,
      context: translation.context.presence
    )

    if result.consistency && !result.consistency.pass?
      translation.update!(
        status: :failed,
        error_message: "Consistency check failed: #{result.consistency.errors.join('; ')}"
      )
      return
    end

    costs = CostCalculator.new(model: translation.model_used).calculate(
      result.cost,
      input_tokens: result.token_usage[:input_tokens],
      output_tokens: result.token_usage[:output_tokens]
    )

    filename = translation.original_filename.sub(/\.srt\z/i, "_#{translation.target_language}.srt")
    translation.translated_file.attach(
      io: StringIO.new(result.srt_content),
      filename: filename,
      content_type: "text/plain"
    )

    translation.update!(
      status: :completed,
      subtitle_count: result.coverage[:total_subtitles],
      tokens_input: result.token_usage[:input_tokens],
      tokens_output: result.token_usage[:output_tokens],
      cost_ai: result.cost,
      cost_ai_brl: costs[:cost_brl],
      processing_time: (Time.current - start_time).to_f
    )
  rescue Legendator::TranslationError, Net::OpenTimeout, Net::ReadTimeout
    # Let retry_on handle these — re-raise so ActiveJob sees them
    raise
  rescue => e
    Rails.logger.error("[TranslateSubtitleJob] Permanent failure for translation #{translation_id}: #{e.message}")
    translation.update!(status: :failed, error_message: e.message)
  end
end
