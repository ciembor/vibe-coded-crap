require "test_helper"

class IntegrationStoreTest < Minitest::Test
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
end
