class CreateInformantTables < ActiveRecord::Migration[8.1]
  def change
    create_table :informant_error_groups do |t|
      t.string :fingerprint, null: false, index: { unique: true }
      t.string :error_class, null: false
      t.text :message
      t.string :severity, default: "error"
      t.string :status, default: "unresolved", null: false
      t.string :first_backtrace_line
      t.string :controller_action
      t.string :job_class
      t.integer :total_occurrences, default: 0, null: false
      t.references :duplicate_of, foreign_key: { to_table: :informant_error_groups }
      t.string :fix_sha
      t.string :original_sha
      t.string :fix_pr_url
      t.text :notes
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :resolved_at
      t.datetime :fix_deployed_at
      t.datetime :last_notified_at
      t.timestamps

      t.index [ :status, :last_seen_at ]
      t.index [ :status, :resolved_at ]
      t.index [ :error_class ]
    end

    add_check_constraint :informant_error_groups,
      "duplicate_of_id IS NULL OR duplicate_of_id != id",
      name: "check_no_self_duplicate"

    create_table :informant_occurrences do |t|
      t.references :error_group, null: false,
        foreign_key: { to_table: :informant_error_groups }
      t.jsonb :backtrace
      t.jsonb :exception_chain
      t.jsonb :request_context
      t.jsonb :user_context
      t.jsonb :custom_context
      t.jsonb :environment_context
      t.jsonb :breadcrumbs
      t.string :git_sha
      t.timestamps

      t.index [ :error_group_id, :created_at ]
      t.index :created_at
    end
  end
end
