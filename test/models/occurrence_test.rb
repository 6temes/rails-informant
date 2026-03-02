require "test_helper"

class RailsInformant::OccurrenceTest < ActiveSupport::TestCase
  test "belongs to error group" do
    group = create_error_group
    occurrence = group.occurrences.create!(
      backtrace: [ "/app/foo.rb:1" ],
      git_sha: "abc123"
    )

    assert_equal group, occurrence.error_group
  end

  test "destroying group destroys occurrences" do
    group = create_error_group
    group.occurrences.create!(backtrace: [ "/app/foo.rb:1" ])
    group.occurrences.create!(backtrace: [ "/app/bar.rb:2" ])

    assert_difference "RailsInformant::Occurrence.count", -2 do
      group.destroy!
    end
  end

  private

  def create_error_group
    RailsInformant::ErrorGroup.create!(
      fingerprint: SecureRandom.hex(8),
      error_class: "StandardError",
      message: "test",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
  end
end
