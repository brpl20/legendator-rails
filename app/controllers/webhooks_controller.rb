class WebhooksController < ApplicationController
  skip_forgery_protection

  def pix
    pix_data = params.permit(:txid, :valor, :horario).to_h.symbolize_keys

    unless pix_data[:txid].present?
      head :bad_request
      return
    end

    if PixService.new.confirm_payment(pix_data)
      head :ok
    else
      head :not_found
    end
  end
end
