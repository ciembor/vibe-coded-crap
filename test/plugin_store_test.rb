require "test_helper"

class PluginStoreTest < Minitest::Test
  def test_renders_plugin_commands_without_exposing_template_rules_to_store
    with_tmpdir do |dir|
      store = Helpdesk::PluginStore.new(
        path: File.join(dir, "plugins.json"),
        config_path: File.join(dir, "plugins.config.json")
      )
      store.create(name: "ship", command: "deploy {{1}} {{args}}")

      run = store.run("ship", args: ["prod", "force now"])

      assert_equal "ship", run[:plugin]["name"]
      assert_equal "deploy prod prod force\\ now", run[:command]
    end
  end

  def test_loads_config_plugins_as_normalized_records
    with_tmpdir do |dir|
      config_path = File.join(dir, "plugins.config.json")
      File.write(config_path, JSON.pretty_generate("plugins" => [
        { "name" => "ops", "command" => "echo {{args}}" },
        { "name" => "", "command" => "ignored" }
      ]))
      store = Helpdesk::PluginStore.new(
        path: File.join(dir, "plugins.json"),
        config_path: config_path
      )

      assert_equal ["ops"], store.all.map { |plugin| plugin["name"] }
    end
  end
end
