require_relative "../test_helper"

module RailsInformant
  module Mcp
    module Tools
      class AnnotationsTest < Minitest::Test
        READ_ONLY_TOOLS = [
          GetError,
          GetInformantStatus,
          ListEnvironments,
          ListErrors,
          ListOccurrences
        ].freeze

        MUTATING_TOOLS = [
          AnnotateError,
          DeleteError,
          IgnoreError,
          MarkDuplicate,
          MarkFixPending,
          ReopenError,
          ResolveError
        ].freeze

        IDEMPOTENT_TOOLS = [
          AnnotateError,
          IgnoreError,
          MarkDuplicate,
          MarkFixPending,
          ReopenError,
          ResolveError
        ].freeze

        ALL_TOOLS = (READ_ONLY_TOOLS + MUTATING_TOOLS).freeze

        def test_read_only_tools_are_marked_read_only
          READ_ONLY_TOOLS.each do |tool|
            annotations = tool.annotations_value

            assert annotations.read_only_hint, "#{tool.name_value} should have read_only_hint: true"
            refute annotations.destructive_hint, "#{tool.name_value} should have destructive_hint: false"
            assert annotations.idempotent_hint, "#{tool.name_value} should have idempotent_hint: true"
          end
        end

        def test_mutating_tools_are_explicitly_not_read_only
          MUTATING_TOOLS.each do |tool|
            annotations = tool.annotations_value

            refute annotations.read_only_hint, "#{tool.name_value} should have read_only_hint: false"
          end
        end

        def test_idempotent_tools_are_marked_idempotent
          IDEMPOTENT_TOOLS.each do |tool|
            annotations = tool.annotations_value

            assert annotations.idempotent_hint, "#{tool.name_value} should have idempotent_hint: true"
          end
        end

        def test_delete_is_destructive_and_idempotent
          annotations = DeleteError.annotations_value

          assert annotations.destructive_hint
          assert annotations.idempotent_hint
        end

        def test_all_tools_have_explicit_annotations
          ALL_TOOLS.each do |tool|
            annotations = tool.annotations_value

            refute_nil annotations, "#{tool.name_value} must have annotations declared"
          end
        end
      end
    end
  end
end
