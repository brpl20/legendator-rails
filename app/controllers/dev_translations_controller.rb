class DevTranslationsController < ApplicationController
  before_action :ensure_dev!

  def new
    @translation = Translation.new
  end

  def create
    @translation = Translation.new(translation_params)
    @translation.original_filename = params.dig(:translation, :original_file)&.original_filename

    if @translation.save
      content = @translation.original_file.download
      estimate = CostCalculator.new(model: @translation.model_used).estimate(content)
      @translation.update!(cost_user: estimate[:cost_user_brl], status: :paid)
      TranslateSubtitleJob.perform_later(@translation.id)
      redirect_to @translation, notice: "Traducao enviada (dev mode). Estimativa: R$ #{"%.2f" % estimate[:cost_user_brl]} | ~#{estimate[:estimated_tokens][:total]} tokens"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def translation_params
    params.require(:translation).permit(:original_file, :target_language, :model_used)
  end

  def ensure_dev!
    raise ActionController::RoutingError, "Not Found" unless Rails.env.development? || Rails.env.test?
  end
end
