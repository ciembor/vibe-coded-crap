require "shellwords"
require "helpdesk/ticket"
require "helpdesk/menu_presenter"
require "helpdesk/debug_logger"
require "helpdesk/integration_dispatcher"
require "helpdesk/plugin_runner"
require "helpdesk/email_notifier"
require "helpdesk/audit_logger"
require "helpdesk/application_context"
require "helpdesk/cli_command_registry"
require "helpdesk/cli_api_commands"
require "helpdesk/cli_integration_commands"
require "helpdesk/cli_profile_commands"
require "helpdesk/cli_reporting_commands"
require "helpdesk/cli_search_commands"
require "helpdesk/cli_ticket_commands"
require "helpdesk/cli_user_commands"
require "helpdesk/cli_workflow_commands"

module Helpdesk
  class CLI
    include CliApiCommands
    include CliIntegrationCommands
    include CliProfileCommands
    include CliReportingCommands
    include CliSearchCommands
    include CliTicketCommands
    include CliUserCommands
    include CliWorkflowCommands

    API_RATE_LIMIT = 5
    API_RATE_WINDOW_SECONDS = 60
    API_CACHE_TTL_SECONDS = 30
    COMMANDS = [
      { name: "help", handler: :print_help, aliases: [] },
      { name: "list", handler: :list, aliases: ["ls"] },
      { name: "show", handler: :show, aliases: ["showt"] },
      { name: "new", handler: :create_ticket, aliases: ["add", "create", "newt"], permission: :ticket_write },
      { name: "edit", handler: :edit_ticket, aliases: [], permission: :ticket_write },
      { name: "delete", handler: :delete_ticket, aliases: ["del", "rm"], permission: :ticket_write },
      { name: "restore", handler: :restore_ticket, aliases: [], permission: :ticket_write },
      { name: "close", handler: :close_tickets, aliases: ["done"], permission: :ticket_write },
      { name: "undo", handler: :undo, aliases: [], permission: :ticket_write },
      { name: "merge", handler: :merge_tickets, aliases: [], permission: :ticket_write },
      { name: "relate", handler: :manage_relationships, aliases: [], permission: :ticket_write },
      { name: "parent", handler: :manage_hierarchy, aliases: [], permission: :ticket_write },
      { name: "dependency", handler: :manage_dependencies, aliases: [], permission: :ticket_write },
      { name: "status", handler: :change_status, aliases: [], permission: :ticket_write },
      { name: "comment", handler: :add_comment, aliases: [], permission: :ticket_write },
      { name: "note", handler: :add_note, aliases: [], permission: :ticket_write },
      { name: "watch", handler: :manage_watchers, aliases: [], permission: :ticket_write },
      { name: "attach", handler: :manage_attachments, aliases: [], permission: :ticket_write },
      { name: "pin", handler: :manage_pins, aliases: [], permission: :ticket_write },
      { name: "archive", handler: :manage_archives, aliases: [], permission: :ticket_write },
      { name: "tag", handler: :manage_tags, aliases: [], permission: :ticket_write },
      { name: "search", handler: :search, aliases: [] },
      { name: "searches", handler: :list_saved_searches, aliases: [] },
      { name: "filter", handler: :filter, aliases: [] },
      { name: "filters", handler: :list_favorite_filters, aliases: [] },
      { name: "field", handler: :manage_custom_fields, aliases: [], permission: :ticket_write },
      { name: "template", handler: :manage_templates, aliases: [] },
      { name: "activity", handler: :activity, aliases: [] },
      { name: "overdue", handler: :overdue, aliases: [] },
      { name: "sla", handler: :manage_sla, aliases: [] },
      { name: "escalation", handler: :manage_escalation, aliases: [] },
      { name: "escalations", handler: :escalations, aliases: [] },
      { name: "escalate", handler: :escalate_ticket, aliases: [], permission: :ticket_write },
      { name: "analytics", handler: :analytics, aliases: [] },
      { name: "report", handler: :report, aliases: [] },
      { name: "sort", handler: :manage_sorting, aliases: [] },
      { name: "workflow", handler: :manage_workflows, aliases: [] },
      { name: "duplicates", handler: :duplicates, aliases: [] },
      { name: "remind", handler: :remind, aliases: [], permission: :ticket_write },
      { name: "reminders", handler: :reminders, aliases: [] },
      { name: "dashboard", handler: :dashboard, aliases: ["stats"] },
      { name: "export", handler: :export, aliases: [] },
      { name: "import", handler: :import, aliases: [] },
      { name: "users", handler: :list_users, aliases: [] },
      { name: "user", handler: :manage_users, aliases: [] },
      { name: "notify", handler: :manage_notifications, aliases: [] },
      { name: "whoami", handler: :whoami, aliases: [] },
      { name: "audit", handler: :audit, aliases: [] },
      { name: "api", handler: :api, aliases: [] },
      { name: "hook", handler: :manage_hooks, aliases: [] },
      { name: "hooks", handler: :list_hooks, aliases: [] },
      { name: "plugin", handler: :manage_plugins, aliases: [] },
      { name: "plugins", handler: :list_plugins, aliases: [] },
      { name: "webhook", handler: :manage_webhooks, aliases: [] },
      { name: "webhooks", handler: :list_webhooks, aliases: [] },
      { name: "aliases", handler: :list_aliases, aliases: [] },
      { name: "menu", handler: :interactive_menu, aliases: [] },
      { name: "profile", handler: :manage_profiles, aliases: [] },
      { name: "profiles", handler: :list_profiles, aliases: [] },
      { name: "session", handler: :manage_session, aliases: [] },
      { name: "debug", handler: :manage_debug, aliases: [] },
      { name: "exit", handler: :exit, aliases: ["q", "quit"], terminal: true }
    ].freeze

    def initialize(store: nil)
      @context = ApplicationContext.new(store: store)
      apply_context!
      @api_rate_limit = API_RATE_LIMIT
      @api_rate_window_seconds = API_RATE_WINDOW_SECONDS
      @api_response_cache = {}
      @debug_enabled = env_debug_enabled? || @session.debug_enabled
      persist_debug_setting!
      debug_log("debug mode enabled")
    end

    def run
      puts banner
      loop do
        print "> "
        line = STDIN.gets
        break if line.nil?

        line = line.strip
        next if line.empty?

        command, *args = Shellwords.split(line)
        dispatch_result = dispatch_command(command, args)
        break if dispatch_result == :exit
        next if dispatch_result == :handled

        if run_plugin_command(command, args)
          next
        end

        puts "Unknown command: #{command}. Type 'help'."
      end
    end

    private

    def banner
      current = @current_user ? " (current user: #{@current_user.name}, role: #{@current_user.role_label})" : ""
      profile = @active_profile ? " (profile: #{@active_profile["name"]})" : ""
      "Helpdesk CLI#{current}#{profile} - type 'help' for commands"
    end

    def print_help
      puts <<~HELP
        Commands:
          help
          list [--status STATUS] [--priority PRIORITY] [--tag TAG] [--sort created_at|priority|custom] [--overdue] [--archived|--active|--deleted]
          overdue
          restore ID
          reminders
          remind set ID TIMESTAMP
          remind clear ID
          remind repeat ID INTERVAL
          remind repeat clear ID
          show ID
          new
          edit ID
          delete ID
          close ID [ID ...]
          undo
          merge SOURCE_ID TARGET_ID
          relate add SOURCE_ID TARGET_ID
          relate remove SOURCE_ID TARGET_ID
          relate list ID
          parent set CHILD_ID PARENT_ID
          parent clear ID
          parent list ID
          dependency add ID DEPENDENCY_ID
          dependency remove ID DEPENDENCY_ID
          dependency list ID
          status ID STATUS
          comment ID TEXT
          note ID TEXT
          new [TEMPLATE]
          watch add ID USER_ID
          watch remove ID USER_ID
          watch list ID
          attach add ID NAME [CONTENT_TYPE] [SIZE] [DESCRIPTION]
          attach remove ID ATTACHMENT_ID
          attach list ID
          pin add ID
          pin remove ID
          pin list
          archive add ID
          archive remove ID
          archive list
          tag add ID [ID ...] TAG
          tag remove ID [ID ...] TAG
          search QUERY
          search save NAME QUERY
          search run NAME
          search delete NAME
          searches
          filter save NAME [list options]
          filter run NAME
          filter delete NAME
          filters
          field set ID KEY VALUE
          field remove ID KEY
          field list ID
          template list
          template show NAME
          template add
          template edit NAME
          template delete NAME
          activity [--last N] [--ticket ID]
          sla
          sla rules show
          sla rules set PRIORITY WARNING_DAYS BREACH_DAYS
          sla rules reset [PRIORITY|all]
          escalations
          escalate ID [NOTE]
          escalation history [--last N] [--ticket ID]
          escalation rules show
          escalation rules set PRIORITY ENABLED TRIGGER TARGET_ROLE
          escalation rules reset [PRIORITY|all]
          analytics [summary|status|aging|trend]
          report daily [DATE]
          report weekly [DATE]
          sort rules show
          sort rules set FIELD [FIELD ...]
          sort rules reset
          workflow show
          workflow set TYPE STATUS [STATUS ...]
          workflow reset [TYPE|all]
          workflow transitions show TYPE
          workflow transitions set TYPE FROM STATUS [STATUS ...]
          workflow transitions reset [TYPE|all]
          workflow permissions show TYPE
          workflow permissions set TYPE FROM TO ROLE [ROLE ...]
          workflow permissions reset [TYPE|all]
          duplicates [--ticket ID]
          dashboard
          stats
          export csv [PATH]
          export json [PATH]
          import json [PATH]
          users
          user add
          user switch ID
          user role ID ROLE
          notify show
          notify set KEY VALUE
          notify suppress show
          notify suppress add RULE
          notify suppress remove RULE
          notify email ID [BODY]
          whoami
          audit [--last N] [--action ACTION] [--actor NAME] [--subject TEXT]
          api --token TOKEN METHOD PATH [JSON_BODY]
          api tokens list
          api tokens create NAME [USER_ID]
          api tokens revoke ID
          hooks
          hook add NAME EVENT COMMAND
          hook remove ID
          hook test ID [EVENT]
          aliases
          menu
          profiles
          profile show [NAME]
          profile use NAME
          profile set NAME data_dir PATH
          profile delete NAME
          session show
          session clear
          debug on|off|show
          plugins
          plugin add NAME COMMAND
          plugin remove ID
          plugin run NAME [ARGS...]
          webhooks
          webhook add NAME URL [EVENT ...]
          webhook remove ID
          webhook test ID [EVENT] [--fail|--flaky]
          exit
      HELP
    end

    def list_aliases
      aliases = command_aliases
      aliases.each do |name, target|
        puts "#{name} -> #{target}"
      end
    end

    def persist_current_user_session!
      @context.current_user = @current_user
    end

    def configure_from_profile!(force_profile_dir: false)
      @context.reload!(force_profile_dir: force_profile_dir)
      apply_context!
    end

    def apply_context!
      @profiles = @context.profiles
      @active_profile = @context.active_profile
      @store = @context.store
      @audit_log = @context.audit_log
      @escalation_rules = @context.escalation_rules
      @sla_rules = @context.sla_rules
      @sort_rules = @context.sort_rules
      @templates = @context.templates
      @users = @context.users
      @session = @context.session
      @api_tokens = @context.api_tokens
      @hooks = @context.hooks
      @plugins = @context.plugins
      @workflows = @context.workflows
      @webhooks = @context.webhooks
      @current_user = @context.current_user
    end

    def prompt(label, default = nil)
      if default.nil? || default.empty?
        print "#{label}: "
      else
        print "#{label} [#{default}]: "
      end
      value = STDIN.gets&.chomp
      return default if value.nil? || value.strip.empty?

      value.strip
    end

    def interactive_menu(_args = [])
      loop do
        puts MenuPresenter.menu

        choice = prompt("Choose an option", "q")
        case normalize_menu_choice(choice)
        when "d"
          dashboard
        when "l"
          list([])
        when "s"
          show([prompt("Ticket ID")])
        when "n"
          create_ticket([])
        when "f"
          search([prompt("Search query")])
        when "w"
          whoami
        when "h"
          puts MenuPresenter.shortcuts
        when "q"
          puts "Leaving menu."
          break
        else
          puts "Unknown menu option."
        end
      end
    end

    def parse_options(args)
      options = {}
      idx = 0
      while idx < args.length
        case args[idx]
        when "--status"
          options[:status] = args[idx + 1]
          idx += 2
        when "--priority"
          options[:priority] = args[idx + 1]
          idx += 2
        when "--tag"
          options[:tag] = args[idx + 1]
          idx += 2
        when "--sort"
          options[:sort] = args[idx + 1]
          idx += 2
        when "--overdue"
          options[:overdue] = true
          idx += 1
        when "--archived"
          options[:archived] = true
          idx += 1
        when "--active"
          options[:active] = true
          idx += 1
        when "--deleted"
          options[:deleted] = true
          idx += 1
        else
          idx += 1
        end
      end
      options
    end

    def sort_tickets(tickets, sort)
      case sort
      when "priority"
        order = Ticket::PRIORITIES.each_with_index.to_h
        tickets.sort_by { |ticket| [ticket.archived? ? 1 : 0, ticket.pinned? ? 0 : 1, order.fetch(ticket.priority, 99), ticket.created_at.to_s] }
      when "custom"
        tickets.sort_by { |ticket| custom_sort_key(ticket) }
      else
        tickets.sort_by { |ticket| [ticket.archived? ? 1 : 0, ticket.pinned? ? 0 : 1, ticket.created_at.to_s] }
      end
    end

    def custom_sort_key(ticket)
      rule = @sort_rules.current
      rule.map { |field| custom_sort_value(ticket, field) } + [ticket.created_at.to_s, ticket.id.to_i]
    end

    def custom_sort_value(ticket, field)
      case field
      when "pinned"
        ticket.pinned? ? 0 : 1
      when "archived"
        ticket.archived? ? 1 : 0
      when "overdue"
        ticket.overdue? ? 0 : 1
      when "escalation"
        ticket.escalation_needed? ? 0 : 1
      when "sla"
        case ticket.sla_status
        when "breached" then 0
        when "warning" then 1
        when "ok" then 2
        else 3
        end
      when "priority"
        Ticket::PRIORITIES.each_with_index.to_h.fetch(ticket.priority, 99)
      when "status"
        %w[open in_progress waiting resolved closed].each_with_index.to_h.fetch(ticket.status, 99)
      when "due_at"
        ticket.due_date ? ticket.due_date.iso8601 : "9999-12-31"
      when "updated_at"
        ticket.updated_at.to_s
      when "created_at"
        ticket.created_at.to_s
      when "title"
        ticket.title.to_s.downcase
      else
        ""
      end
    end

    def field_visibility_for_role
      role = @current_user&.role_label || "agent"
      case role
      when "viewer"
        {
          type: false,
          pinned: false,
          archived: false,
          comments: true,
          internal_notes: false,
          watchers: false,
          attachments: true,
          custom_fields: false
        }
      else
        {
          type: true,
          pinned: true,
          archived: true,
          comments: true,
          internal_notes: true,
          watchers: true,
          attachments: true,
          custom_fields: true
        }
      end
    end

    def option_value(options, key)
      options[key] || options[key.to_s]
    end

    def truthy_option?(options, key)
      value = option_value(options, key)
      value == true || %w[true yes on 1].include?(value.to_s.strip.downcase)
    end

    def required_id(args)
      id = args[0]
      raise ArgumentError, "Usage requires an ID" if id.nil? || id.strip.empty?

      id.to_i
    end

    def log_action(action, subject, details = {})
      actor = @current_user ? @current_user.display_name : "system"
      audit_logger.log(action, subject, details: details, actor: actor)
    end

    def debug_log(message)
      debug_logger.log(message)
    end

    def persist_debug_setting!
      debug_logger.enabled = @debug_enabled
      return if @session.nil?

      @session.debug_enabled = @debug_enabled
    end

    def env_debug_enabled?
      %w[1 true yes on].include?(ENV.fetch("HELPDESK_DEBUG", "").to_s.strip.downcase)
    end

    def dispatch_command(command, args)
      command_registry.dispatch(self, command.to_s, args)
    end

    def command_registry
      @command_registry ||= CliCommandRegistry.build(COMMANDS)
    end

    def normalize_menu_choice(choice)
      choice.to_s.strip.downcase
    end

    def command_aliases
      command_registry.aliases
    end

    def shell_runner
      @shell_runner ||= ShellCommandRunner.new
    end

    def debug_logger
      @debug_logger ||= DebugLogger.new(enabled: @debug_enabled)
      @debug_logger.enabled = @debug_enabled
      @debug_logger
    end

    def integration_dispatcher
      IntegrationDispatcher.new(hooks: @hooks, webhooks: @webhooks, audit_log: @audit_log, shell: shell_runner)
    end

    def plugin_runner
      PluginRunner.new(plugins: @plugins, shell: shell_runner)
    end

    def email_notifier
      EmailNotifier.new(users: @users)
    end

    def audit_logger
      AuditLogger.new(audit_log: @audit_log, integration_dispatcher: integration_dispatcher, debug_logger: debug_logger)
    end

    def require_permission!(kind)
      role = @current_user&.role_label || "agent"

      allowed =
        case kind
        when :ticket_write
          %w[admin agent].include?(role)
        when :admin
          role == "admin"
        else
          true
        end

      return true if allowed

      puts "Permission denied for #{kind.to_s.tr('_', ' ')} as #{role}."
      false
    end
  end
end
