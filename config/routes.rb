RailsInformant::Engine.routes.draw do
  # Checked per request: the host enables capture in an initializer, which
  # runs after the engine's routes are loaded.
  resources :browser_reports, only: :create, constraints: ->(_) { RailsInformant.capture_browser_errors }

  namespace :api do
    scope "v1" do
      resources :errors, only: [ :index, :show, :update, :destroy ] do
        member do
          patch :duplicate
          patch :fix_pending
        end
      end
      resource :deploy, only: [ :create ], controller: "deploys"
      resources :occurrences, only: [ :index ]
      resource :status, only: [ :show ], controller: "status"
    end
  end
end
