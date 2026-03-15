class TranslateSubtitleJob < ApplicationJob
  queue_as :default

  def perform(translation_id)
    translation = Translation.find(translation_id)
    translation.processing!

    start_time = Time.current
    content = translation.original_file.download

    result = Legendator.translate_content(
      content,
      lang: translation.target_language,
      provider: :openrouter,
      model: translation.model_used
    )

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
  rescue => e
    translation.update!(status: :failed, error_message: e.message)
  end
end
