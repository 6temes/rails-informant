module RailsInformant
  class Occurrence < ApplicationRecord
    self.table_name = "informant_occurrences"

    API_FIELDS = %i[
      backtrace
      breadcrumbs
      created_at
      custom_context
      environment_context
      error_group_id
      exception_chain
      git_sha
      id
      request_context
      updated_at
      user_context
    ].freeze

    belongs_to :error_group, class_name: "RailsInformant::ErrorGroup", inverse_of: :occurrences
  end
end
