require "test_helper"

class RailsInformantTest < ActiveSupport::TestCase
  test "browser_schema_ready? is true when the browser capture columns exist" do
    assert RailsInformant.browser_schema_ready?
  end

  test "browser_schema_ready? is false when any browser capture column is missing" do
    RailsInformant::Occurrence.stubs(:column_names).returns(%w[id error_group_id request_id])

    assert_not RailsInformant.browser_schema_ready?
  end

  test "reset_caches! re-checks the schema" do
    assert RailsInformant.browser_schema_ready?
    RailsInformant::ErrorGroup.stubs(:column_names).returns(%w[id fingerprint])

    assert RailsInformant.browser_schema_ready?, "the result is memoized"
    RailsInformant.reset_caches!
    assert_not RailsInformant.browser_schema_ready?
  end
end
