module RailsInformant
  # The render-time context a page echoes back in its reports. Encrypted, not
  # just signed, so user details stay unreadable in page HTML that third-party
  # scripts or cached copies can see.
  module BrowserContext
    IDENTITY_TTL = 24.hours
    PURPOSE = :browser_report

    class << self
      def generate(request)
        encryptor.encrypt_and_sign({
          "rendered_at" => Time.current.iso8601(6),
          "request_id" => request.request_id,
          "revision" => RailsInformant.current_git_sha,
          "user_context" => ContextBuilder.build_user_context(request.env)
        }, purpose: PURPOSE)
      end

      # The message has no expiry so a long-open tab still supplies its render
      # time and revision, which keep a stale page from reopening a fixed
      # group; only the identity parts age out.
      def verify(blob)
        return unless blob.is_a?(String)

        payload = encryptor.decrypt_and_verify(blob, purpose: PURPOSE) or return
        rendered_at = Time.iso8601(payload["rendered_at"])
        fresh = rendered_at > IDENTITY_TTL.ago

        BrowserReport::Context.new(
          rendered_at:,
          request_id: (payload["request_id"] if fresh),
          revision: payload["revision"],
          user_context: (payload["user_context"] if fresh)
        )
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        nil
      end

      private

      # The serializer is explicit so the host's message_serializer default
      # cannot change the payload's shape or key types.
      def encryptor
        ActiveSupport::MessageEncryptor.new Rails.application.key_generator.generate_key("informant_browser", 32), serializer: :json
      end
    end
  end
end
