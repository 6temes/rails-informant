module RailsInformant
  class Current < ActiveSupport::CurrentAttributes
    attribute :breadcrumbs, :browser_group_limit_logged, :custom_context, :delivering_notification, :ingesting_browser_report, :silenced, :user_context
  end
end
