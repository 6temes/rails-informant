RailsInformant::Engine.routes.draw do
  namespace :api do
    scope "v1" do
      resources :errors, only: [ :index, :show, :update, :destroy ] do
        member do
          patch :duplicate
          patch :fix_pending
        end
      end
      resources :occurrences, only: [ :index ]
      resource :status, only: [ :show ], controller: "status"
    end
  end
end
