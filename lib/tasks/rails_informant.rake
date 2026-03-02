namespace :informant do
  desc "Purge resolved errors older than retention_days"
  task purge: :environment do
    RailsInformant::PurgeJob.perform_now
    puts "Purge complete"
  end

  desc "Show error monitoring statistics"
  task stats: :environment do
    groups = RailsInformant::ErrorGroup
    total = groups.count
    unresolved = groups.where(status: "unresolved").count
    fix_pending = groups.where(status: "fix_pending").count
    resolved = groups.where(status: "resolved").count
    ignored = groups.where(status: "ignored").count
    duplicates = groups.where(status: "duplicate").count
    occurrences = RailsInformant::Occurrence.count

    puts "Rails Informant Statistics"
    puts "-" * 30
    puts "Error groups:    #{total}"
    puts "  Unresolved:    #{unresolved}"
    puts "  Fix pending:   #{fix_pending}"
    puts "  Resolved:      #{resolved}"
    puts "  Ignored:       #{ignored}"
    puts "  Duplicates:    #{duplicates}"
    puts "Occurrences:     #{occurrences}"
    puts "Deploy SHA:      #{RailsInformant.current_git_sha || 'unknown'}"
  end
end
