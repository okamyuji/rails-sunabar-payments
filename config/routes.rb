Rails.application.routes.draw do
  get "up" => "rails/health#show", :as => :rails_health_check

  namespace :api do
    post "accounts/sync", to: "accounts#sync"
    resources :accounts, only: %i[index show]
    resources :virtual_accounts, only: %i[index create]
    resources :transfers, only: %i[index show create]
    post "reconciliations/run", to: "reconciliations#run"
    get "metrics", to: "metrics#show"
  end

  namespace :admin do
    get "/", to: "dashboard#show"
    resources :transfers, only: %i[index show]
    resources :invoices
    resources :reconciliations, only: [:index]
    resources :outbox_events, only: %i[index show]
  end
end
