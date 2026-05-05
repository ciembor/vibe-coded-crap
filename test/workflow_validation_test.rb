require "test_helper"

module Helpdesk
  class WorkflowValidationTest < Minitest::Test
    def test_workflow_must_include_closed_status
      with_tempdir do |dir|
        store = WorkflowStore.new(path: File.join(dir, "workflows.json"))

        error = assert_raises(ArgumentError) do
          store.upsert("support", statuses: %w[open waiting])
        end

        assert_includes error.message, "must include closed"
      end
    end

    def test_transition_target_must_belong_to_workflow_statuses
      with_tempdir do |dir|
        store = WorkflowStore.new(path: File.join(dir, "workflows.json"))
        store.upsert("support", statuses: %w[open closed])

        error = assert_raises(ArgumentError) do
          store.set_transition("support", "open", ["triaged"])
        end

        assert_includes error.message, "invalid transition targets"
      end
    end

    def test_transition_permission_must_reference_existing_transition
      with_tempdir do |dir|
        store = WorkflowStore.new(path: File.join(dir, "workflows.json"))
        store.upsert("support", statuses: %w[open waiting closed])
        store.set_transition("support", "open", ["waiting"])

        error = assert_raises(ArgumentError) do
          store.set_transition_permission("support", "open", "closed", ["agent"])
        end

        assert_includes error.message, "has no transition open -> closed"
      end
    end
  end
end
