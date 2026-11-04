class AddBrowserCaptureToInformantTables < ActiveRecord::Migration[8.1]
  # up/down rather than change: a reversed `change` re-evaluates the guards
  # against the migrated schema, skips every step and leaves the columns behind.
  def up
    unless column_exists?(:informant_error_groups, :source)
      add_column :informant_error_groups, :source, :string, null: false, default: "server"
    end
    unless index_exists?(:informant_error_groups, [ :source, :status ])
      add_index :informant_error_groups, [ :source, :status ]
    end

    unless column_exists?(:informant_occurrences, :failing_request_id)
      add_column :informant_occurrences, :failing_request_id, :string
    end
    unless index_exists?(:informant_occurrences, :failing_request_id)
      add_index :informant_occurrences, :failing_request_id
    end

    unless column_exists?(:informant_occurrences, :request_id)
      add_column :informant_occurrences, :request_id, :string
    end
    unless index_exists?(:informant_occurrences, :request_id)
      add_index :informant_occurrences, :request_id
    end
  end

  def down
    remove_column :informant_occurrences, :request_id, if_exists: true
    remove_column :informant_occurrences, :failing_request_id, if_exists: true
    remove_index :informant_error_groups, [ :source, :status ], if_exists: true
    remove_column :informant_error_groups, :source, if_exists: true
  end
end
