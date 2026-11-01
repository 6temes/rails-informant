module RailsInformant
  # One browser report, normalized at the boundary: every field comes from
  # the page and is attacker-controlled, so only allowlisted keys and types
  # are read, strings are capped and filtered, and identity comes only from
  # the verified render-time context.
  class BrowserReport
    # What the server vouched for when it rendered the page. Any field may be
    # nil, and the whole context is nil when the page sent none or it failed
    # verification.
    Context = Data.define(:rendered_at, :request_id, :revision, :user_context)

    BREADCRUMB_KEYS = %w[category duration message metadata timestamp].freeze
    MAX_BACKTRACE_LINE_LENGTH = 255
    MAX_BREADCRUMBS = 20
    MAX_MESSAGE_LENGTH = 1_000
    MAX_REQUEST_ID_LENGTH = 255
    NAME_PATTERN = /\A[A-Z][A-Za-z0-9_]{0,63}\z/

    attr_reader :context, :error, :error_class, :message, :page_path, :stack

    def initialize(report, context:, base_url:, remote_ip:, user_agent:)
      @report = report
      @context = context
      @remote_ip = remote_ip
      @user_agent = user_agent

      @name = string(report["name"])
      @error_class = "JS::#{NAME_PATTERN.match?(@name) ? @name : "Error"}"
      @message = string(report["message"]).truncate(MAX_MESSAGE_LENGTH)
      @stack = JavascriptStack.parse(string(report["stack"]), origin: base_url)
      @page_url = string(report["url"]).presence
      @page_path = page_path_of(@page_url)
      @error = BrowserError.new(message, backtrace:, name: @name)
    end

    def group_attributes(now:)
      {
        controller_action: nil,
        created_at: now,
        error_class:,
        first_backtrace_line:,
        first_seen_at: now,
        job_class: nil,
        last_seen_at: now,
        message:,
        severity: "error",
        source: "browser",
        total_occurrences: 1,
        updated_at: now
      }
    end

    def occurrence_attributes
      {
        backtrace: error.backtrace,
        breadcrumbs:,
        environment_context: ContextBuilder.build_environment_context,
        failing_request_id: string(report["failing_request_id"]).first(MAX_REQUEST_ID_LENGTH).presence,
        git_sha: context&.revision,
        request_context: ContextFilter.filter(ip: remote_ip, url: page_url && ContextBuilder.filtered_url(page_url), user_agent:),
        request_id: context&.request_id,
        user_context: ContextFilter.filter(context&.user_context)
      }
    end

    private

    attr_reader :name, :page_url, :remote_ip, :report, :user_agent

    # V8 starts error.stack with the error's own "Name: message" line, which
    # is not a frame and would otherwise show up as the top of the backtrace.
    def backtrace
      lines = stack.backtrace
      lines = lines.drop(1) if v8_header?(lines.first)
      ContextFilter.filter_backtrace(lines)
    end

    def v8_header?(line)
      name.present? && (line == name || line&.start_with?("#{name}:"))
    end

    def breadcrumbs
      Array(report["breadcrumbs"]).grep(Hash).first(MAX_BREADCRUMBS).map { ContextFilter.filter(it.slice(*BREADCRUMB_KEYS)) }
    end

    def first_backtrace_line
      (stack.first_app_frame || stack.frames.first)&.to_s&.first(MAX_BACKTRACE_LINE_LENGTH)
    end

    def page_path_of(url)
      URI.parse(url).path.presence if url
    rescue URI::InvalidURIError
      nil
    end

    def string(value)
      value.is_a?(String) ? value : ""
    end
  end
end
