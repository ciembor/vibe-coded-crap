require "test_helper"

class IntegrationStoreTest < Minitest::Test
  FakeShellResult = Struct.new(:success, :exit_status, keyword_init: true)

  class FakeShell
    attr_reader :invocations

    def initialize(results = [true])
      @results = results
      @invocations = []
    end

    def run(env, command)
      success = @results.empty? ? true : @results.shift
      @invocations << { env: env, command: command, success: success }
      FakeShellResult.new(success: success, exit_status: success ? 0 : 7)
    end
  end

  def test_hook_and_webhook_matching_supports_wildcards_and_disabled_rows
    with_tmpdir do |dir|
      hooks = Helpdesk::HookStore.new(path: File.join(dir, "hooks.json"))
      hooks.create(name: "ticket hooks", events: ["ticket.*"], command: "echo {{event}}")
      hooks.create(name: "disabled", events: ["ticket.created"], command: "echo no", enabled: false)

      webhooks = Helpdesk::WebhookStore.new(path: File.join(dir, "webhooks.json"))
      exact = webhooks.create(name: "exact", url: "https://example.test/exact", events: ["ticket.created"])
      wildcard = webhooks.create(name: "all tickets", url: "https://example.test/all", events: ["ticket.*"])

      assert_equal ["ticket hooks"], hooks.matching("ticket.created").map { |hook| hook["name"] }
      assert_equal [exact["id"]], webhooks.matching("ticket.created").select { |row| row["name"] == "exact" }.map { |row| row["id"] }
      assert_equal [wildcard["id"]], webhooks.matching("ticket.closed").map { |row| row["id"] }
    end
  end

  def test_plugin_store_renders_commands_and_loads_config_plugins
    with_tmpdir do |dir|
      config_path = File.join(dir, "plugins.config.json")
      File.write(config_path, JSON.pretty_generate("plugins" => [
        { "name" => "ops", "command" => "echo {{args}}" },
        { "name" => "", "command" => "ignored" }
      ]))
      store = Helpdesk::PluginStore.new(path: File.join(dir, "plugins.json"), config_path: config_path)
      store.create(name: "ship", command: "deploy {{1}} {{args}}")

      run = store.run("ship", args: ["prod", "force now"])

      assert_equal ["ops", "ship"], store.all.map { |plugin| plugin["name"] }.sort
      assert_equal "deploy prod prod force\\ now", run[:command]
    end
  end

  def test_plugin_runner_sets_environment_and_reports_shell_result
    with_tmpdir do |dir|
      plugins = Helpdesk::PluginStore.new(path: File.join(dir, "plugins.json"), config_path: File.join(dir, "plugins.config.json"))
      plugin = plugins.create(name: "ship", command: "deploy {{1}} {{args}}")
      shell = FakeShell.new([true])
      runner = Helpdesk::PluginRunner.new(plugins: plugins, shell: shell)

      output = capture_stdout do
        result = runner.run_by_name("ship", ["prod", "now"])
        assert_equal true, result.success
      end

      assert_includes output, "[plugin mock] Running plugin ##{plugin["id"]} ship: deploy prod prod now"
      assert_equal "ship", shell.invocations.first[:env]["HELPDESK_PLUGIN_NAME"]
      assert_equal "prod now", shell.invocations.first[:env]["HELPDESK_PLUGIN_ARGS"]
      assert_equal "deploy prod prod now", shell.invocations.first[:command]
    end
  end

  def test_integration_dispatcher_runs_matching_hooks_and_retries_flaky_webhooks
    with_tmpdir do |dir|
      hooks = Helpdesk::HookStore.new(path: File.join(dir, "hooks.json"))
      hook = hooks.create(name: "ticket hook", events: ["ticket.*"], command: "echo hook")
      webhooks = Helpdesk::WebhookStore.new(path: File.join(dir, "webhooks.json"))
      webhooks.create(name: "flaky", url: "https://example.test/flaky", events: ["ticket.*"])
      audit_log = Helpdesk::AuditLog.new(path: File.join(dir, "audit_log.json"))
      shell = FakeShell.new([true])
      dispatcher = Helpdesk::IntegrationDispatcher.new(hooks: hooks, webhooks: webhooks, audit_log: audit_log, shell: shell)

      output = capture_stdout do
        dispatcher.dispatch("ticket.created", "Agent", "ticket #1", {})
      end

      assert_equal "echo hook", shell.invocations.first[:command]
      assert_equal hook["id"].to_s, shell.invocations.first[:env]["HELPDESK_HOOK_ID"]
      assert_includes output, "[webhook mock] Attempt 1/3 POST https://example.test/flaky"
      assert_includes output, "[webhook mock] Attempt 3/3 POST https://example.test/flaky"
      assert_includes output, "[webhook mock] Delivered."
      trigger = audit_log.all.find { |entry| entry["action"] == "hook.trigger" }
      refute_nil trigger
      assert_equal true, trigger.dig("details", "success")
    end
  end
end
