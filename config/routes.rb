Rails.application.routes.draw do
  root "pages#home"

  resources :translations, only: [:new, :create, :show] do
    member do
      get :download
    end
  end

  get "recover", to: "translations#recover_form"
  post "recover", to: "translations#recover"

  post "webhooks/pix", to: "webhooks#pix"

  if Rails.env.development? || Rails.env.test?
    post "translations/:id/simulate_payment", to: "translations#simulate_payment", as: :simulate_payment
    get "translations-dev/new", to: "dev_translations#new", as: :dev_translation_new
    post "translations-dev", to: "dev_translations#create", as: :dev_translation
  end
end
