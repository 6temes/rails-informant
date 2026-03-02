module RailsInformant
  class Occurrence < ApplicationRecord
    self.table_name = "informant_occurrences"

    belongs_to :error_group, class_name: "RailsInformant::ErrorGroup"
  end
end
