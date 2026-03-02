module RailsInformant
  class BreadcrumbSubscriber
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
      "start_processing.action_controller" => %i[controller action params format method path]
    }.freeze

    def self.subscribe!
      SUBSCRIPTIONS.each do |event_name, allowed_keys|
        ActiveSupport::Notifications.subscribe(event_name) do |name, start, finish, _id, payload|
          next unless RailsInformant.initialized?

          filtered = payload.slice(*allowed_keys)
          BreadcrumbBuffer.current.record(
            category: name,
            message: name.split(".").first,
            metadata: filtered,
            duration: ((finish - start) * 1000).round(1)
          )
        end
      end
    end
  end
end
