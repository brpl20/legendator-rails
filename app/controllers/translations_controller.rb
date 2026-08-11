class TranslationsController < ApplicationController
  def new
    @translation = Translation.new
  end

  def create
    @translation = Translation.new(translation_params)
    upload = params.dig(:translation, :original_file)
    @translation.original_filename = upload&.original_filename

    # Measure before charging. A flat price on an unbounded file is a standing
    # invitation to upload five movies at once and pay the minimum for them.
    content = read_upload(upload)

    if content.nil?
      @translation.errors.add(:original_file, "e obrigatorio")
      return render :new, status: :unprocessable_entity
    end

    measurement = SrtSizeGate.new(content).measure

    unless measurement.ok?
      @translation.errors.add(:original_file, measurement.reason)
      return render :new, status: :unprocessable_entity
    end

    if @translation.save
      estimate = CostCalculator.new(model: @translation.model_used).estimate(content)
      @translation.update!(
        cost_user: estimate[:cost_user_brl],
        subtitle_count: measurement.subtitles
      )

      apply_preview(@translation, content)
      PixService.new.create_charge(@translation)

      redirect_to @translation
    else
      render :new, status: :unprocessable_entity
    end
  end

  # The customer can refine the context right up until they pay — that is the
  # whole point of showing them what we detected.
  def update_context
    translation = find_translation!

    unless translation.pending_payment?
      return redirect_to translation, alert: "A traducao ja comecou, nao da mais para mudar o contexto."
    end

    if translation.update(context: params.dig(:translation, :context))
      redirect_to translation, notice: "Contexto atualizado."
    else
      redirect_to translation, alert: translation.errors.full_messages.to_sentence
    end
  end

  def show
    @translation = find_translation!

    if @translation.pending_payment? && @translation.payment&.pending?
      PixService.new.check_payment(@translation.payment)
      @translation.reload
    end
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

  def simulate_payment
    raise ActionController::RoutingError, "Not Found" unless Rails.env.development? || Rails.env.test?

    translation = find_translation!
    if translation.pending_payment? && translation.payment
      translation.payment.update!(status: :confirmed, paid_at: Time.current)
      translation.paid!
      TranslateSubtitleJob.perform_later(translation.id)
      redirect_to translation, notice: "Pagamento simulado com sucesso!"
    else
      redirect_to translation, alert: "Nao foi possivel simular o pagamento."
    end
  end

  private

  def translation_params
    params.require(:translation).permit(:original_file, :target_language, :model_used, :context)
  end

  # Best-effort: a failed preview must never cost us the sale, so anything that
  # goes wrong here is swallowed and the customer just sees no summary.
  def apply_preview(translation, content)
    preview = SrtPreview.new(content, model: translation.model_used).call
    return unless preview.ok?

    translation.update(
      detected_title: preview.title,
      detected_summary: preview.summary,
      context: translation.context.presence || preview.suggested_context
    )
  rescue StandardError => e
    Rails.logger.warn("[TranslationsController] preview skipped for #{translation.id}: #{e.class}: #{e.message}")
  end

  # The upload is still an IO here — the blob is not in the storage service
  # until after save, so this is the only place the bytes are readable.
  def read_upload(upload)
    return nil unless upload.respond_to?(:read)
    content = upload.read
    upload.rewind
    content
  end

  def find_translation!
    Translation.find_by!(access_token: params[:id])
  end
end
