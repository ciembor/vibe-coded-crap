require "shellwords"

module Helpdesk
  module CliIntegrationCommands
    def list_webhooks
      webhooks = @webhooks.all
      if webhooks.empty?
        puts "No webhooks."
        return
      end

      webhooks.each do |webhook|
        puts "##{webhook["id"]} #{webhook["name"]} #{webhook["url"]} events=#{Array(webhook["events"]).join(",")}"
      end
    end

    def list_hooks
      hooks = @hooks.all
      if hooks.empty?
        puts "No hooks."
        return
      end

      hooks.each do |hook|
        puts "##{hook["id"]} #{hook["name"]} command=#{hook["command"]} events=#{Array(hook["events"]).join(",")}"
      end
    end

    def list_plugins
      plugins = @plugins.all
      if plugins.empty?
        puts "No plugins."
        return
      end

      plugins.each do |plugin|
        puts "##{plugin["id"]} #{plugin["name"]} command=#{plugin["command"]} enabled=#{plugin["enabled"]}"
      end
    end

    def manage_webhooks(args)
      action = args[0]
      case action
      when "add"
        return unless require_permission!(:admin)

        name = args[1]
        url = args[2]
        events = args.drop(3)
        if name.to_s.strip.empty? || url.to_s.strip.empty?
          puts "Usage: webhook add NAME URL [EVENT ...]"
          return
        end

        webhook = @webhooks.create(name: name, url: url, events: events)
        puts "Created webhook ##{webhook["id"]}."
      when "remove"
        return unless require_permission!(:admin)

        id = required_id(args.drop(1))
        if @webhooks.delete(id)
          puts "Removed webhook ##{id}."
        else
          puts "Webhook not found."
        end
      when "test"
        return unless require_permission!(:admin)

        id = required_id(args.drop(1))
        webhook = @webhooks.find(id)
        return puts "Webhook not found." unless webhook

        event = args[2].to_s.strip
        event = "webhook.test" if event.empty?
        mode = args[3..].to_a.find { |arg| %w[--fail --flaky].include?(arg) }
        details = { "test" => true }
        details["mode"] = mode.delete_prefix("--") if mode
        payload = integration_dispatcher.payload(event, "webhook ##{webhook["id"]}", details, actor: current_user_name)
        integration_dispatcher.deliver_webhook(webhook, payload)
      else
        puts "Usage: webhook add NAME URL [EVENT ...] | webhook remove ID | webhook test ID [EVENT] [--fail|--flaky]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_hooks(args)
      action = args[0]
      case action
      when "add"
        return unless require_permission!(:admin)

        name = args[1]
        event = args[2]
        command = Shellwords.join(args.drop(3))
        if name.to_s.strip.empty? || event.to_s.strip.empty? || command.to_s.strip.empty?
          puts "Usage: hook add NAME EVENT COMMAND"
          return
        end

        hook = @hooks.create(name: name, events: [event], command: command)
        log_action("hook.create", "hook ##{hook["id"]}", name: hook["name"], events: hook["events"])
        puts "Created hook ##{hook["id"]}."
      when "remove"
        return unless require_permission!(:admin)

        id = required_id(args.drop(1))
        if @hooks.delete(id)
          log_action("hook.delete", "hook ##{id}")
          puts "Removed hook ##{id}."
        else
          puts "Hook not found."
        end
      when "test"
        return unless require_permission!(:admin)

        id = required_id(args.drop(1))
        hook = @hooks.find(id)
        return puts "Hook not found." unless hook

        event = args[2].to_s.strip
        event = Array(hook["events"]).first.to_s if event.empty?
        event = "hook.test" if event.empty?
        payload = integration_dispatcher.payload(event, "hook ##{hook["id"]}", { "test" => true }, actor: current_user_name)
        integration_dispatcher.deliver_hook(hook, payload)
      else
        puts "Usage: hook add NAME EVENT COMMAND | hook remove ID | hook test ID [EVENT]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_plugins(args)
      action = args[0]
      case action
      when "add"
        return unless require_permission!(:admin)

        name = args[1]
        command = args.drop(2).join(" ")
        if name.to_s.strip.empty? || command.to_s.strip.empty?
          puts "Usage: plugin add NAME COMMAND"
          return
        end

        plugin = @plugins.create(name: name, command: command)
        log_action("plugin.create", "plugin ##{plugin["id"]}", name: plugin["name"])
        puts "Created plugin ##{plugin["id"]}."
      when "remove"
        return unless require_permission!(:admin)

        id = required_id(args.drop(1))
        if @plugins.delete(id)
          log_action("plugin.delete", "plugin ##{id}")
          puts "Removed plugin ##{id}."
        else
          puts "Plugin not found."
        end
      when "run", "test"
        name = args[1]
        if name.to_s.strip.empty?
          puts "Usage: plugin run NAME [ARGS...]"
          return
        end
        run_plugin_by_name(name, args.drop(2))
      else
        puts "Usage: plugin add NAME COMMAND | plugin remove ID | plugin run NAME [ARGS...]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def run_plugin_command(command, args)
      result = plugin_runner.run_command(command, args)
      return false unless result

      log_plugin_run(result, args)
      true
    end

    def run_plugin_by_name(name, args)
      result = plugin_runner.run_by_name(name, args)
      log_plugin_run(result, args) if result

      result&.success
    end

    def log_plugin_run(result, args)
      plugin = result.plugin
      log_action("plugin.run", "plugin ##{plugin["id"]}", name: plugin["name"], args: Array(args), success: result.success)
    end

  end
end
