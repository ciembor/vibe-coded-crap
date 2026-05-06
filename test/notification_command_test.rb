require "test_helper"

class NotificationCommandTest < Minitest::Test
  def setup
    reset_ticket_rules!
  end

  def test_manual_notification_respects_user_suppression_rules
    with_tmpdir do |dir|
      cli = build_cli(dir, role: "admin")
      users = cli.instance_variable_get(:@users)
      watcher = users.create(name: "Watcher", email: "watcher@example.test", role: "agent")
      watcher = users.update(watcher.id, notification_suppression_rules: ["manual"])
      ticket = cli.instance_variable_get(:@store).create(title: "Quiet ticket")
      ticket.add_watcher(watcher.id)
      cli.instance_variable_get(:@store).save_ticket(ticket)

      output = capture_stdout do
        assert_equal :handled, cli.send(:dispatch_command, "notify", ["email", ticket.id.to_s, "Manual body"])
      end

      refute_includes output, "[email mock] To: Watcher <watcher@example.test>"
      assert cli.instance_variable_get(:@audit_log).all.any? { |entry| entry["action"] == "notification.email" }
    end
  end
end
