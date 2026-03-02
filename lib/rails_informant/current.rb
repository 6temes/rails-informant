module RailsInformant
  class Current < ActiveSupport::CurrentAttributes
    attribute :breadcrumbs, :request_context, :user_context, :custom_context
  end
end
