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
end
