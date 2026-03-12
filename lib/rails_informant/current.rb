module RailsInformant
  class Current < ActiveSupport::CurrentAttributes
    attribute :breadcrumbs, :custom_context, :delivering_notification, :silenced, :user_context
  end
end
