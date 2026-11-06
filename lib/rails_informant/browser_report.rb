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

    ABORTED_FETCH = "aborted_fetch"
    ABORTED_FETCH_NOTES = "Auto-ignored: JS::AbortError is an aborted fetch, not an app defect. Reopen to get notified."
    ABORT_ERROR_CLASS = "JS::AbortError"
    BREADCRUMB_KEYS = %w[category duration message metadata timestamp].freeze
    URL_BREADCRUMB_CATEGORIES = %w[fetch.error turbo.visit].freeze
    MAX_BACKTRACE_LINE_LENGTH = 255
    MAX_BREADCRUMBS = 20
    MAX_MESSAGE_LENGTH = 1_000
    MAX_REQUEST_ID_LENGTH = 255
    MAX_STACK_LENGTH = 20_000
    NAME_PATTERN = /\A[A-Z][A-Za-z0-9_]{0,63}\z/
    THIRD_PARTY = "third_party"
    THIRD_PARTY_NOTES = "Auto-ignored: no frame from this app's own JavaScript, so the error came from an extension or injected script. Reopen to get notified."
    SILENCED_NOTES = { ABORTED_FETCH => ABORTED_FETCH_NOTES, THIRD_PARTY => THIRD_PARTY_NOTES }.freeze

    attr_reader :context, :error, :error_class, :message, :page_path, :silenced_reason, :stack

    def initialize(report, context:, base_url:, remote_ip:, user_agent:)
      @report = report
      @context = context
      @remote_ip = remote_ip
      @user_agent = user_agent

      @name = string(report["name"])
      @error_class = "JS::#{NAME_PATTERN.match?(@name) ? @name : "Error"}"
      @message = string(report["message"]).truncate(MAX_MESSAGE_LENGTH)
      @stack = JavascriptStack.parse(string(report["stack"]).first(MAX_STACK_LENGTH), origin: base_url)
      @page_url = string(report["url"]).split("#").first.presence
      @page_path = ContextBuilder.page_path(@page_url)
      @error = BrowserError.new(message, backtrace:, name: @name)
      @silenced_reason = classify(string(report["kind"]))
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
      }.merge(silenced_attributes)
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

    def backtrace
      ContextFilter.filter_backtrace(stack_lines.map { it.first(MAX_BACKTRACE_LINE_LENGTH) })
    end

    # V8 starts error.stack with the error's own "Name: message" line, which
    # is not a frame and would otherwise show up as the top of the backtrace.
    def stack_lines
      @_stack_lines ||= begin
        lines = stack.backtrace
        v8_header?(lines.first) ? lines.drop(1) : lines
      end
    end

    def v8_header?(line)
      name.present? && (line == name || line&.start_with?("#{name}:"))
    end

    def breadcrumbs
      @_breadcrumbs ||= Array(report["breadcrumbs"]).grep(Hash).first(MAX_BREADCRUMBS).map do |crumb|
        crumb = ContextFilter.filter(crumb.slice(*BREADCRUMB_KEYS))
        if URL_BREADCRUMB_CATEGORIES.include?(crumb["category"]) && crumb["message"].is_a?(String)
          crumb["message"] = ContextBuilder.filtered_url(crumb["message"])
        end
        crumb
      end
    end

    def classify(kind)
      return ABORTED_FETCH if error_class == ABORT_ERROR_CLASS

      return THIRD_PARTY if stack.frames.any? && stack.frames.none? { first_party?(it) }
      return if stack.frames.any?

      # A frameless rejection or Turbo report carries no source, so only an
      # error event with no stack at all says the code was not the page's.
      THIRD_PARTY if stack_lines.any? || (stack.backtrace.empty? && kind == "error")
    end

    # Extensions and in-app browsers inject inline scripts that report line 1
    # of the page they were injected on, which can be a page visited earlier.
    def first_party?(frame)
      frame.same_origin? && !(frame.line == 1 && page_paths.include?(ContextBuilder.page_path(frame.path)))
    end

    def page_paths
      @_page_paths ||= begin
        visits = breadcrumbs.select { it["category"] == "turbo.visit" && it["message"].is_a?(String) }
        [ page_path, *visits.map { ContextBuilder.page_path(it["message"]) } ].compact
      end
    end

    def silenced_attributes
      silenced_reason ? { notes: SILENCED_NOTES.fetch(silenced_reason), status: "ignored" } : {}
    end

    def first_backtrace_line
      (stack.first_app_frame || stack.frames.first)&.to_s&.first(MAX_BACKTRACE_LINE_LENGTH)
    end

    def string(value)
      value.is_a?(String) ? value : ""
    end
  end
end
