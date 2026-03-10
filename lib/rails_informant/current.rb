module RailsInformant
  class Current < ActiveSupport::CurrentAttributes
    attribute :breadcrumbs, :custom_context, :delivering_notification, :user_context
  end
end
