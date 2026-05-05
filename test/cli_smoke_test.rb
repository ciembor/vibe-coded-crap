require "test_helper"

class CliSmokeTest < Minitest::Test
  def setup
    reset_ticket_rules!
  end

  def test_dashboard_and_daily_report_render_from_store_contract
    with_tmpdir do |dir|
      cli = build_cli(dir)
      cli.instance_variable_get(:@store).create(
        title: "Important bug",
        priority: "urgent",
        tags: ["ops"],
        custom_fields: { "severity" => "high" },
        ticket_type: "bug",
        due_at: "2026-05-04"
      )

      output = capture_stdout do
        cli.send(:dashboard)
        cli.send(:report_daily, "2026-05-05")
      end

      assert_includes output, "Dashboard"
      assert_includes output, "Total tickets: 1"
      assert_includes output, "Daily summary report for 2026-05-05"
      assert_includes output, "urgent: 1"
    end
  end

  def test_api_and_notification_smoke_paths_use_configured_stores
    with_tmpdir do |dir|
      cli = build_cli(dir, role: "admin")
      user = cli.instance_variable_get(:@users).create(
        name: "Watcher",
        email: "watcher@example.test",
        role: "agent"
      )
      token = cli.instance_variable_get(:@api_tokens).create(name: "api", user_id: user.id)
      ticket = cli.instance_variable_get(:@store).create(title: "Needs attention")
      ticket.add_watcher(user.id)
      cli.instance_variable_get(:@store).save_ticket(ticket)

      output = capture_stdout do
        cli.send(:api, ["--token", token["token"], "GET", "/tickets"])
        cli.send(:send_email_notifications, ticket, subject: "Updated", body: "Changed", event: "watchers")
      end

      assert_includes output, '"status": 200'
      assert_includes output, "Needs attention"
      assert_includes output, "[email mock] To: Watcher <watcher@example.test>"
    end
  end

  private

  def build_cli(dir, role: "agent")
    store = Helpdesk::Store.new(path: File.join(dir, "tickets.json"))
    cli = Helpdesk::CLI.allocate
    users = Helpdesk::UserStore.new(path: File.join(dir, "users.json"))
    current_user = users.create(name: "Current", email: "current@example.test", role: role)

    cli.instance_variable_set(:@store, store)
    cli.instance_variable_set(:@audit_log, Helpdesk::AuditLog.new(path: File.join(dir, "audit_log.json")))
    cli.instance_variable_set(:@users, users)
    cli.instance_variable_set(:@current_user, current_user)
    cli.instance_variable_set(:@api_tokens, Helpdesk::ApiTokenStore.new(path: File.join(dir, "api_tokens.json")))
    cli.instance_variable_set(:@hooks, Helpdesk::HookStore.new(path: File.join(dir, "hooks.json")))
    cli.instance_variable_set(:@webhooks, Helpdesk::WebhookStore.new(path: File.join(dir, "webhooks.json")))
    cli.instance_variable_set(:@api_rate_limit, Helpdesk::CLI::API_RATE_LIMIT)
    cli.instance_variable_set(:@api_rate_window_seconds, Helpdesk::CLI::API_RATE_WINDOW_SECONDS)
    cli.instance_variable_set(:@api_response_cache, {})
    cli.instance_variable_set(:@debug_enabled, false)
    cli
  end
end
