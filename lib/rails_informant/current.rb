module RailsInformant
  class Current < ActiveSupport::CurrentAttributes
    attribute :breadcrumbs, :user_context, :custom_context
  end
end
