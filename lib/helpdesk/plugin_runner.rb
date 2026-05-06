require "helpdesk/shell_command_runner"

module Helpdesk
  class PluginRunner
    Result = Struct.new(:plugin, :success, keyword_init: true)

    def initialize(plugins:, shell: ShellCommandRunner.new)
      @plugins = plugins
      @shell = shell
    end

    def run_command(command, args)
      plugin = @plugins.find_by_name(command)
      return nil if plugin.nil? || plugin["enabled"] == false

      run(plugin, args)
    end

    def run_by_name(name, args)
      plugin = @plugins.find_by_name(name)
      return missing_plugin unless plugin
      return disabled_plugin if plugin["enabled"] == false

      run(plugin, args)
    end

    def run(plugin, args)
      command = @plugins.run(plugin["name"], args: args)
      return missing_plugin unless command

      rendered = command[:command]
      env = {
        "HELPDESK_PLUGIN_ID" => plugin["id"].to_s,
        "HELPDESK_PLUGIN_NAME" => plugin["name"].to_s,
        "HELPDESK_PLUGIN_ARGS" => Array(args).join(" "),
        "HELPDESK_PLUGIN_COMMAND" => rendered
      }

      puts "[plugin mock] Running plugin ##{plugin["id"]} #{plugin["name"]}: #{rendered}"
      shell_result = @shell.run(env, rendered)
      if shell_result.success
        puts "[plugin mock] Completed."
      else
        puts "[plugin mock] Failed#{shell_result.exit_status ? " (exit #{shell_result.exit_status})" : ""}."
      end

      Result.new(plugin: plugin, success: shell_result.success)
    end

    private

    def missing_plugin
      puts "Plugin not found."
      nil
    end

    def disabled_plugin
      puts "Plugin is disabled."
      nil
    end
  end
end
