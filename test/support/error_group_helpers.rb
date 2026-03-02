module ErrorGroupHelpers
  private

  def create_error_group(**attrs)
    defaults = {
      fingerprint: SecureRandom.hex(8),
      error_class: "StandardError",
      message: "test error",
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      total_occurrences: 1
    }
    RailsInformant::ErrorGroup.create!(**defaults.merge(attrs))
  end

  def build_error_group(**attrs)
    defaults = {
      fingerprint: SecureRandom.hex(8),
      error_class: "StandardError",
      message: "test error",
      first_seen_at: Time.current,
      last_seen_at: Time.current,
      total_occurrences: 1
    }
    RailsInformant::ErrorGroup.new(**defaults.merge(attrs))
  end

  def create_error_group_with_occurrence(**attrs)
    group = create_error_group(**attrs)
    create_occurrence error_group: group, backtrace: [ "/app/foo.rb:1" ]
    group
  end

  def create_occurrence(error_group:, **attrs)
    defaults = {
      backtrace: [ "/app/test.rb:1:in 'test'" ]
    }
    error_group.occurrences.create!(**defaults.merge(attrs))
  end
end
