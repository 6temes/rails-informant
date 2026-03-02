module RailsInformant
  class BreadcrumbSubscriber
    NEEDS_FILTERING = %w[
      process_action.action_controller
      redirect_to.action_controller
      start_processing.action_controller
    ].to_set.freeze

    SUBSCRIPTIONS = {
      "cache_fetch_hit.active_support" => %i[key],
      "cache_read.active_support" => %i[key hit],
      "cache_write.active_support" => %i[key],
      "deliver.action_mailer" => %i[mailer],
      "halted_callback.action_controller" => %i[filter],
      "instantiation.active_record" => %i[record_count class_name],
      "perform.active_job" => %i[job],
      "perform_action.action_cable" => %i[channel_class action],
      "perform_start.active_job" => %i[job],
      "process_action.action_controller" => %i[controller action method path status],
      "redirect_to.action_controller" => %i[status location],
      "render_collection.action_view" => %i[identifier count],
      "render_partial.action_view" => %i[identifier],
      "render_template.action_view" => %i[identifier],
      "sql.active_record" => %i[name],
      "start_processing.action_controller" => %i[action controller format method path]
    }.freeze

    def self.subscribe!
      SUBSCRIPTIONS.each do |event_name, allowed_keys|
        message = event_name.split(".").first

        ActiveSupport::Notifications.subscribe(event_name) do |event|
          next unless RailsInformant.initialized?
          next if event_name == "sql.active_record" && (event.payload[:cached] || event.payload[:name] == "SCHEMA")

          filtered = event.payload.slice(*allowed_keys)
          filtered = ContextFilter.filter(filtered) if NEEDS_FILTERING.include?(event_name)
          if event_name == "redirect_to.action_controller" && filtered[:location]
            filtered[:location] = ContextBuilder.filtered_url filtered[:location]
          end
          BreadcrumbBuffer.current.record(
            category: event.name,
            message:,
            metadata: filtered,
            duration: event.duration.round(1)
          )
        end
      end
    end
  end
end
