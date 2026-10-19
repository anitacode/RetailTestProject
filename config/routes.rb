Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :products, only: [:index, :show]
  resources :stores, only: [:index, :show]
  resources :brands, only: [:index, :show]
  get "/alerts", to: "alerts_app#index"
  get "/alerts/settings/:contact_id", to: "alerts_app#index"
  get "/alerts/:id", to: "alerts_app#index"
  namespace :api do
    resources :tracking_events, only: [:index]
    resources :contacts, only: [:index, :show, :create, :update]
    resources :queued_jobs, only: [:index] do
      post "retry", on: :member, action: :retry_job
    end
    resource :session, only: [:show, :create, :destroy], controller: :sessions
    resources :alerts, only: [:index, :show] do
      patch :seen, on: :member
    end
  end

  # Defines the root path route ("/")
  root "stores#index"
end
