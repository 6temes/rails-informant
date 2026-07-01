require "digest"
require "fileutils"
require "json"
require "pathname"
require "rails_informant/claude_integration_content"

module RailsInformant
  # Classifies the host app's committed Claude Code integration by comparing its
  # live .claude/ files against what the installed gem would generate now. The
  # detection primitive behind the three drift channels (boot warning, doctor,
  # hook nudge); Rails-boot-independent and unit-testable in isolation.
  #
  # Internals may raise (missing gem spec, unreadable templates); each channel
  # wraps a single top-level rescue so a drift check never breaks boot or CI.
  # The one exception is #write_drift_flag, which is best-effort by nature and
  # swallows its own IO failures.
  class Integration
    Content = ClaudeIntegrationContent

    DRIFT_FLAG = "rails-informant-drift"

    # Fixed order so the digest is deterministic across runs.
    COMPONENTS = %w[hook mcp settings skill].freeze

    def initialize(app_root: Rails.root)
      @app_root = Pathname(app_root)
    end

    # :not_installed | :current | :stale | :error
    #
    # not_installed wins first so apps that use the gem only for error capture
    # are never nagged. error (a present-but-unparseable settings.json/.mcp.json)
    # is distinct from stale because re-running the generator skips unparseable
    # files — it could never clear a stale reported on one.
    def status
      return :not_installed unless installed?
      return :error if json_error?

      live_digest == expected_digest ? :current : :stale
    end

    def installed?
      hook_script_present? || settings_informant_present? || mcp_informant_present?
    end

    def stale?
      status == :stale
    end

    # Display only — the drift decision uses the digest, not the version. Harmless
    # that local path/git installs report 0.0.0.dev here; only published installs
    # show a real number.
    def gem_version
      Gem.loaded_specs["rails-informant"]&.version&.to_s
    end

    def drift_flag_path
      @app_root.join "tmp", DRIFT_FLAG
    end

    # Best-effort: the Ruby channels refresh this flag so the bash hook can read
    # drift without loading Ruby. Never raises out — a read-only tmp/ must not
    # break a dev boot or a doctor run.
    def write_drift_flag(stale:)
      if stale
        FileUtils.mkdir_p drift_flag_path.dirname
        drift_flag_path.write "The Claude Code integration is out of date. " \
          "Run `bin/rails g rails_informant:skill` to update it.\n"
      elsif drift_flag_path.exist?
        drift_flag_path.delete
      end
    rescue SystemCallError
      nil
    end

    private

    def hook_path = @app_root.join(Content::HOOK_SCRIPT_PATH)
    def skill_path = @app_root.join(Content::SKILL_PATH)
    def settings_path = @app_root.join(Content::SETTINGS_PATH)
    def mcp_path = @app_root.join(Content::MCP_PATH)

    def hook_script_present? = hook_path.exist?

    def settings_informant_present?
      registrations = live_settings_registrations
      registrations && !registrations.empty?
    end

    def mcp_informant_present?
      !live_mcp_entry.nil?
    end

    def json_error?
      parse_failed?(settings_path) || parse_failed?(mcp_path)
    end

    # --- digest -------------------------------------------------------------

    def expected_digest
      digest_of(
        "hook" => normalize_text(Content.hook_script),
        "skill" => normalize_text(Content.skill_markdown),
        "settings" => canonical_json(Content.expected_registrations),
        "mcp" => canonical_json(Content.mcp_entry)
      )
    end

    def live_digest
      digest_of(
        "hook" => normalize_text(read_or_empty(hook_path)),
        "skill" => normalize_text(read_or_empty(skill_path)),
        "settings" => canonical_json(live_settings_registrations || {}),
        "mcp" => canonical_json(live_mcp_entry || {})
      )
    end

    def digest_of(components)
      material = COMPONENTS.map { |name| "#{name}:#{components[name]}" }.join("\n")
      Digest::SHA256.hexdigest material
    end

    # --- live extraction ----------------------------------------------------

    # The informant-owned hook registrations, keyed by event, swept from every
    # event key by script path. nil when settings.json is absent or unparseable.
    def live_settings_registrations
      settings = parsed_json(settings_path) or return nil
      hooks = settings["hooks"]
      return {} unless hooks.is_a?(Hash)

      hooks.each_with_object({}) do |(event, entries), result|
        next unless entries.is_a?(Array)

        informant = entries.select { |entry| Content.informant_hook_entry?(entry) }
        result[event] = informant unless informant.empty?
      end
    end

    # The informant server entry from .mcp.json, or nil when absent/unparseable.
    def live_mcp_entry
      mcp = parsed_json(mcp_path) or return nil
      mcp.dig "mcpServers", "informant"
    end

    # --- json / text helpers ------------------------------------------------

    # Read and parse each JSON file at most once per instance. Instances are
    # created fresh per channel call, so this both removes the redundant reads
    # and lets installed?/json_error?/the digest classify from one consistent
    # snapshot (no split read where one path sees the file valid and another a
    # concurrent edit).
    def json_state(path)
      @_json_states ||= {}
      @_json_states[path] ||= compute_json_state(path)
    end

    def compute_json_state(path)
      return [ :absent, nil ] unless path.exist?

      [ :ok, JSON.parse(path.read) ]
    rescue JSON::ParserError
      [ :error, nil ]
    end

    def parsed_json(path)
      state, data = json_state(path)
      state == :ok ? data : nil
    end

    def parse_failed?(path)
      json_state(path).first == :error
    end

    def read_or_empty(path)
      path.exist? ? path.read : ""
    end

    # Canonical JSON: recursively sort hash keys so a host-side key reorder in a
    # JSON fragment does not read as drift.
    def canonical_json(object)
      JSON.generate deep_sort(object)
    end

    def deep_sort(object)
      case object
      when Hash then object.keys.sort.each_with_object({}) { |key, sorted| sorted[key] = deep_sort(object[key]) }
      when Array then object.map { |element| deep_sort(element) }
      else object
      end
    end

    # Strip a leading BOM, normalize line endings, and trim trailing whitespace so
    # host-side encoding noise (CRLF via .gitattributes, an EditorConfig
    # trim/final-newline rule, a BOM-prepending editor) does not byte-diverge into
    # a permanent stale. Content reformatting (reindentation, blank-line collapse)
    # is intentionally out of scope — it would risk masking real drift.
    def normalize_text(text)
      text.delete_prefix("\uFEFF").gsub(/\r\n?/, "\n").split("\n", -1).map(&:rstrip).join("\n").sub(/\n+\z/, "")
    end
  end
end
