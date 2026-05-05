module Helpdesk
  class CliCommandRouter
    EXIT_COMMANDS = %w[exit quit].freeze

    class MethodCommandHandler
      def initialize(method_name, passes_args:)
        @method_name = method_name
        @passes_args = passes_args
      end

      def call(cli, args)
        @passes_args ? cli.send(@method_name, args) : cli.send(@method_name)
      end
    end
    private_constant :MethodCommandHandler

    ROUTES = {
      "help" => MethodCommandHandler.new(:print_help, passes_args: false),
      "list" => MethodCommandHandler.new(:list, passes_args: true),
      "show" => MethodCommandHandler.new(:show, passes_args: true),
      "new" => MethodCommandHandler.new(:create_ticket, passes_args: true),
      "edit" => MethodCommandHandler.new(:edit_ticket, passes_args: true),
      "delete" => MethodCommandHandler.new(:delete_ticket, passes_args: true),
      "restore" => MethodCommandHandler.new(:restore_ticket, passes_args: true),
      "close" => MethodCommandHandler.new(:close_tickets, passes_args: true),
      "undo" => MethodCommandHandler.new(:undo, passes_args: true),
      "merge" => MethodCommandHandler.new(:merge_tickets, passes_args: true),
      "relate" => MethodCommandHandler.new(:manage_relationships, passes_args: true),
      "parent" => MethodCommandHandler.new(:manage_hierarchy, passes_args: true),
      "dependency" => MethodCommandHandler.new(:manage_dependencies, passes_args: true),
      "status" => MethodCommandHandler.new(:change_status, passes_args: true),
      "comment" => MethodCommandHandler.new(:add_comment, passes_args: true),
      "note" => MethodCommandHandler.new(:add_note, passes_args: true),
      "watch" => MethodCommandHandler.new(:manage_watchers, passes_args: true),
      "attach" => MethodCommandHandler.new(:manage_attachments, passes_args: true),
      "pin" => MethodCommandHandler.new(:manage_pins, passes_args: true),
      "archive" => MethodCommandHandler.new(:manage_archives, passes_args: true),
      "tag" => MethodCommandHandler.new(:manage_tags, passes_args: true),
      "search" => MethodCommandHandler.new(:search, passes_args: true),
      "searches" => MethodCommandHandler.new(:list_saved_searches, passes_args: false),
      "filter" => MethodCommandHandler.new(:filter, passes_args: true),
      "filters" => MethodCommandHandler.new(:list_favorite_filters, passes_args: false),
      "field" => MethodCommandHandler.new(:manage_custom_fields, passes_args: true),
      "template" => MethodCommandHandler.new(:manage_templates, passes_args: true),
      "activity" => MethodCommandHandler.new(:activity, passes_args: true),
      "overdue" => MethodCommandHandler.new(:overdue, passes_args: false),
      "sla" => MethodCommandHandler.new(:manage_sla, passes_args: true),
      "escalation" => MethodCommandHandler.new(:manage_escalation, passes_args: true),
      "escalations" => MethodCommandHandler.new(:escalations, passes_args: false),
      "escalate" => MethodCommandHandler.new(:escalate_ticket, passes_args: true),
      "analytics" => MethodCommandHandler.new(:analytics, passes_args: true),
      "report" => MethodCommandHandler.new(:report, passes_args: true),
      "sort" => MethodCommandHandler.new(:manage_sorting, passes_args: true),
      "workflow" => MethodCommandHandler.new(:manage_workflows, passes_args: true),
      "duplicates" => MethodCommandHandler.new(:duplicates, passes_args: true),
      "remind" => MethodCommandHandler.new(:remind, passes_args: true),
      "reminders" => MethodCommandHandler.new(:reminders, passes_args: false),
      "dashboard" => MethodCommandHandler.new(:dashboard, passes_args: false),
      "stats" => MethodCommandHandler.new(:dashboard, passes_args: false),
      "export" => MethodCommandHandler.new(:export, passes_args: true),
      "import" => MethodCommandHandler.new(:import, passes_args: true),
      "users" => MethodCommandHandler.new(:list_users, passes_args: false),
      "user" => MethodCommandHandler.new(:manage_users, passes_args: true),
      "notify" => MethodCommandHandler.new(:manage_notifications, passes_args: true),
      "whoami" => MethodCommandHandler.new(:whoami, passes_args: false),
      "audit" => MethodCommandHandler.new(:audit, passes_args: true),
      "api" => MethodCommandHandler.new(:api, passes_args: true),
      "hook" => MethodCommandHandler.new(:manage_hooks, passes_args: true),
      "hooks" => MethodCommandHandler.new(:list_hooks, passes_args: false),
      "plugin" => MethodCommandHandler.new(:manage_plugins, passes_args: true),
      "plugins" => MethodCommandHandler.new(:list_plugins, passes_args: false),
      "webhook" => MethodCommandHandler.new(:manage_webhooks, passes_args: true),
      "webhooks" => MethodCommandHandler.new(:list_webhooks, passes_args: false),
      "aliases" => MethodCommandHandler.new(:list_aliases, passes_args: false),
      "menu" => MethodCommandHandler.new(:interactive_menu, passes_args: true),
      "profile" => MethodCommandHandler.new(:manage_profiles, passes_args: true),
      "profiles" => MethodCommandHandler.new(:list_profiles, passes_args: false),
      "session" => MethodCommandHandler.new(:manage_session, passes_args: true),
      "debug" => MethodCommandHandler.new(:manage_debug, passes_args: true)
    }.freeze

    def initialize(routes: ROUTES, exit_commands: EXIT_COMMANDS)
      @routes = routes
      @exit_commands = exit_commands
    end

    def dispatch(cli, command, args)
      return :exit if @exit_commands.include?(command)

      route = @routes[command]
      return :unknown unless route

      route.call(cli, args)
      :handled
    end
  end
end
