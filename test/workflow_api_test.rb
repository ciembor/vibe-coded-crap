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

  def test_cli_workflow_permissions_reject_disallowed_status_transition
    with_tmpdir do |dir|
      cli = build_cli(dir, role: "agent")
      cli.instance_variable_get(:@workflows).upsert(
        "general",
        statuses: ["open", "closed"],
        initial_status: "open",
        transitions: { "open" => ["closed"] },
        permissions: { "open" => { "closed" => ["admin"] } }
      )
      cli.send(:reload_ticket_workflows!)
      ticket = cli.instance_variable_get(:@store).create(title: "Needs approval")

      output = capture_stdout do
        assert_equal :handled, cli.send(:dispatch_command, "status", [ticket.id.to_s, "closed"])
      end

      assert_includes output, "transition open -> closed is not permitted for agent"
      assert_equal "open", cli.instance_variable_get(:@store).find(ticket.id).status
    end
  end

  def test_api_command_reports_rate_limits_with_error_envelope
    with_tmpdir do |dir|
      cli = build_cli(dir, role: "admin")
      cli.instance_variable_set(:@api_rate_limit, 1)
      token = cli.instance_variable_get(:@api_tokens).create(name: "api", user_id: cli.instance_variable_get(:@current_user).id)

      output = capture_stdout do
        cli.send(:api, ["--token", token["token"], "GET", "/tickets"])
        cli.send(:api, ["--token", token["token"], "GET", "/tickets"])
      end

      assert_includes output, '"status": 200'
      assert_includes output, '"status": 429'
      assert_includes output, '"error": "API rate limit exceeded."'
      assert_includes output, '"rate_limit_remaining": 0'
    end
  end

  def test_api_command_invalidates_cached_ticket_list_after_write
    with_tmpdir do |dir|
      cli = build_cli(dir, role: "admin")
      token = cli.instance_variable_get(:@api_tokens).create(name: "api", user_id: cli.instance_variable_get(:@current_user).id)

      first_get = capture_stdout do
        cli.send(:api, ["--token", token["token"], "GET", "/tickets"])
      end
      capture_stdout do
        cli.send(:api, ["--token", token["token"], "POST", "/tickets", JSON.generate("title" => "CreatedViaApi")])
      end
      second_get = capture_stdout do
        cli.send(:api, ["--token", token["token"], "GET", "/tickets"])
      end

      refute_includes first_get, "CreatedViaApi"
      assert_includes second_get, "CreatedViaApi"
    end
  end
end
