require "uri"

module RailsInformant
  class JavascriptStack
    ANONYMOUS = "<anonymous>"
    ANONYMOUS_NAMES = [ "", ANONYMOUS, "global code", "module code" ].freeze
    APP_SOURCE_PREFIX = "app/javascript/"
    # Same rule as Propshaft::Asset.extract_path_and_digest, which only exists when the host loads Propshaft.
    DIGEST_PATTERN = /-([0-9a-zA-Z]{7,128})\.(?!digested)(?:[^.]|\.map)+\z/
    FIREFOX_FRAME = /\A\s*(?<function>[^@]*)@(?<url>.+):(?<line>\d+):(?<column>\d+)\z/
    MAX_FRAMES = 50
    V8_FRAME = /\A\s*at (?:(?<function>.+?) \()?(?<url>\S+?):(?<line>\d+):(?<column>\d+)\)?\z/

    Frame = Data.define(:app, :column, :function, :line, :path) do
      alias_method :app?, :app

      def fingerprint_key = "#{path}:#{function}"

      def to_s = "#{path}:#{line}:#{column}:in '#{function}'"
    end

    def self.parse(stack, origin:) = new(stack, origin:)

    def self.normalize_function(name)
      name = name.to_s.strip.delete_prefix("async ").delete_prefix("new ")
      return ANONYMOUS if name.include?("/<")

      name = name.split(".").last.to_s.delete("*")
      ANONYMOUS_NAMES.include?(name) ? ANONYMOUS : name
    end

    attr_reader :backtrace, :frames

    def initialize(stack, origin:)
      @origin = origin
      lines = stack.to_s.lines(chomp: true).reject(&:blank?).first(MAX_FRAMES)
      entries = lines.map { parse_line(it) || it }
      @frames = entries.grep(Frame)
      @backtrace = entries.map(&:to_s)
    end

    def first_app_frame = frames.find(&:app?)

    private

    attr_reader :origin

    def parse_line(line)
      match = V8_FRAME.match(line) || FIREFOX_FRAME.match(line)
      return unless match

      path, app = resolve(match[:url])
      Frame.new app:, column: match[:column].to_i, function: self.class.normalize_function(match[:function]), line: match[:line].to_i, path:
    end

    # A stack repeats the same few script URLs, and each miss costs an asset
    # lookup, so misses are cached too.
    def resolve(url)
      (@_resolved ||= {})[url] ||= begin
        source = app_source_for(url)
        source ? [ source, source.start_with?(APP_SOURCE_PREFIX) ] : [ url, false ]
      end
    end

    def app_source_for(url)
      uri = URI.parse(url)
      return unless uri.is_a?(URI::HTTP) && origin_of(uri) == origin

      asset = find_asset(uri.path)
      relative = asset&.path.to_s.delete_prefix("#{Rails.root}/")
      relative if asset && relative != asset.path.to_s
    rescue URI::InvalidURIError
      nil
    end

    def find_asset(url_path)
      assets = Rails.application.assets
      return unless assets.respond_to?(:load_path)

      prefix = "#{Rails.application.config.assets.prefix.chomp("/")}/"
      return unless url_path.start_with?(prefix)

      digested = url_path.delete_prefix(prefix)
      digest = digested[DIGEST_PATTERN, 1]
      assets.load_path.find(digest ? digested.sub("-#{digest}", "") : digested)
    end

    def origin_of(uri)
      port = ":#{uri.port}" unless uri.port == uri.default_port
      "#{uri.scheme}://#{uri.host}#{port}"
    end
  end
end
