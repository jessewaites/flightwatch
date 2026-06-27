Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  mount ActionCable.server => "/cable"

  get "credits", to: "static_pages#credits"
  get "evals", to: "static_pages#evals"
  post "mode", to: "dashboard#mode"
  post "synthesis", to: "dashboard#synthesis"
  get "anomalies", to: "dashboard#anomalies"
  root "dashboard#index"
end
