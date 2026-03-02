RailsInformant::Engine.routes.draw do
  namespace :api do
    resources :errors, only: [ :index, :show, :update, :destroy ] do
      member do
        post :fix_pending
        post :duplicate
      end
    end
    resources :occurrences, only: [ :index ]
    resource :status, only: [ :show ], controller: "status"
  end
end
