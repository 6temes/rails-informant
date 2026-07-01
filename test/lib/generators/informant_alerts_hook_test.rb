require "test_helper"
require "open3"
require "json"
require "tmpdir"
require "fileutils"

# Exercises the generated hook script by shelling out with a fake `curl` on PATH.
# jq is a hard dependency of the script, so the whole suite skips when it's absent.
class RailsInformant::InformantAlertsHookTest < ActiveSupport::TestCase
  HOOK_SCRIPT = File.expand_path(
    "../../../lib/generators/rails_informant/skill/templates/informant-alerts.sh",
    __dir__
  )

  setup do
    skip "jq is required to exercise the hook" unless system("command -v jq >/dev/null 2>&1")

    @tmpdir = Dir.mktmpdir
    @bin = File.join(@tmpdir, "bin")
    FileUtils.mkdir_p @bin
    @curl_sentinel = File.join(@tmpdir, "curl-called")
    @curl_response = File.join(@tmpdir, "curl-response.json")
    write_fake_curl
  end

  teardown do
    FileUtils.remove_entry @tmpdir if @tmpdir && File.directory?(@tmpdir)
  end

  test "suppresses the alert when the first prompt is /informant" do
    out, status = run_hook prompt: "/informant", session_id: "s-informant"

    assert_equal "", out.strip
    assert status.success?
    assert_not curl_called?, "should not request status when first prompt is /informant"
  end

  test "suppresses the alert for /informant with an environment argument" do
    out, _status = run_hook prompt: "/informant production", session_id: "s-informant-env"

    assert_equal "", out.strip
    assert_not curl_called?
  end

  test "emits the alert for a normal first prompt with unresolved errors" do
    set_response unresolved_count: 3, top_errors: [
      { error_class: "OpenSSL::SSL::SSLError", total_occurrences: 12 }
    ]

    out, status = run_hook prompt: "fix the checkout bug", session_id: "s-normal"

    assert status.success?
    assert_match "3 unresolved errors in production", out
    assert_match "OpenSSL::SSL::SSLError", out
    assert_match "Do NOT proceed", out
    assert curl_called?
  end

  test "does not treat a prefixed command like /informants as /informant" do
    set_response unresolved_count: 1, top_errors: []

    out, _status = run_hook prompt: "/informants are cool", session_id: "s-near-miss"

    assert_match "1 unresolved error", out
    assert curl_called?, "a near-miss prefix must still run the status check"
  end

  test "stays silent for the rest of the session after a first /informant prompt" do
    set_response unresolved_count: 4, top_errors: []

    first_out, _status = run_hook prompt: "/informant", session_id: "s-informant-then-work"
    second_out, _status = run_hook prompt: "implement feature X", session_id: "s-informant-then-work"

    assert_equal "", first_out.strip
    assert_equal "", second_out.strip
    assert_not curl_called?, "a later normal prompt must not re-check after /informant"
  end

  test "stays silent for a normal first prompt with zero unresolved errors" do
    set_response unresolved_count: 0

    out, _status = run_hook prompt: "hello", session_id: "s-zero"

    assert_equal "", out.strip
    assert curl_called?
  end

  test "runs at most once per session" do
    set_response unresolved_count: 2, top_errors: []

    first_out, _status = run_hook prompt: "start work", session_id: "s-once"
    reset_curl_sentinel
    second_out, _status = run_hook prompt: "keep going", session_id: "s-once"

    assert_match "2 unresolved errors", first_out
    assert_equal "", second_out.strip
    assert_not curl_called?, "second prompt in the same session should not re-check"
  end

  test "exits silently and writes no marker when env vars are missing" do
    out, status = run_hook prompt: "anything", session_id: "s-noenv",
      env: { "INFORMANT_PRODUCTION_URL" => nil, "INFORMANT_PRODUCTION_TOKEN" => nil }

    assert_equal "", out.strip
    assert status.success?
    assert_empty Dir.glob(File.join(@tmpdir, "rails-informant-alert-*"))
  end

  test "exits silently when the URL is not HTTPS" do
    out, _status = run_hook prompt: "anything", session_id: "s-http",
      env: { "INFORMANT_PRODUCTION_URL" => "http://insecure.example.com" }

    assert_equal "", out.strip
    assert_not curl_called?
  end

  private

  def run_hook(prompt:, session_id:, env: {})
    base_env = {
      "PATH" => "#{@bin}:#{ENV["PATH"]}",
      "TMPDIR" => @tmpdir,
      "INFORMANT_PRODUCTION_URL" => "https://app.example.com",
      "INFORMANT_PRODUCTION_TOKEN" => "test-token-00112233445566778899aabb",
      "CURL_SENTINEL" => @curl_sentinel,
      "CURL_RESPONSE" => @curl_response
    }.merge(env)

    payload = JSON.generate(session_id:, prompt:)
    out, _err, status = Open3.capture3 base_env, "bash", HOOK_SCRIPT, stdin_data: payload
    [ out, status ]
  end

  # A fake curl that records its invocation and returns the canned status body.
  def write_fake_curl
    fake = File.join(@bin, "curl")
    File.write fake, <<~CURL
      #!/usr/bin/env bash
      echo called >> "$CURL_SENTINEL"
      cat "$CURL_RESPONSE" 2>/dev/null || true
    CURL
    FileUtils.chmod 0o755, fake
    set_response unresolved_count: 0
  end

  def set_response(**payload)
    File.write @curl_response, JSON.generate(payload)
  end

  def curl_called?
    File.exist?(@curl_sentinel) && !File.zero?(@curl_sentinel)
  end

  def reset_curl_sentinel
    FileUtils.rm_f @curl_sentinel
  end
end
