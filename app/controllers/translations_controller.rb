class TranslationsController < ApplicationController
  def new
    @translation = Translation.new
  end

  def create
    @translation = Translation.new(translation_params)
    @translation.original_filename = params.dig(:translation, :original_file)&.original_filename

    if @translation.save
      content = @translation.original_file.download
      estimate = CostCalculator.new(model: @translation.model_used).estimate(content)
      @translation.update!(cost_user: estimate[:cost_user_brl])

      PixService.new.create_charge(@translation)

      redirect_to @translation
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @translation = find_translation!
  end

  def download
    translation = find_translation!

    if translation.completed? && translation.translated_file.attached?
      redirect_to rails_blob_path(translation.translated_file, disposition: "attachment")
    else
      redirect_to translation, alert: "Arquivo ainda nao esta pronto."
    end
  end

  def recover_form
  end

  def recover
    code = params[:code].to_s.strip.upcase.delete_prefix("LEG-")
    translation = Translation.find_by(access_token: code)

    if translation
      redirect_to translation
    else
      flash.now[:alert] = "Codigo nao encontrado. Verifique e tente novamente."
      render :recover_form
    end
  end

  private

  def translation_params
    params.require(:translation).permit(:original_file, :target_language, :model_used)
  end

  def find_translation!
    Translation.find_by!(access_token: params[:id])
  end
end
