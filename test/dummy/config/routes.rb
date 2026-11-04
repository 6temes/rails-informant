Rails.application.routes.draw do
  mount RailsInformant::Engine => "/informant"

  get "failures/raise_error", to: "failures#raise_error"
  get "failures/report_error", to: "failures#report_error"
end
