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

  def test_command_registry_dispatches_aliases_and_terminal_commands
    with_tmpdir do |dir|
      cli = build_cli(dir)

      list_output = capture_stdout do
        assert_equal :handled, cli.send(:dispatch_command, "ls", [])
      end
      aliases_output = capture_stdout do
        cli.send(:list_aliases)
      end

      assert_includes list_output, "No tickets found."
      assert_includes aliases_output, "ls -> list"
      assert_includes aliases_output, "stats -> dashboard"
      assert_equal :exit, cli.send(:dispatch_command, "q", [])
      assert_nil cli.send(:dispatch_command, "missing", [])
    end
  end

  def test_profile_session_and_debug_commands_use_extracted_group
    with_tmpdir do |dir|
      cli = build_cli(dir)

      output = capture_stdout do
        assert_equal :handled, cli.send(:dispatch_command, "profiles", [])
        assert_equal :handled, cli.send(:dispatch_command, "session", ["show"])
        assert_equal :handled, cli.send(:dispatch_command, "debug", ["on"])
        assert_equal :handled, cli.send(:dispatch_command, "debug", ["show"])
      end

      assert_includes output, "default data_dir="
      assert_includes output, "Current session user:"
      assert_includes output, "Debug logging enabled."
      assert_includes output, "Debug logging: on"
    end
  end

  def test_integration_commands_use_extracted_group
    with_tmpdir do |dir|
      cli = build_cli(dir, role: "admin")

      output = capture_stdout do
        assert_equal :handled, cli.send(:dispatch_command, "hook", ["add", "ticket-log", "ticket.*", "echo", "hook"])
        assert_equal :handled, cli.send(:dispatch_command, "hooks", [])
        assert_equal :handled, cli.send(:dispatch_command, "webhook", ["add", "events", "https://example.test/hooks", "ticket.*"])
        assert_equal :handled, cli.send(:dispatch_command, "webhooks", [])
        assert_equal :handled, cli.send(:dispatch_command, "plugin", ["add", "ship", "echo", "plugin"])
        assert_equal :handled, cli.send(:dispatch_command, "plugins", [])
      end

      assert_includes output, "Created hook #"
      assert_includes output, "ticket-log"
      assert_includes output, "Created webhook #"
      assert_includes output, "https://example.test/hooks"
      assert_includes output, "Created plugin #"
      assert_includes output, "ship"
    end
  end

  def test_user_and_notification_commands_use_extracted_group
    with_tmpdir do |dir|
      cli = build_cli(dir)

      output = capture_stdout do
        assert_equal :handled, cli.send(:dispatch_command, "users", [])
        assert_equal :handled, cli.send(:dispatch_command, "whoami", [])
        assert_equal :handled, cli.send(:dispatch_command, "notify", ["show"])
        assert_equal :handled, cli.send(:dispatch_command, "notify", ["set", "email", "false"])
        assert_equal :handled, cli.send(:dispatch_command, "notify", ["suppress", "add", "manual"])
        assert_equal :handled, cli.send(:dispatch_command, "notify", ["suppress", "show"])
      end

      assert_includes output, "Current <current@example.test>"
      assert_includes output, "Current user:"
      assert_includes output, "email: true"
      assert_includes output, "Updated notification preference email to false."
      assert_includes output, "Updated suppression rules: manual"
      assert_includes output, "manual"
    end
  end

  def test_search_and_filter_commands_use_extracted_group
    with_tmpdir do |dir|
      cli = build_cli(dir)
      cli.instance_variable_get(:@store).create(title: "Login failure", priority: "urgent", tags: ["auth"])
      cli.instance_variable_get(:@store).create(title: "Billing question", priority: "low", tags: ["billing"])

      output = capture_stdout do
        assert_equal :handled, cli.send(:dispatch_command, "search", ["save", "authbugs", "login"])
        assert_equal :handled, cli.send(:dispatch_command, "searches", [])
        assert_equal :handled, cli.send(:dispatch_command, "search", ["run", "authbugs"])
        assert_equal :handled, cli.send(:dispatch_command, "filter", ["save", "urgent", "--priority", "urgent"])
        assert_equal :handled, cli.send(:dispatch_command, "filters", [])
        assert_equal :handled, cli.send(:dispatch_command, "filter", ["run", "urgent"])
      end

      assert_includes output, "Saved search authbugs."
      assert_includes output, "authbugs: login"
      assert_includes output, "Login failure"
      assert_includes output, "Saved favorite filter urgent."
      assert_includes output, "urgent: --priority urgent"
      refute_includes output, "Billing question"
    end
  end

  def test_workflow_and_sort_commands_use_extracted_group
    with_tmpdir do |dir|
      cli = build_cli(dir, role: "admin")

      output = capture_stdout do
        assert_equal :handled, cli.send(:dispatch_command, "sort", ["set", "priority", "created_at"])
        assert_equal :handled, cli.send(:dispatch_command, "sort", ["rules", "show"])
        assert_equal :handled, cli.send(:dispatch_command, "workflow", ["set", "bug", "open", "triaged", "closed"])
        assert_equal :handled, cli.send(:dispatch_command, "workflow", ["transitions", "set", "bug", "open", "triaged"])
        assert_equal :handled, cli.send(:dispatch_command, "workflow", ["permissions", "set", "bug", "open", "triaged", "admin"])
        assert_equal :handled, cli.send(:dispatch_command, "workflow", ["show"])
      end

      assert_includes output, "Updated custom sort rule."
      assert_includes output, "Custom sort order: priority > created_at"
      assert_includes output, "Updated workflow bug."
      assert_includes output, "Updated transitions for workflow bug."
      assert_includes output, "Updated transition permissions for workflow bug."
      assert_includes output, "bug: open, triaged, closed"
      assert_includes output, "open -> triaged"
      assert_includes output, "open => triaged: admin"
    end
  end

  def test_reporting_activity_and_export_commands_use_extracted_group
    with_tmpdir do |dir|
      cli = build_cli(dir, role: "admin")
      ticket = cli.instance_variable_get(:@store).create(title: "Reportable ticket", priority: "high", tags: ["ops"])
      cli.send(:log_action, "ticket.update", "ticket ##{ticket.id}", status: "open")
      csv_path = File.join(dir, "tickets.csv")
      json_path = File.join(dir, "tickets.json")

      output = capture_stdout do
        assert_equal :handled, cli.send(:dispatch_command, "dashboard", [])
        assert_equal :handled, cli.send(:dispatch_command, "analytics", ["summary"])
        assert_equal :handled, cli.send(:dispatch_command, "report", ["daily", "2026-05-05"])
        assert_equal :handled, cli.send(:dispatch_command, "duplicates", [])
        assert_equal :handled, cli.send(:dispatch_command, "audit", ["--action", "ticket.update"])
        assert_equal :handled, cli.send(:dispatch_command, "activity", ["--ticket", ticket.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "export", ["csv", csv_path])
        assert_equal :handled, cli.send(:dispatch_command, "export", ["json", json_path])
      end

      assert_includes output, "Dashboard"
      assert_includes output, "Analytics"
      assert_includes output, "Daily summary report for 2026-05-05"
      assert_includes output, "No duplicate tickets found."
      assert_includes output, "ticket.update"
      assert_includes output, "updated ticket ##{ticket.id}"
      assert_includes output, "Exported 1 tickets to #{csv_path}."
      assert_includes output, "Exported 1 tickets to #{json_path}."
      assert File.exist?(csv_path)
      assert File.exist?(json_path)
    end
  end

  def test_ticket_commands_use_extracted_group
    with_tmpdir do |dir|
      cli = build_cli(dir, role: "admin")
      store = cli.instance_variable_get(:@store)
      current_user = cli.instance_variable_get(:@current_user)
      first = store.create(
        title: "Broken login",
        priority: "urgent",
        ticket_type: "bug",
        due_at: "2026-05-04",
        tags: ["auth"],
        custom_fields: { "severity" => "high" }
      )
      second = store.create(title: "Reset password copy", priority: "medium")
      disposable = store.create(title: "Disposable")

      output = capture_stdout do
        assert_equal :handled, cli.send(:dispatch_command, "list", ["--priority", "urgent"])
        assert_equal :handled, cli.send(:dispatch_command, "show", [first.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "status", [first.id.to_s, "waiting"])
        assert_equal :handled, cli.send(:dispatch_command, "tag", ["add", first.id.to_s, second.id.to_s, "support"])
        assert_equal :handled, cli.send(:dispatch_command, "relate", ["add", first.id.to_s, second.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "relate", ["list", first.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "parent", ["set", second.id.to_s, first.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "parent", ["list", first.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "dependency", ["add", first.id.to_s, second.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "dependency", ["list", first.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "watch", ["add", first.id.to_s, current_user.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "attach", ["add", first.id.to_s, "trace.log", "text/plain", "12", "login trace"])
        assert_equal :handled, cli.send(:dispatch_command, "field", ["set", first.id.to_s, "severity", "high"])
        assert_equal :handled, cli.send(:dispatch_command, "pin", ["add", first.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "archive", ["add", second.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "overdue", [])
        assert_equal :handled, cli.send(:dispatch_command, "sla", ["rules", "set", "urgent", "1", "2"])
        assert_equal :handled, cli.send(:dispatch_command, "sla", ["rules", "show"])
        assert_equal :handled, cli.send(:dispatch_command, "escalation", ["rules", "set", "urgent", "true", "overdue", "admin"])
        assert_equal :handled, cli.send(:dispatch_command, "escalate", [first.id.to_s, "manual check"])
        assert_equal :handled, cli.send(:dispatch_command, "escalation", ["history", "--ticket", first.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "remind", ["set", first.id.to_s, "2026-05-05", "10:00", "UTC"])
        assert_equal :handled, cli.send(:dispatch_command, "reminders", [])
        assert_equal :handled, cli.send(:dispatch_command, "template", ["list"])
        assert_equal :handled, cli.send(:dispatch_command, "delete", [disposable.id.to_s])
        assert_equal :handled, cli.send(:dispatch_command, "restore", [disposable.id.to_s])
      end

      assert_includes output, "Broken login"
      assert_includes output, "Updated ticket ##{first.id} to waiting."
      assert_includes output, "Added tag for tickets: ##{first.id}, ##{second.id}"
      assert_includes output, "Related ticket ##{first.id} with ##{second.id}."
      assert_includes output, "Set ticket ##{first.id} as parent of ##{second.id}."
      assert_includes output, "Added dependency ##{second.id} to ticket ##{first.id}."
      assert_includes output, "Added watcher Current <current@example.test> to ticket ##{first.id}."
      assert_includes output, "Added attachment trace.log to ticket ##{first.id}."
      assert_includes output, "Set custom field severity on ticket ##{first.id}."
      assert_includes output, "Pinned ticket ##{first.id}."
      assert_includes output, "Archived ticket ##{second.id}."
      assert_includes output, "Updated SLA rule for urgent."
      assert_includes output, "urgent: warning 1 days, breach 2 days"
      assert_includes output, "Updated escalation rule for urgent."
      assert_includes output, "Recorded escalation history for ticket ##{first.id}."
      assert_includes output, "manual check"
      assert_includes output, "Reminder set for ticket ##{first.id}."
      assert_includes output, "##{first.id} Broken login [reminder"
      assert_includes output, "No templates found."
      assert_includes output, "Soft-deleted ticket ##{disposable.id}."
      assert_includes output, "Restored ticket ##{disposable.id}."
    end
  end
end
