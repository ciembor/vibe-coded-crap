require "test_helper"

class WorkflowApiTest < Minitest::Test
  def setup
    reset_ticket_rules!
  end

  def test_workflow_store_exports_transitions_and_permissions_to_ticket_policy
    with_tmpdir do |dir|
      store = Helpdesk::WorkflowStore.new(path: File.join(dir, "workflows.json"))
      store.upsert(
        "bug",
        statuses: ["open", "triaged", "closed"],
        initial_status: "open",
        transitions: { "open" => ["triaged"], "triaged" => ["closed"] },
        permissions: { "triaged" => { "closed" => ["admin"] } }
      )
      Helpdesk::Ticket.workflows = store.to_workflow_hash
      ticket = Helpdesk::Ticket.new(title: "Need help", ticket_type: "bug", status: "triaged", custom_fields: { "severity" => "high" }).normalize!

      assert_equal ["triaged"], Helpdesk::Ticket.workflow_next_statuses_for("bug", "open")
      assert_equal false, ticket.can_transition_to?("closed", role: "agent")
      assert_equal true, ticket.can_transition_to?("closed", role: "admin")
    end
  ensure
    reset_ticket_rules!
  end

  def test_api_tokens_track_usage_rate_limits_and_revocation
    with_tmpdir do |dir|
      store = Helpdesk::ApiTokenStore.new(path: File.join(dir, "tokens.json"))
      token = store.create(name: "cli", user_id: 12, scopes: ["tickets, users", "tickets"])

      first = store.consume!(token["token"], limit: 1, window_seconds: 60)
      second = store.consume!(token["token"], limit: 1, window_seconds: 60)
      revoked = store.revoke(token["id"])

      assert_equal ["tickets", "users"], token["scopes"]
      assert_equal true, first[:allowed]
      assert_equal false, second[:allowed]
      assert_equal false, revoked["enabled"]
    end
  end
end
