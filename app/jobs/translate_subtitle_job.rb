class TranslateSubtitleJob < ApplicationJob
  queue_as :default

  # Retry on transient AI provider failures (after gem-level retries + fallback are exhausted)
  retry_on Legendator::TranslationError, wait: :polynomially_longer, attempts: 3
  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 30.seconds, attempts: 3

  # Don't retry on permanent failures
  discard_on ActiveJob::DeserializationError

  def perform(translation_id)
    translation = Translation.find(translation_id)
    translation.processing! unless translation.processing?

    start_time = Time.current
    content = translation.original_file.download

    result = Legendator.translate_content(
      content,
      lang: translation.target_language,
      provider: :openrouter,
      model: translation.model_used
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
