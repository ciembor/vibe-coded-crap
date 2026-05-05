require "shellwords"
require "time"
require "csv"
require "json"
require "fileutils"
require "helpdesk/audit_log"
require "helpdesk/api_token_store"
require "helpdesk/hook_store"
require "helpdesk/escalation_rule_store"
require "helpdesk/store"
require "helpdesk/sla_rule_store"
require "helpdesk/sort_rule_store"
require "helpdesk/template_store"
require "helpdesk/user_store"
require "helpdesk/session_store"
require "helpdesk/workflow_store"
require "helpdesk/webhook_store"

module Helpdesk
  class CLI
    API_RATE_LIMIT = 5
    API_RATE_WINDOW_SECONDS = 60
    API_CACHE_TTL_SECONDS = 30

    def initialize(store: Store.new)
      @store = store
      @audit_log = AuditLog.new
      @escalation_rules = EscalationRuleStore.new
      @sla_rules = SlaRuleStore.new
      @sort_rules = SortRuleStore.new
      @templates = TemplateStore.new
      @users = UserStore.new
      @session = SessionStore.new
      @api_tokens = ApiTokenStore.new
      @hooks = HookStore.new
      @plugins = PluginStore.new
      @workflows = WorkflowStore.new
      @webhooks = WebhookStore.new
      reload_ticket_workflows!
      @api_rate_limit = API_RATE_LIMIT
      @api_rate_window_seconds = API_RATE_WINDOW_SECONDS
      @api_response_cache = {}
      @escalation_rules.reload_ticket_rules!
      @sla_rules.reload_ticket_rules!
      seed_default_user
      load_session_user!
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
        command = resolve_alias(command)
        case command
        when "help" then print_help
        when "list" then list(args)
        when "show" then show(args)
        when "new" then create_ticket(args)
        when "edit" then edit_ticket(args)
        when "delete" then delete_ticket(args)
        when "restore" then restore_ticket(args)
        when "close" then close_tickets(args)
        when "undo" then undo(args)
        when "merge" then merge_tickets(args)
        when "relate" then manage_relationships(args)
        when "parent" then manage_hierarchy(args)
        when "dependency" then manage_dependencies(args)
        when "status" then change_status(args)
        when "comment" then add_comment(args)
        when "note" then add_note(args)
        when "watch" then manage_watchers(args)
        when "attach" then manage_attachments(args)
        when "pin" then manage_pins(args)
        when "archive" then manage_archives(args)
        when "tag" then manage_tags(args)
        when "search" then search(args)
        when "searches" then list_saved_searches
        when "filter" then filter(args)
        when "filters" then list_favorite_filters
        when "field" then manage_custom_fields(args)
        when "template" then manage_templates(args)
        when "activity" then activity(args)
        when "overdue" then overdue
        when "sla" then manage_sla(args)
        when "escalation" then manage_escalation(args)
        when "escalations" then escalations
        when "escalate" then escalate_ticket(args)
        when "analytics" then analytics(args)
        when "report" then report(args)
        when "sort" then manage_sorting(args)
        when "workflow" then manage_workflows(args)
        when "duplicates" then duplicates(args)
        when "remind" then remind(args)
        when "reminders" then reminders
        when "dashboard" then dashboard
        when "stats" then dashboard
        when "export" then export(args)
        when "import" then import(args)
        when "users" then list_users
        when "user" then manage_users(args)
        when "notify" then manage_notifications(args)
        when "whoami" then whoami
        when "audit" then audit(args)
        when "api" then api(args)
        when "hook" then manage_hooks(args)
        when "hooks" then list_hooks
        when "plugin" then manage_plugins(args)
        when "plugins" then list_plugins
        when "webhook" then manage_webhooks(args)
        when "webhooks" then list_webhooks
        when "aliases" then list_aliases
        when "menu" then interactive_menu(args)
        when "session" then manage_session(args)
        when "exit", "quit" then break
        else
          if run_plugin_command(command, args)
            next
          end

          puts "Unknown command: #{command}. Type 'help'."
        end
      end
    end

    private

    def banner
      current = @current_user ? " (current user: #{@current_user.name}, role: #{@current_user.role_label})" : ""
      "Helpdesk CLI#{current} - type 'help' for commands"
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
          session show
          session clear
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

    def list(args)
      options = parse_options(args)
      include_deleted = truthy_option?(options, :deleted)
      tickets = filter_tickets(@store.all(include_deleted: include_deleted), options)

      if tickets.empty?
        puts "No tickets found."
        return
      end

      tickets.each { |ticket| puts format_ticket_row(ticket) }
    end

    def filter_tickets(tickets, options)
      tickets = tickets.select { |ticket| ticket.status == option_value(options, :status) } if option_value(options, :status)
      tickets = tickets.select { |ticket| ticket.priority == option_value(options, :priority) } if option_value(options, :priority)
      tickets = tickets.select { |ticket| ticket.tags.include?(option_value(options, :tag)) } if option_value(options, :tag)
      tickets = tickets.select(&:overdue?) if truthy_option?(options, :overdue)
      tickets = tickets.select(&:archived?) if truthy_option?(options, :archived)
      tickets = tickets.reject(&:archived?) if truthy_option?(options, :active)
      tickets = tickets.select(&:deleted?) if truthy_option?(options, :deleted)
      sort_tickets(tickets, option_value(options, :sort))
    end

    def show(args)
      ticket = @store.find(required_id(args))
      return puts "Ticket not found." unless ticket

      visibility = field_visibility_for_role
      puts "##{ticket.id} #{ticket.title}"
      puts "Status: #{ticket.status}"
      puts "Priority: #{ticket.priority}"
      puts "Type: #{ticket.ticket_type}" if visibility[:type]
      puts "Due: #{ticket.due_at || 'none'}"
      puts "Overdue: #{ticket.overdue? ? 'yes' : 'no'}"
      puts "Reminder: #{ticket.reminder_at || 'none'}"
      puts "Reminder repeat: #{ticket.reminder_repeat || 'none'}"
      puts "Reminder due: #{ticket.reminder_due? ? 'yes' : 'no'}"
      puts "SLA: #{format_sla_status(ticket)}"
      puts "Escalation: #{format_escalation_status(ticket)}"
      puts "Tags: #{ticket.tags.join(", ")}"
      puts "Pinned: #{ticket.pinned? ? 'yes' : 'no'}" if visibility[:pinned]
      puts "Pinned at: #{ticket.pinned_at || 'none'}" if visibility[:pinned]
      puts "Archived: #{ticket.archived? ? 'yes' : 'no'}" if visibility[:archived]
      puts "Archived at: #{ticket.archived_at || 'none'}" if visibility[:archived]
      puts "Merged into: ##{ticket.merged_into_id}" if ticket.merged?
      puts "Merged from: #{ticket.merged_from_ids.map { |id| "##{id}" }.join(", ")}" unless ticket.merged_from_ids.empty?
      show_related_tickets(ticket)
      show_hierarchy(ticket)
      show_dependencies(ticket)
      show_workflow_transitions(ticket)
      puts "Created: #{ticket.created_at}"
      puts "Updated: #{ticket.updated_at}"
      puts "Description:"
      puts ticket.description
      show_comments(ticket, visibility)
      show_internal_notes(ticket, visibility)
      show_watchers(ticket, visibility)
      show_attachments(ticket, visibility)
      show_custom_fields(ticket, visibility)
      show_escalation_history(ticket)
      show_duplicate_candidates(ticket)
      activity = activity_entries_for_ticket(ticket.id)
      puts "Activity:"
      if activity.empty?
        puts "  none"
      else
        activity.each do |entry|
          puts "  #{format_activity_entry(entry)}"
        end
      end
    end

    def create_ticket(args = [])
      return unless require_permission!(:ticket_write)

      template = load_template(args[0])
      if args[0] && template.nil?
        puts "Template not found."
        return
      end
      title_default = template ? template.title : ""
      description_default = template ? template.description : ""
      priority_default = template ? template.priority : "medium"
      ticket_type_default = template ? template.ticket_type : "general"
      status_default = template ? template.status : Ticket.initial_status_for(ticket_type_default)
      tags_default = template ? template.tags.join(", ") : ""
      custom_fields_default = template ? template.custom_fields : {}

      title = prompt("Title", title_default)
      description = prompt("Description", description_default)
      status = prompt("Status", status_default)
      priority = prompt("Priority", priority_default)
      ticket_type = prompt("Type (general, bug, feature, incident)", ticket_type_default)
      custom_fields = prompt_custom_fields_for_type(ticket_type, custom_fields_default)
      due_at = prompt("Due date (YYYY-MM-DD)", "")
      reminder_at = prompt("Reminder time (YYYY-MM-DD HH:MM, optional)", "")
      reminder_repeat = prompt("Reminder repeat (daily, weekly, monthly, optional)", "")
      tags = prompt("Tags (comma separated)", tags_default).split(",").map(&:strip).reject(&:empty?)
      ticket = @store.create(
        title: title,
        description: description,
        status: status,
        priority: priority,
        ticket_type: ticket_type,
        custom_fields: custom_fields,
        due_at: due_at,
        reminder_at: reminder_at,
        reminder_repeat: reminder_repeat,
        tags: tags
      )
      report_duplicate_candidates(ticket)
      log_action("ticket.create", "ticket ##{ticket.id}", title: ticket.title, status: ticket.status, priority: ticket.priority)
      puts "Created ticket ##{ticket.id}."
    rescue ArgumentError => e
      puts e.message
    end

    def show_comments(ticket, visibility)
      return unless visibility[:comments]

      puts "Comments:"
      if ticket.comments.empty?
        puts "  none"
      else
        ticket.comments.each do |comment|
          puts "  [#{comment["id"]}] #{comment["author"]} @ #{comment["created_at"]}: #{comment["body"]}"
        end
      end
    end

    def show_internal_notes(ticket, visibility)
      return unless visibility[:internal_notes]

      puts "Internal notes:"
      if ticket.internal_notes.empty?
        puts "  none"
      else
        ticket.internal_notes.each do |note|
          puts "  [#{note["id"]}] #{note["author"]} @ #{note["created_at"]}: #{note["body"]}"
        end
      end
    end

    def show_watchers(ticket, visibility)
      return unless visibility[:watchers]

      puts "Watchers:"
      if ticket.watchers.empty?
        puts "  none"
      else
        ticket.watchers.each do |watcher_id|
          user = @users.find(watcher_id)
          label = user ? user.display_name : "user ##{watcher_id}"
          puts "  - #{label}"
        end
      end
    end

    def show_attachments(ticket, visibility)
      return unless visibility[:attachments]

      puts "Attachments:"
      if ticket.attachments.empty?
        puts "  none"
      else
        ticket.attachments.each do |attachment|
          details = [
            attachment["content_type"].to_s.empty? ? nil : attachment["content_type"],
            attachment["size"].to_i.zero? ? nil : "#{attachment["size"]} bytes",
            attachment["description"].to_s.empty? ? nil : attachment["description"]
          ].compact.join(" | ")
          details = " | #{details}" unless details.empty?
          puts "  [#{attachment["id"]}] #{attachment["name"]}#{details} (by #{attachment["uploaded_by"]} @ #{attachment["created_at"]})"
        end
      end
    end

    def show_custom_fields(ticket, visibility)
      return unless visibility[:custom_fields]

      puts "Custom fields:"
      if ticket.custom_fields.empty?
        puts "  none"
      else
        ticket.custom_fields.each do |key, value|
          puts "  #{key}: #{value}"
        end
      end
    end

    def edit_ticket(args)
      return unless require_permission!(:ticket_write)

      id = required_id(args)
      ticket = @store.find(id)
      return puts "Ticket not found." unless ticket

      attrs = {}
      attrs[:title] = prompt("Title", ticket.title)
      attrs[:description] = prompt("Description", ticket.description)
      attrs[:status] = prompt("Status", ticket.status)
      attrs[:priority] = prompt("Priority", ticket.priority)
      attrs[:ticket_type] = prompt("Type (general, bug, feature, incident)", ticket.ticket_type || "general")
      attrs[:custom_fields] = prompt_custom_fields_for_type(attrs[:ticket_type], ticket.custom_fields)
      attrs[:due_at] = prompt("Due date (YYYY-MM-DD)", ticket.due_at || "")
      attrs[:reminder_at] = prompt("Reminder time (YYYY-MM-DD HH:MM, optional)", ticket.reminder_at || "")
      attrs[:reminder_repeat] = prompt("Reminder repeat (daily, weekly, monthly, optional)", ticket.reminder_repeat || "")
      attrs[:tags] = prompt("Tags (comma separated)", ticket.tags.join(", ")).split(",").map(&:strip).reject(&:empty?)
      @store.update(id, attrs, actor_role: @current_user&.role_label)
      log_action("ticket.update", "ticket ##{id}", title: attrs[:title], status: attrs[:status], priority: attrs[:priority])
      puts "Updated ticket ##{id}."
    rescue ArgumentError => e
      puts e.message
    end

    def delete_ticket(args)
      return unless require_permission!(:ticket_write)

      id = required_id(args)
      if @store.delete(id)
        log_action("ticket.delete", "ticket ##{id}")
        puts "Soft-deleted ticket ##{id}."
      else
        puts "Ticket not found."
      end
    end

    def restore_ticket(args)
      return unless require_permission!(:ticket_write)

      id = required_id(args)
      if @store.restore(id)
        log_action("ticket.restore", "ticket ##{id}")
        puts "Restored ticket ##{id}."
      else
        puts "Ticket not found."
      end
    end

    def close_tickets(args)
      return unless require_permission!(:ticket_write)

      ids = args.map { |arg| arg.to_i }.reject(&:zero?)
      if ids.empty?
        puts "Usage: close ID [ID ...]"
        return
      end

      blocked_ids = ids.select do |id|
        ticket = @store.find(id)
        ticket && !@store.closeable_ticket?(ticket)
      end
      closed_ids = @store.bulk_close(ids, actor_role: @current_user&.role_label)
      if closed_ids.empty? && blocked_ids.empty?
        puts "No matching tickets found."
      else
        if blocked_ids.any?
          puts "Blocked by open dependencies: #{blocked_ids.map { |id| "##{id}" }.join(", ")}"
        end
        closed_ids.each { |ticket_id| log_action("ticket.close", "ticket ##{ticket_id}") }
        puts "Closed tickets: #{closed_ids.map { |id| "##{id}" }.join(", ")}" if closed_ids.any?
      end
    end

    def undo(args)
      return unless require_permission!(:ticket_write)

      action = args[0]
      return puts "Usage: undo" if action && action != "last"

      entry = @store.undo_last_bulk_action
      unless entry
        puts "No bulk actions to undo."
        return
      end

      log_action("bulk.undo", "bulk action ##{entry["id"]}", action: entry["action"])
      puts "Undid #{entry["action"].to_s.tr('_', ' ')}."
    end

    def merge_tickets(args)
      return unless require_permission!(:ticket_write)

      source_id = args[0]
      target_id = args[1]
      if source_id.to_s.strip.empty? || target_id.to_s.strip.empty?
        puts "Usage: merge SOURCE_ID TARGET_ID"
        return
      end

      result = @store.merge(source_id, target_id)
      unless result
        puts "Ticket not found."
        return
      end

      log_action("ticket.merge", "ticket ##{source_id} -> ##{target_id}", source: source_id.to_i, target: target_id.to_i)
      puts "Merged ticket ##{source_id} into ##{target_id}."
    rescue ArgumentError => e
      puts e.message
    end

    def manage_relationships(args)
      return unless require_permission!(:ticket_write)

      action = args[0]
      case action
      when "add"
        source_id = args[1]
        target_id = args[2]
        if source_id.to_s.strip.empty? || target_id.to_s.strip.empty?
          puts "Usage: relate add SOURCE_ID TARGET_ID"
          return
        end

        result = @store.relate(source_id, target_id)
        unless result
          puts "Ticket not found."
          return
        end

        log_action("ticket.relate", "ticket ##{source_id} <-> ##{target_id}", source: source_id.to_i, target: target_id.to_i)
        puts "Related ticket ##{source_id} with ##{target_id}."
      when "remove"
        source_id = args[1]
        target_id = args[2]
        if source_id.to_s.strip.empty? || target_id.to_s.strip.empty?
          puts "Usage: relate remove SOURCE_ID TARGET_ID"
          return
        end

        result = @store.unrelate(source_id, target_id)
        unless result
          puts "Ticket not found."
          return
        end

        log_action("ticket.unrelate", "ticket ##{source_id} <-> ##{target_id}", source: source_id.to_i, target: target_id.to_i)
        puts "Removed relationship between ticket ##{source_id} and ##{target_id}."
      when "list"
        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        related = @store.related_tickets(ticket)
        if related.empty?
          puts "No related tickets."
        else
          related.each { |related_ticket| puts format_ticket_row(related_ticket) }
        end
      else
        puts "Usage: relate add SOURCE_ID TARGET_ID | relate remove SOURCE_ID TARGET_ID | relate list ID"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_hierarchy(args)
      return unless require_permission!(:ticket_write)

      action = args[0]
      case action
      when "set"
        child_id = args[1]
        parent_id = args[2]
        if child_id.to_s.strip.empty? || parent_id.to_s.strip.empty?
          puts "Usage: parent set CHILD_ID PARENT_ID"
          return
        end

        result = @store.set_parent(child_id, parent_id)
        unless result
          puts "Ticket not found."
          return
        end

        log_action("ticket.parent_set", "ticket ##{child_id} -> ##{parent_id}", child: child_id.to_i, parent: parent_id.to_i)
        puts "Set ticket ##{parent_id} as parent of ##{child_id}."
      when "clear"
        id = args[1]
        if id.to_s.strip.empty?
          puts "Usage: parent clear ID"
          return
        end

        result = @store.clear_parent(id)
        unless result
          puts "Ticket not found."
          return
        end

        log_action("ticket.parent_clear", "ticket ##{id}", child: id.to_i, parent: result[:parent]&.id)
        puts "Cleared parent for ticket ##{id}."
      when "list"
        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        parent = @store.parent_ticket(ticket)
        children = @store.child_tickets(ticket)
        puts "Parent:"
        puts parent ? "  #{format_ticket_row(parent)}" : "  none"
        puts "Children:"
        if children.empty?
          puts "  none"
        else
          children.each { |child| puts "  #{format_ticket_row(child)}" }
        end
      else
        puts "Usage: parent set CHILD_ID PARENT_ID | parent clear ID | parent list ID"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_dependencies(args)
      return unless require_permission!(:ticket_write)

      action = args[0]
      case action
      when "add"
        ticket_id = args[1]
        dependency_id = args[2]
        if ticket_id.to_s.strip.empty? || dependency_id.to_s.strip.empty?
          puts "Usage: dependency add ID DEPENDENCY_ID"
          return
        end

        result = @store.add_dependency(ticket_id, dependency_id)
        unless result
          puts "Ticket not found."
          return
        end

        log_action("ticket.dependency_add", "ticket ##{ticket_id} depends on ##{dependency_id}", ticket: ticket_id.to_i, dependency: dependency_id.to_i)
        puts "Added dependency ##{dependency_id} to ticket ##{ticket_id}."
      when "remove"
        ticket_id = args[1]
        dependency_id = args[2]
        if ticket_id.to_s.strip.empty? || dependency_id.to_s.strip.empty?
          puts "Usage: dependency remove ID DEPENDENCY_ID"
          return
        end

        result = @store.remove_dependency(ticket_id, dependency_id)
        unless result
          puts "Ticket not found."
          return
        end

        log_action("ticket.dependency_remove", "ticket ##{ticket_id} depends on ##{dependency_id}", ticket: ticket_id.to_i, dependency: dependency_id.to_i)
        puts "Removed dependency ##{dependency_id} from ticket ##{ticket_id}."
      when "list"
        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        dependencies = @store.dependencies_for(ticket)
        dependents = @store.dependent_tickets(ticket)
        puts "Depends on:"
        if dependencies.empty?
          puts "  none"
        else
          dependencies.each { |dependency| puts "  #{format_ticket_row(dependency)}" }
        end
        puts "Blocked by:"
        if dependents.empty?
          puts "  none"
        else
          dependents.each { |dependent| puts "  #{format_ticket_row(dependent)}" }
        end
      else
        puts "Usage: dependency add ID DEPENDENCY_ID | dependency remove ID DEPENDENCY_ID | dependency list ID"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def change_status(args)
      return unless require_permission!(:ticket_write)

      id = required_id(args)
      status = args[1]
      ticket = @store.update(id, { status: status }, actor_role: @current_user&.role_label)
      if ticket
        log_action("ticket.status", "ticket ##{id}", status: ticket.status)
        puts "Updated ticket ##{id} to #{ticket.status}."
      else
        puts "Ticket not found."
      end
    rescue ArgumentError => e
      puts e.message
    end

    def add_comment(args)
      return unless require_permission!(:ticket_write)

      id = required_id(args)
      ticket = @store.find(id)
      return puts "Ticket not found." unless ticket

      body = args.drop(1).join(" ")
      body = prompt("Comment") if body.strip.empty?
      ticket.add_comment(body: body, author: prompt("Author", current_user_name))
      @store.save_ticket(ticket)
      send_email_notifications(ticket, subject: "Comment added to ticket ##{ticket.id}", body: body, event: "comments")
      log_action("ticket.comment", "ticket ##{id}", author: current_user_name)
      puts "Added comment to ticket ##{id}."
    end

    def add_note(args)
      return unless require_permission!(:ticket_write)

      id = required_id(args)
      ticket = @store.find(id)
      return puts "Ticket not found." unless ticket

      body = args.drop(1).join(" ")
      body = prompt("Note") if body.strip.empty?
      ticket.add_internal_note(body: body, author: prompt("Author", current_user_name))
      @store.save_ticket(ticket)
      log_action("ticket.note", "ticket ##{id}", author: current_user_name)
      puts "Added internal note to ticket ##{id}."
    end

    def manage_watchers(args)
      return unless require_permission!(:ticket_write)

      action = args[0]
      case action
      when "add"
        id = required_id(args.drop(1))
        user = @users.find(required_id(args.drop(2)))
        return puts "User not found." unless user

        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        ticket.add_watcher(user.id)
        @store.save_ticket(ticket)
        log_action("ticket.watch_add", "ticket ##{id}", watcher: user.display_name)
        puts "Added watcher #{user.display_name} to ticket ##{id}."
      when "remove"
        id = required_id(args.drop(1))
        user = @users.find(required_id(args.drop(2)))
        return puts "User not found." unless user

        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        ticket.remove_watcher(user.id)
        @store.save_ticket(ticket)
        log_action("ticket.watch_remove", "ticket ##{id}", watcher: user.display_name)
        puts "Removed watcher #{user.display_name} from ticket ##{id}."
      when "list"
        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        if ticket.watchers.empty?
          puts "No watchers."
        else
          ticket.watchers.each do |watcher_id|
            user = @users.find(watcher_id)
            puts user ? "#{user.display_name} (##{user.id})" : "user ##{watcher_id}"
          end
        end
      else
        puts "Usage: watch add ID USER_ID | watch remove ID USER_ID | watch list ID"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_attachments(args)
      return unless require_permission!(:ticket_write)

      action = args[0]
      case action
      when "add"
        id = required_id(args.drop(1))
        name = args[2]
        content_type = args[3] || ""
        size = args[4] || "0"
        description = args.drop(5).join(" ")
        return puts "Usage: attach add ID NAME [CONTENT_TYPE] [SIZE] [DESCRIPTION]" if name.to_s.strip.empty?

        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        ticket.add_attachment(
          name: name,
          content_type: content_type,
          size: size,
          description: description,
          uploaded_by: current_user_name
        )
        @store.save_ticket(ticket)
        log_action("ticket.attach_add", "ticket ##{id}", attachment: name)
        puts "Added attachment #{name} to ticket ##{id}."
      when "remove"
        id = required_id(args.drop(1))
        attachment_id = args[2]
        return puts "Usage: attach remove ID ATTACHMENT_ID" if attachment_id.to_s.strip.empty?

        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        unless ticket.remove_attachment(attachment_id)
          puts "Attachment not found."
          return
        end
        @store.save_ticket(ticket)
        log_action("ticket.attach_remove", "ticket ##{id}", attachment_id: attachment_id.to_i)
        puts "Removed attachment ##{attachment_id} from ticket ##{id}."
      when "list"
        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        if ticket.attachments.empty?
          puts "No attachments."
        else
          ticket.attachments.each do |attachment|
            puts "##{attachment['id']} #{attachment['name']}"
          end
        end
      else
        puts "Usage: attach add ID NAME [CONTENT_TYPE] [SIZE] [DESCRIPTION] | attach remove ID ATTACHMENT_ID | attach list ID"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_pins(args)
      return unless require_permission!(:ticket_write)

      action = args[0]
      case action
      when "add"
        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        ticket.pin!
        @store.save_ticket(ticket)
        log_action("ticket.pin", "ticket ##{id}")
        puts "Pinned ticket ##{id}."
      when "remove"
        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        ticket.unpin!
        @store.save_ticket(ticket)
        log_action("ticket.unpin", "ticket ##{id}")
        puts "Unpinned ticket ##{id}."
      when "list"
        tickets = @store.all.select(&:pinned?)
        if tickets.empty?
          puts "No pinned tickets."
        else
          tickets.sort_by { |ticket| [ticket.updated_at.to_s, ticket.created_at.to_s] }.reverse.each do |ticket|
            puts format_ticket_row(ticket)
          end
        end
      else
        puts "Usage: pin add ID | pin remove ID | pin list"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_archives(args)
      return unless require_permission!(:ticket_write)

      action = args[0]
      case action
      when "add"
        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        ticket.archive!
        @store.save_ticket(ticket)
        log_action("ticket.archive", "ticket ##{id}")
        puts "Archived ticket ##{id}."
      when "remove"
        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        ticket.unarchive!
        @store.save_ticket(ticket)
        log_action("ticket.unarchive", "ticket ##{id}")
        puts "Unarchived ticket ##{id}."
      when "list"
        tickets = @store.all.select(&:archived?)
        if tickets.empty?
          puts "No archived tickets."
        else
          tickets.sort_by { |ticket| [ticket.updated_at.to_s, ticket.created_at.to_s] }.reverse.each do |ticket|
            puts format_ticket_row(ticket)
          end
        end
      else
        puts "Usage: archive add ID | archive remove ID | archive list"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_custom_fields(args)
      return unless require_permission!(:ticket_write)

      action = args[0]
      case action
      when "set"
        id = required_id(args.drop(1))
        key = args[2]
        value = args.drop(3).join(" ")
        return puts "Usage: field set ID KEY VALUE" if key.to_s.strip.empty? || value.to_s.strip.empty?

        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        ticket.set_custom_field(key, value)
        @store.save_ticket(ticket)
        log_action("ticket.field_set", "ticket ##{id}", key: key, value: value)
        puts "Set custom field #{key} on ticket ##{id}."
      when "remove"
        id = required_id(args.drop(1))
        key = args[2]
        return puts "Usage: field remove ID KEY" if key.to_s.strip.empty?

        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        ticket.remove_custom_field(key)
        @store.save_ticket(ticket)
        log_action("ticket.field_remove", "ticket ##{id}", key: key)
        puts "Removed custom field #{key} from ticket ##{id}."
      when "list"
        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        if ticket.custom_fields.empty?
          puts "No custom fields."
        else
          ticket.custom_fields.each do |key, value|
            puts "#{key}: #{value}"
          end
        end
      else
        puts "Usage: field set ID KEY VALUE | field remove ID KEY | field list ID"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_templates(args)
      action = args[0]
      case action
      when "list"
        list_templates
      when "show"
        show_template(args.drop(1))
      when "add"
        return unless require_permission!(:admin)

        add_template
      when "edit"
        return unless require_permission!(:admin)

        edit_template(args.drop(1))
      when "delete"
        return unless require_permission!(:admin)

        delete_template(args.drop(1))
      else
        puts "Usage: template list | template show NAME | template add | template edit NAME | template delete NAME"
      end
    end

    def list_templates
      templates = @templates.all
      if templates.empty?
        puts "No templates found."
        return
      end

      templates.each do |template|
        puts "##{template.name} [#{template.ticket_type}] #{template.title}"
      end
    end

    def show_template(args)
      name = args[0].to_s.strip
      if name.empty?
        puts "Usage: template show NAME"
        return
      end

      template = @templates.find(name)
      unless template
        puts "Template not found."
        return
      end

      puts "Name: #{template.name}"
      puts "Type: #{template.ticket_type}"
      puts "Title: #{template.title}"
      puts "Description: #{template.description}"
      puts "Status: #{template.status}"
      puts "Priority: #{template.priority}"
      puts "Tags: #{template.tags.join(", ")}"
      puts "Custom fields:"
      if template.custom_fields.empty?
        puts "  none"
      else
        template.custom_fields.each { |key, value| puts "  #{key}: #{value}" }
      end
    end

    def add_template
      name = prompt("Template name")
      ticket_type = prompt("Ticket type (general, bug, feature, incident)", "general")
      title = prompt("Title", "")
      description = prompt("Description", "")
      status = prompt("Status", Ticket.initial_status_for(ticket_type))
      priority = prompt("Priority", "medium")
      tags = prompt("Tags (comma separated)", "").split(",").map(&:strip).reject(&:empty?)
      custom_fields = prompt_custom_fields_for_type(ticket_type)
      template = @templates.create(
        name: name,
        ticket_type: ticket_type,
        title: title,
        description: description,
        status: status,
        priority: priority,
        tags: tags,
        custom_fields: custom_fields
      )
      log_action("template.create", "template #{template.name}", ticket_type: template.ticket_type)
      puts "Created template #{template.name}."
    rescue ArgumentError => e
      puts e.message
    end

    def edit_template(args)
      name = args[0].to_s.strip
      if name.empty?
        puts "Usage: template edit NAME"
        return
      end

      template = @templates.find(name)
      unless template
        puts "Template not found."
        return
      end

      attrs = {}
      attrs[:name] = prompt("Template name", template.name)
      attrs[:ticket_type] = prompt("Ticket type (general, bug, feature, incident)", template.ticket_type)
      attrs[:title] = prompt("Title", template.title)
      attrs[:description] = prompt("Description", template.description)
      attrs[:status] = prompt("Status", template.status)
      attrs[:priority] = prompt("Priority", template.priority)
      attrs[:tags] = prompt("Tags (comma separated)", template.tags.join(", ")).split(",").map(&:strip).reject(&:empty?)
      attrs[:custom_fields] = prompt_custom_fields_for_type(attrs[:ticket_type], template.custom_fields)
      template = @templates.update(name, attrs)
      log_action("template.update", "template #{template.name}", ticket_type: template.ticket_type)
      puts "Updated template #{template.name}."
    rescue ArgumentError => e
      puts e.message
    end

    def delete_template(args)
      name = args[0].to_s.strip
      if name.empty?
        puts "Usage: template delete NAME"
        return
      end

      if @templates.delete(name)
        log_action("template.delete", "template #{name}")
        puts "Deleted template #{name}."
      else
        puts "Template not found."
      end
    end

    def load_template(name)
      return nil if name.to_s.strip.empty?

      @templates.find(name)
    end

    def prompt_custom_fields_for_type(ticket_type, existing_fields = {})
      fields = existing_fields.is_a?(Hash) ? existing_fields.dup : {}
      required_custom_fields(ticket_type).each do |key, label|
        fields[key] = prompt("#{label}", fields[key].to_s)
      end
      fields
    end

    def required_custom_fields(ticket_type)
      case ticket_type.to_s.strip.downcase
      when "bug"
        { "severity" => "Severity (bug)" }
      when "feature"
        { "requested_by" => "Requested by (feature)" }
      when "incident"
        { "impact" => "Impact (incident)" }
      else
        {}
      end
    end

    def manage_tags(args)
      return unless require_permission!(:ticket_write)

      action = args[0]
      case action
      when "add", "remove"
        tag = args.pop
        ids = args.drop(1)
        if ids.empty? || tag.to_s.strip.empty?
          puts "Usage: tag add|remove ID [ID ...] TAG"
          return
        end

        touched_ids = @store.bulk_tag(ids, tag, action: action)
        if touched_ids.empty?
          puts "No matching tickets found."
        else
          touched_ids.each { |ticket_id| log_action("ticket.tag.#{action}", "ticket ##{ticket_id}", tag: tag) }
          verb = action == "add" ? "Added" : "Removed"
          puts "#{verb} tag for tickets: #{touched_ids.map { |id| "##{id}" }.join(", ")}"
        end
      else
        puts "Usage: tag add|remove ID [ID ...] TAG"
      end
    end

    def search(args)
      action = args[0]
      case action
      when "save"
        save_search(args.drop(1))
      when "run"
        run_saved_search(args.drop(1))
      when "delete"
        delete_saved_search(args.drop(1))
      else
        perform_search(args.join(" "))
      end
    end

    def list_saved_searches
      searches = @current_user.saved_searches || []
      if searches.empty?
        puts "No saved searches."
        return
      end

      searches.each do |search|
        puts "#{search["name"]}: #{search["query"]}"
      end
    end

    def list_favorite_filters
      filters = @current_user.favorite_filters || []
      if filters.empty?
        puts "No favorite filters."
        return
      end

      filters.each do |filter|
        puts "#{filter["name"]}: #{format_filter_options(filter["options"])}"
      end
    end

    def save_search(args)
      name = args[0].to_s.strip
      query = args.drop(1).join(" ").strip
      if name.empty? || query.empty?
        puts "Usage: search save NAME QUERY"
        return
      end

      searches = (@current_user.saved_searches || []).dup
      existing = searches.index { |search| search["name"].to_s.casecmp?(name) }
      payload = {
        "name" => name,
        "query" => query,
        "created_at" => existing ? searches[existing]["created_at"] : Time.now.utc.iso8601,
        "updated_at" => Time.now.utc.iso8601
      }
      if existing
        searches[existing] = payload
      else
        searches << payload
      end

      persist_saved_searches(searches)
      log_action("user.saved_searches", "user ##{@current_user.id}", saved_searches: searches.map { |search| search["name"] })
      puts "Saved search #{name}."
    end

    def filter(args)
      action = args[0]
      case action
      when "save"
        save_favorite_filter(args.drop(1))
      when "run"
        run_favorite_filter(args.drop(1))
      when "delete"
        delete_favorite_filter(args.drop(1))
      else
        puts "Usage: filter save NAME [list options] | filter run NAME | filter delete NAME"
      end
    end

    def save_favorite_filter(args)
      name = args[0].to_s.strip
      option_args = args.drop(1)
      if name.empty? || option_args.empty?
        puts "Usage: filter save NAME [list options]"
        return
      end

      options = parse_options(option_args)
      filters = (@current_user.favorite_filters || []).dup
      existing = filters.index { |filter| filter["name"].to_s.casecmp?(name) }
      payload = {
        "name" => name,
        "options" => options,
        "created_at" => existing ? filters[existing]["created_at"] : Time.now.utc.iso8601,
        "updated_at" => Time.now.utc.iso8601
      }
      if existing
        filters[existing] = payload
      else
        filters << payload
      end

      persist_favorite_filters(filters)
      log_action("user.favorite_filters", "user ##{@current_user.id}", favorite_filters: filters.map { |filter| filter["name"] })
      puts "Saved favorite filter #{name}."
    end

    def run_favorite_filter(args)
      name = args[0].to_s.strip
      if name.empty?
        puts "Usage: filter run NAME"
        return
      end

      filter = (@current_user.favorite_filters || []).find { |entry| entry["name"].to_s.casecmp?(name) }
      unless filter
        puts "Favorite filter not found."
        return
      end

      tickets = filter_tickets(@store.all, filter["options"] || {})
      if tickets.empty?
        puts "No tickets found."
      else
        tickets.each { |ticket| puts format_ticket_row(ticket) }
      end
    end

    def delete_favorite_filter(args)
      name = args[0].to_s.strip
      if name.empty?
        puts "Usage: filter delete NAME"
        return
      end

      filters = (@current_user.favorite_filters || []).dup
      before = filters.length
      filters.reject! { |filter| filter["name"].to_s.casecmp?(name) }
      if filters.length == before
        puts "Favorite filter not found."
        return
      end

      persist_favorite_filters(filters)
      log_action("user.favorite_filters", "user ##{@current_user.id}", favorite_filters: filters.map { |filter| filter["name"] })
      puts "Deleted favorite filter #{name}."
    end

    def persist_favorite_filters(filters)
      updated_user = @users.update(@current_user.id, favorite_filters: filters)
      if updated_user
        @current_user = updated_user
      else
        @current_user.favorite_filters = filters
        @users.save_user(@current_user)
      end
    end

    def run_saved_search(args)
      name = args[0].to_s.strip
      if name.empty?
        puts "Usage: search run NAME"
        return
      end

      search = (@current_user.saved_searches || []).find { |entry| entry["name"].to_s.casecmp?(name) }
      unless search
        puts "Saved search not found."
        return
      end

      perform_search(search["query"])
    end

    def delete_saved_search(args)
      name = args[0].to_s.strip
      if name.empty?
        puts "Usage: search delete NAME"
        return
      end

      searches = (@current_user.saved_searches || []).dup
      before = searches.length
      searches.reject! { |search| search["name"].to_s.casecmp?(name) }
      if searches.length == before
        puts "Saved search not found."
        return
      end

      persist_saved_searches(searches)
      log_action("user.saved_searches", "user ##{@current_user.id}", saved_searches: searches.map { |search| search["name"] })
      puts "Deleted saved search #{name}."
    end

    def perform_search(query)
      query = query.to_s.strip.downcase
      if query.empty?
        puts "Usage: search QUERY"
        return
      end

      matches = @store.all.select do |ticket|
        haystack = [
          ticket.title,
          ticket.description,
          ticket.ticket_type,
          ticket.status,
          ticket.priority,
          ticket.tags.join(" "),
          ticket.comments.map { |comment| comment["body"] }.join(" "),
          ticket.attachments.map { |attachment| [attachment["name"], attachment["description"], attachment["content_type"]].join(" ") }.join(" "),
          ticket.custom_fields.map { |key, value| "#{key} #{value}" }.join(" ")
        ].join(" ").downcase
        haystack.include?(query)
      end

      if matches.empty?
        puts "No tickets found."
      else
        matches.each { |ticket| puts format_ticket_row(ticket) }
      end
    end

    def persist_saved_searches(searches)
      updated_user = @users.update(@current_user.id, saved_searches: searches)
      if updated_user
        @current_user = updated_user
      else
        @current_user.saved_searches = searches
        @users.save_user(@current_user)
      end
    end

    def dashboard
      tickets = @store.all
      counts = tickets.group_by(&:status).transform_values(&:count)
      priority_counts = tickets.group_by(&:priority).transform_values(&:count)
      escalation_count = tickets.count(&:escalation_needed?)
      duplicate_groups = @store.duplicate_groups
      sla_warning_count = tickets.count { |ticket| ticket.sla_status == "warning" }
      sla_breach_count = tickets.count { |ticket| ticket.sla_status == "breached" }
      recent_tickets = tickets.sort_by { |ticket| ticket.updated_at.to_s }.reverse.take(5)
      open_tickets = tickets.select { |ticket| %w[open in_progress waiting].include?(ticket.status) }
      oldest_open_ticket = open_tickets.min_by { |ticket| ticket.created_at.to_s }
      tag_counts = tickets.flat_map(&:tags).tally.sort_by { |tag, count| [-count, tag] }.first(5)

      puts "Dashboard"
      puts "Total tickets: #{tickets.count}"
      puts "Open: #{counts.fetch("open", 0)}"
      puts "In progress: #{counts.fetch("in_progress", 0)}"
      puts "Waiting: #{counts.fetch("waiting", 0)}"
      puts "Resolved: #{counts.fetch("resolved", 0)}"
      puts "Closed: #{counts.fetch("closed", 0)}"
      puts "Overdue: #{tickets.count(&:overdue?)}"
      puts "Due reminders: #{tickets.count(&:reminder_due?)}"
      puts "Escalations needed: #{escalation_count}"
      puts "Duplicate groups: #{duplicate_groups.count}"
      puts "SLA warnings: #{sla_warning_count}"
      puts "SLA breaches: #{sla_breach_count}"
      puts "Total comments: #{tickets.sum { |ticket| ticket.comments.count }}"
      puts "Priority breakdown:"
      Ticket::PRIORITIES.each do |priority|
        puts "  #{priority}: #{priority_counts.fetch(priority, 0)}"
      end
      puts "Recent updates:"
      if recent_tickets.empty?
        puts "  none"
      else
        recent_tickets.each do |ticket|
          puts "  ##{ticket.id} #{ticket.title} (updated #{ticket.updated_at})"
        end
      end
      if oldest_open_ticket
        puts "Oldest open ticket: ##{oldest_open_ticket.id} #{oldest_open_ticket.title} (created #{oldest_open_ticket.created_at})"
      else
        puts "Oldest open ticket: none"
      end
      puts "Top tags:"
      if tag_counts.empty?
        puts "  none"
      else
        tag_counts.each do |tag, count|
          puts "  #{tag}: #{count}"
        end
      end
    end

    alias stats dashboard

    def analytics(args)
      action = args[0]
      case action
      when nil, "summary"
        analytics_summary
      when "status"
        analytics_status
      when "aging"
        analytics_aging
      when "trend"
        analytics_trend
      else
        puts "Usage: analytics [summary|status|aging|trend]"
      end
    end

    def report(args)
      action = args[0]
      case action
      when "daily", nil
        report_daily(args[1])
      when "weekly"
        report_weekly(args[1])
      else
        puts "Usage: report daily [DATE] | report weekly [DATE]"
      end
    end

    def manage_sorting(args)
      action = args[0]
      case action
      when nil, "show"
        show_sort_rules
      when "set"
        return unless require_permission!(:admin)

        fields = args.drop(1)
        return puts "Usage: sort rules set FIELD [FIELD ...]" if fields.empty?

        rule = @sort_rules.set(fields)
        log_action("sort.rules_set", "sort", fields: rule)
        puts "Updated custom sort rule."
      when "reset"
        return unless require_permission!(:admin)

        rule = @sort_rules.reset
        log_action("sort.rules_reset", "sort", fields: rule)
        puts "Reset custom sort rule."
      when "rules"
        manage_sort_rules(args.drop(1))
      else
        puts "Usage: sort rules show | sort rules set FIELD [FIELD ...] | sort rules reset"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_workflows(args)
      action = args[0]
      case action
      when nil, "show"
        show_workflows
      when "set"
        return unless require_permission!(:admin)

        ticket_type = args[1].to_s.strip
        statuses = args.drop(2)
        if ticket_type.empty? || statuses.empty?
          puts "Usage: workflow set TYPE STATUS [STATUS ...]"
          return
        end

        workflow = @workflows.upsert(ticket_type, statuses: statuses)
        reload_ticket_workflows!
        log_action("workflow.set", "workflow #{ticket_type}", workflow: workflow["statuses"])
        puts "Updated workflow #{ticket_type}."
      when "reset"
        return unless require_permission!(:admin)

        target = args[1].to_s.strip
        target = "all" if target.empty?
        @workflows.reset(target)
        reload_ticket_workflows!
        log_action("workflow.reset", "workflow #{target}", workflow: target)
        puts target == "all" ? "Reset all workflows." : "Reset workflow #{target}."
      when "transitions"
        manage_workflow_transitions(args.drop(1))
      when "permissions"
        manage_workflow_permissions(args.drop(1))
      else
        puts "Usage: workflow show | workflow set TYPE STATUS [STATUS ...] | workflow reset [TYPE|all] | workflow transitions show TYPE | workflow transitions set TYPE FROM STATUS [STATUS ...] | workflow transitions reset [TYPE|all] | workflow permissions show TYPE | workflow permissions set TYPE FROM TO ROLE [ROLE ...] | workflow permissions reset [TYPE|all]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def duplicates(args)
      options = parse_duplicate_options(args)
      if options[:ticket]
        ticket = @store.find(options[:ticket])
        return puts "Ticket not found." unless ticket

        candidates = @store.duplicate_candidates_for(ticket)
        if candidates.empty?
          puts "No duplicate candidates for ticket ##{ticket.id}."
        else
          puts "Duplicate candidates for ticket ##{ticket.id}:"
          candidates.each { |candidate| puts "  #{format_ticket_row(candidate)}" }
        end
        return
      end

      groups = @store.duplicate_groups
      if groups.empty?
        puts "No duplicate tickets found."
        return
      end

      groups.each_with_index do |group, index|
        puts "Group #{index + 1}:"
        group.each { |ticket| puts "  #{format_ticket_row(ticket)}" }
      end
    end

    def manage_sort_rules(args)
      action = args[0]
      case action
      when nil, "show"
        show_sort_rules
      when "set"
        return unless require_permission!(:admin)

        fields = args.drop(1)
        return puts "Usage: sort rules set FIELD [FIELD ...]" if fields.empty?

        rule = @sort_rules.set(fields)
        log_action("sort.rules_set", "sort", fields: rule)
        puts "Updated custom sort rule."
      when "reset"
        return unless require_permission!(:admin)

        rule = @sort_rules.reset
        log_action("sort.rules_reset", "sort", fields: rule)
        puts "Reset custom sort rule."
      else
        puts "Usage: sort rules show | sort rules set FIELD [FIELD ...] | sort rules reset"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def show_workflows
      workflows = @workflows.all
      if workflows.empty?
        puts "No workflows."
        return
      end

      workflows.each do |workflow|
        transitions = format_workflow_transitions(workflow["transitions"] || {})
        permissions = format_workflow_permissions(workflow["permissions"] || {})
        puts "#{workflow["ticket_type"]}: #{workflow["statuses"].join(", ")} (initial: #{workflow["initial_status"]})"
        puts "  transitions: #{transitions}"
        puts "  permissions: #{permissions}"
      end
    end

    def manage_workflow_transitions(args)
      action = args[0]
      case action
      when "show"
        ticket_type = args[1].to_s.strip
        if ticket_type.empty?
          puts "Usage: workflow transitions show TYPE"
          return
        end

        workflow = @workflows.find(ticket_type)
        return puts "Workflow not found." unless workflow

        puts "#{workflow["ticket_type"]}:"
        puts "  #{format_workflow_transitions(workflow["transitions"] || {})}"
      when "set"
        return unless require_permission!(:admin)

        ticket_type = args[1].to_s.strip
        from_status = args[2].to_s.strip
        next_statuses = args.drop(3)
        if ticket_type.empty? || from_status.empty? || next_statuses.empty?
          puts "Usage: workflow transitions set TYPE FROM STATUS [STATUS ...]"
          return
        end

        workflow = @workflows.set_transition(ticket_type, from_status, next_statuses)
        return puts "Workflow not found." unless workflow

        reload_ticket_workflows!
        log_action("workflow.transitions_set", "workflow #{ticket_type}", from: from_status, to: next_statuses)
        puts "Updated transitions for workflow #{ticket_type}."
      when "reset"
        return unless require_permission!(:admin)

        target = args[1].to_s.strip
        target = "all" if target.empty?
        result = @workflows.reset_transitions(target)
        return puts "Workflow not found." if result.nil? && target != "all"

        reload_ticket_workflows!
        log_action("workflow.transitions_reset", "workflow #{target}", workflow: target)
        puts target == "all" ? "Reset workflow transitions for all workflows." : "Reset workflow transitions for #{target}."
      else
        puts "Usage: workflow transitions show TYPE | workflow transitions set TYPE FROM STATUS [STATUS ...] | workflow transitions reset [TYPE|all]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_workflow_permissions(args)
      action = args[0]
      case action
      when "show"
        ticket_type = args[1].to_s.strip
        if ticket_type.empty?
          puts "Usage: workflow permissions show TYPE"
          return
        end

        workflow = @workflows.find(ticket_type)
        return puts "Workflow not found." unless workflow

        puts "#{workflow["ticket_type"]}:"
        puts "  #{format_workflow_permissions(workflow["permissions"] || {})}"
      when "set"
        return unless require_permission!(:admin)

        ticket_type = args[1].to_s.strip
        from_status = args[2].to_s.strip
        to_status = args[3].to_s.strip
        roles = args.drop(4)
        if ticket_type.empty? || from_status.empty? || to_status.empty? || roles.empty?
          puts "Usage: workflow permissions set TYPE FROM TO ROLE [ROLE ...]"
          return
        end

        workflow = @workflows.set_transition_permission(ticket_type, from_status, to_status, roles)
        return puts "Workflow not found." unless workflow

        reload_ticket_workflows!
        log_action("workflow.permissions_set", "workflow #{ticket_type}", from: from_status, to: to_status, roles: roles)
        puts "Updated transition permissions for workflow #{ticket_type}."
      when "reset"
        return unless require_permission!(:admin)

        target = args[1].to_s.strip
        target = "all" if target.empty?
        result = @workflows.reset_transition_permissions(target)
        return puts "Workflow not found." if result.nil? && target != "all"

        reload_ticket_workflows!
        log_action("workflow.permissions_reset", "workflow #{target}", workflow: target)
        puts target == "all" ? "Reset transition permissions for all workflows." : "Reset transition permissions for #{target}."
      else
        puts "Usage: workflow permissions show TYPE | workflow permissions set TYPE FROM TO ROLE [ROLE ...] | workflow permissions reset [TYPE|all]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def reload_ticket_workflows!
      Ticket.workflows = @workflows.to_workflow_hash
    end

    def show_workflow_transitions(ticket)
      next_statuses = Ticket.workflow_next_statuses_for(ticket.ticket_type, ticket.status)
      puts "Next statuses: #{next_statuses.empty? ? 'none' : next_statuses.join(', ')}"
      permissions = next_statuses.map do |next_status|
        roles = Ticket.workflow_transition_roles_for(ticket.ticket_type, ticket.status, next_status)
        "#{next_status}=#{roles.join(', ')}"
      end
      puts "Transition roles: #{permissions.empty? ? 'none' : permissions.join(' | ')}"
    end

    def format_workflow_transitions(transitions)
      return "none" if transitions.empty?

      transitions.sort_by { |from_status, _| from_status.to_s }.map do |from_status, next_statuses|
        "#{from_status} -> #{Array(next_statuses).join(', ')}"
      end.join(" | ")
    end

    def format_workflow_permissions(permissions)
      return "none" if permissions.empty?

      permissions.sort_by { |from_status, _| from_status.to_s }.map do |from_status, transitions|
        inner = transitions.sort_by { |to_status, _| to_status.to_s }.map do |to_status, roles|
          "#{to_status}: #{Array(roles).join(', ')}"
        end.join(" | ")
        "#{from_status} => #{inner}"
      end.join(" | ")
    end

    def show_sort_rules
      rule = @sort_rules.current
      puts "Custom sort order: #{rule.join(' > ')}"
      puts "Allowed fields: #{SortRuleStore::ALLOWED_FIELDS.join(', ')}"
    end

    def export(args)
      format = args[0]
      case format
      when "csv"
        path = args[1] || prompt("CSV path", "data/tickets.csv")
        export_csv(path)
      when "json"
        path = args[1] || prompt("JSON path", "data/tickets-export.json")
        export_json(path)
      else
        puts "Usage: export csv [PATH] | export json [PATH]"
      end
    end

    def export_csv(path)
      tickets = @store.all
      FileUtils.mkdir_p(File.dirname(path))
      CSV.open(path, "w") do |csv|
        csv << %w[
          id title description status priority due_at overdue reminder_at reminder_repeat
          tags comment_count created_at updated_at closed_at
        ]
        tickets.each do |ticket|
          csv << [
            ticket.id,
            ticket.title,
            ticket.description,
            ticket.status,
            ticket.priority,
            ticket.due_at,
            ticket.overdue?,
            ticket.reminder_at,
            ticket.reminder_repeat,
            ticket.tags.join(";"),
            ticket.comments.count,
            ticket.created_at,
            ticket.updated_at,
            ticket.closed_at
          ]
        end
      end
      puts "Exported #{tickets.count} tickets to #{path}."
    end

    def export_json(path)
      tickets = @store.all
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(tickets.map(&:to_h)))
      puts "Exported #{tickets.count} tickets to #{path}."
    end

    def import(args)
      return unless require_permission!(:admin)

      format = args[0]
      case format
      when "json"
        path = args[1] || prompt("JSON path", "data/tickets-export.json")
        summary = @store.import_json(path)
        report_duplicate_groups
        log_action("tickets.import", "tickets", source: path, imported: summary[:imported], merged: summary[:merged], remapped: summary[:remapped])
        puts "Imported #{summary[:imported]} tickets from #{path}."
        puts "Resolved #{summary[:merged]} duplicate merges and #{summary[:remapped]} ID conflicts."
      else
        puts "Usage: import json [PATH]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def list_users
      users = @users.all
      if users.empty?
        puts "No users found."
        return
      end

      users.each do |user|
        marker = @current_user && user.id.to_i == @current_user.id.to_i ? " *" : ""
        puts "##{user.id} #{user.display_name} [#{user.role_label}]#{marker}"
      end
    end

    def manage_users(args)
      action = args[0]
      case action
      when "add"
        return unless require_permission!(:admin)

        name = prompt("Name")
        email = prompt("Email", "")
        role = prompt("Role (admin, agent, viewer)", "agent")
        user = @users.create(name: name, email: email, role: role)
        @current_user ||= user
        persist_current_user_session!
        log_action("user.create", "user ##{user.id}", name: user.name, role: user.role_label)
        puts "Created user ##{user.id}."
      when "switch"
        user = @users.find(required_id(args.drop(1)))
        return puts "User not found." unless user

        log_action("user.switch", "user ##{user.id}", name: user.name, role: user.role_label)
        @current_user = user
        persist_current_user_session!
        puts "Switched to #{user.display_name}."
      when "role"
        return unless require_permission!(:admin)

        user = @users.find(required_id(args.drop(1)))
        return puts "User not found." unless user

        role = args[2]
        role = prompt("Role (admin, agent, viewer)", user.role_label) if role.to_s.strip.empty?
        user = @users.update(user.id, role: role)
        log_action("user.role", "user ##{user.id}", name: user.name, role: user.role_label)
        puts "Updated role for #{user.display_name} to #{user.role_label}."
      else
        puts "Usage: user add | user switch ID | user role ID ROLE"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def whoami
      if @current_user
        puts "Current user: ##{@current_user.id} #{@current_user.display_name} (role: #{@current_user.role_label})"
        puts "Notification prefs: #{@current_user.notification_preferences_label}"
        puts "Suppression rules: #{@current_user.notification_suppression_rules_label}"
        puts "Saved searches: #{@current_user.saved_searches_label}"
        puts "Favorite filters: #{@current_user.favorite_filters_label}"
      else
        puts "No current user."
      end
    end

    def manage_notifications(args)
      action = args[0]
      case action
      when "show"
        show_notification_preferences
      when "set"
        key = args[1]
        value = args[2]
        return puts "Usage: notify set KEY VALUE" if key.to_s.strip.empty? || value.to_s.strip.empty?

        update_notification_preferences(key, value)
      when "suppress"
        manage_notification_suppression(args.drop(1))
      when "email"
        return unless require_permission!(:ticket_write)

        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        body = args.drop(2).join(" ")
        body = "Ticket ##{ticket.id}: #{ticket.title}" if body.strip.empty?
        send_email_notifications(ticket, subject: "Ticket ##{ticket.id}", body: body, event: "manual")
      else
        puts "Usage: notify show | notify set KEY VALUE | notify suppress show|add|remove ... | notify email ID [BODY]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def audit(args)
      options = parse_audit_options(args)
      entries = @audit_log.all
      entries = entries.select { |entry| entry["action"] == options[:action] } if options[:action]
      entries = entries.select { |entry| entry["actor"].to_s.include?(options[:actor]) } if options[:actor]
      entries = entries.select { |entry| entry["subject"].to_s.include?(options[:subject]) } if options[:subject]
      entries = entries.last(options[:last]) if options[:last]
      if entries.empty?
        puts "No audit events."
        return
      end

      entries.each do |entry|
        puts "##{entry["id"]} #{entry["created_at"]} #{entry["actor"]} #{entry["action"]} #{entry["subject"]}"
      end
    end

    def api(args)
      if args[0].to_s == "tokens"
        manage_api_tokens(args.drop(1))
        return
      end

      token_index = args.index("--token")
      raw_token = token_index ? args[token_index + 1].to_s.strip : ""
      if raw_token.empty?
        puts api_json_response(401, error: "Missing API token.")
        return
      end

      method_args = args.dup
      method_args.slice!(token_index, 2) if token_index

      method = method_args[0].to_s.strip.upcase
      path = method_args[1].to_s.strip
      body = method_args.drop(2).join(" ")
      if method.empty? || path.empty?
        puts "Usage: api --token TOKEN METHOD PATH [JSON_BODY]"
        return
      end

      auth_token = @api_tokens.find_by_token(raw_token)
      if auth_token.nil? || auth_token["enabled"] == false
        puts api_json_response(401, error: "Invalid API token.")
        return
      end

      rate = @api_tokens.consume!(raw_token, limit: @api_rate_limit, window_seconds: @api_rate_window_seconds)
      if rate.nil?
        puts api_json_response(401, error: "Invalid API token.")
        return
      end
      unless rate[:allowed]
        puts api_json_response(429, {}, "API rate limit exceeded.", rate_limit_remaining: rate[:remaining], rate_limit_reset_at: rate[:reset_at])
        return
      end

      previous_user = @current_user
      @current_user = @users.find(auth_token["user_id"]) || previous_user

      payload = parse_api_body(body)
      response =
        if method == "GET" && path == "/tickets"
          cached_api_response([@current_user&.id, method, path, body]) do
            { status: 200, data: @store.all.map { |ticket| api_ticket(ticket) } }
          end
        elsif method == "GET" && path.match?(%r{\A/tickets/\d+\z})
          cached_api_response([@current_user&.id, method, path, body]) do
            ticket = @store.find(path.split("/").last)
            return { status: 404, error: "Ticket not found." } unless ticket

            { status: 200, data: api_ticket(ticket) }
          end
        elsif method == "POST" && path == "/tickets"
          return unless require_permission!(:ticket_write)

          ticket = @store.create(payload.transform_keys(&:to_sym))
          invalidate_api_cache!
          log_action("ticket.create", "ticket ##{ticket.id}", title: ticket.title, status: ticket.status, priority: ticket.priority)
          { status: 201, data: api_ticket(ticket) }
        elsif method == "PATCH" && path.match?(%r{\A/tickets/\d+\z})
          return unless require_permission!(:ticket_write)

          id = path.split("/").last
          ticket = @store.update(id, payload.transform_keys(&:to_sym), actor_role: @current_user&.role_label)
          return puts(api_json_response(404, error: "Ticket not found.")) unless ticket

          invalidate_api_cache!
          log_action("ticket.update", "ticket ##{id}", changes: payload)
          { status: 200, data: api_ticket(ticket) }
        elsif method == "DELETE" && path.match?(%r{\A/tickets/\d+\z})
          return unless require_permission!(:ticket_write)

          id = path.split("/").last
          if @store.delete(id)
            invalidate_api_cache!
            log_action("ticket.delete", "ticket ##{id}")
            { status: 200, data: { deleted: true, id: id.to_i } }
          else
            { status: 404, error: "Ticket not found." }
          end
        elsif method == "POST" && path.match?(%r{\A/tickets/\d+/restore\z})
          return unless require_permission!(:ticket_write)

          id = path.split("/")[2]
          if @store.restore(id)
            invalidate_api_cache!
            log_action("ticket.restore", "ticket ##{id}")
            { status: 200, data: { restored: true, id: id.to_i } }
          else
            { status: 404, error: "Ticket not found." }
          end
        elsif method == "GET" && path == "/users"
          cached_api_response([@current_user&.id, method, path, body]) do
            { status: 200, data: @users.all.map { |user| api_user(user) } }
          end
        elsif method == "GET" && path == "/webhooks"
          cached_api_response([@current_user&.id, method, path, body]) do
            { status: 200, data: @webhooks.all }
          end
        elsif method == "POST" && path == "/webhooks"
          return unless require_permission!(:admin)

          webhook = @webhooks.create(
            name: payload["name"] || payload[:name],
            url: payload["url"] || payload[:url],
            events: payload["events"] || payload[:events] || []
          )
          invalidate_api_cache!
          { status: 201, data: webhook }
        elsif method == "DELETE" && path.match?(%r{\A/webhooks/\d+\z})
          return unless require_permission!(:admin)

          id = path.split("/").last
          if @webhooks.delete(id)
            invalidate_api_cache!
            { status: 200, data: { deleted: true, id: id.to_i } }
          else
            { status: 404, error: "Webhook not found." }
          end
        else
                   { status: 404, error: "Unknown API route." }
        end

      puts api_json_response(response[:status], response[:data] || {}, response[:error])
    rescue ArgumentError, JSON::ParserError => e
      puts api_json_response(400, error: e.message)
    ensure
      @current_user = previous_user if defined?(previous_user)
    end

    def manage_api_tokens(args)
      action = args[0]
      case action
      when "list"
        return unless require_permission!(:admin)

        tokens = @api_tokens.all
        if tokens.empty?
          puts "No API tokens."
          return
        end

        tokens.each do |token|
          user = @users.find(token["user_id"])
          puts "##{token["id"]} #{token["name"]} user=#{user ? user.display_name : "user ##{token["user_id"]}"} enabled=#{token["enabled"]} last_used=#{token["last_used_at"] || 'never'} requests=#{token["request_count"].to_i} window_started=#{token["window_started_at"] || 'never'}"
        end
      when "create"
        return unless require_permission!(:admin)

        name = args[1]
        user_id = args[2] || @current_user.id
        if name.to_s.strip.empty?
          puts "Usage: api tokens create NAME [USER_ID]"
          return
        end

        token = @api_tokens.create(name: name, user_id: user_id, scopes: ["*"])
        invalidate_api_cache!
        user = @users.find(token["user_id"])
        puts "Created API token ##{token["id"]} for #{user ? user.display_name : "user ##{token["user_id"]}"}."
        puts "Token: #{token["token"]}"
      when "revoke"
        return unless require_permission!(:admin)

        id = required_id(args.drop(1))
        token = @api_tokens.revoke(id)
        if token
          invalidate_api_cache!
          puts "Revoked API token ##{id}."
        else
          puts "API token not found."
        end
      else
        puts "Usage: api tokens list | api tokens create NAME [USER_ID] | api tokens revoke ID"
      end
    rescue ArgumentError => e
      puts e.message
    end

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

    def list_aliases
      aliases = command_aliases
      aliases.each do |name, target|
        puts "#{name} -> #{target}"
      end
    end

    def manage_session(args)
      action = args[0]
      case action
      when nil, "show"
        if @current_user
          puts "Current session user: ##{@current_user.id} #{@current_user.display_name} (role: #{@current_user.role_label})"
          puts "Session file: #{@session.path}"
        else
          puts "No current session user."
        end
      when "clear"
        @session.clear!
        @current_user = @users.all.first
        persist_current_user_session!
        puts "Cleared session user."
      else
        puts "Usage: session show | session clear"
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

    def load_session_user!
      return if @session.nil? || @users.nil?

      user = @users.find(@session.current_user_id)
      user ||= @users.all.first
      @current_user = user
      persist_current_user_session!
    end

    def persist_current_user_session!
      return if @session.nil?

      @session.current_user_id = @current_user&.id
    end

    def api_json_response(status, data = {}, error = nil, meta = {})
      payload = { status: status }
      payload["error"] = error if error
      payload["data"] = data unless error
      meta.each do |key, value|
        payload[key.to_s] = value
      end
      JSON.pretty_generate(payload)
    end

    def cached_api_response(key)
      normalized_key = Array(key).map(&:to_s).join("|")
      entry = @api_response_cache[normalized_key]
      if entry && (Time.now.utc - entry[:cached_at]) < API_CACHE_TTL_SECONDS
        return entry[:value]
      end

      value = yield
      @api_response_cache[normalized_key] = { value: value, cached_at: Time.now.utc }
      value
    end

    def invalidate_api_cache!
      @api_response_cache.clear
    end

    def parse_api_body(body)
      body = body.to_s.strip
      return {} if body.empty?

      if body.start_with?("{", "[")
        parsed = JSON.parse(body)
        return parsed if parsed.is_a?(Hash)

        raise ArgumentError, "API body must be a JSON object"
      end

      pairs = Shellwords.split(body)
      pairs.each_with_object({}) do |pair, hash|
        key, value = pair.split("=", 2)
        raise ArgumentError, "invalid body pair: #{pair}" if key.to_s.strip.empty?

        hash[key] = value.nil? ? true : value
      end
    end

    def api_ticket(ticket)
      {
        id: ticket.id,
        title: ticket.title,
        description: ticket.description,
        status: ticket.status,
        priority: ticket.priority,
        tags: ticket.tags,
        ticket_type: ticket.ticket_type,
        due_at: ticket.due_at,
        reminder_at: ticket.reminder_at,
        reminder_repeat: ticket.reminder_repeat,
        created_at: ticket.created_at,
        updated_at: ticket.updated_at
      }
    end

    def api_user(user)
      {
        id: user.id,
        name: user.name,
        email: user.email,
        role: user.role_label
      }
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
        deliver_webhook(webhook, webhook_payload(event, "webhook ##{webhook["id"]}", details))
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
        payload = hook_payload(event, "hook ##{hook["id"]}", { "test" => true }, actor: current_user_name)
        deliver_hook(hook, payload)
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

    def activity(args)
      options = parse_activity_options(args)
      entries = @audit_log.all.select { |entry| activity_visible?(entry) }
      entries = entries.select { |entry| activity_entry_for_ticket?(entry, options[:ticket]) } if options[:ticket]
      entries = entries.last(options[:last]) if options[:last]
      if entries.empty?
        puts "No activity."
        return
      end

      entries.each do |entry|
        puts format_activity_entry(entry)
      end
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
        puts
        puts "Interactive Menu"
        puts "d) Dashboard"
        puts "l) List tickets"
        puts "s) Show ticket"
        puts "n) New ticket"
        puts "f) Search tickets"
        puts "w) Who am I"
        puts "h) Help"
        puts "q) Exit menu"
        puts "Shortcuts: d l s n f w h q"

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
          puts "Shortcuts: d dashboard, l list, s show, n new, f search, w whoami, q quit"
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

    def format_ticket_row(ticket)
      overdue_marker = ticket.overdue? ? " overdue" : ""
      sla_marker = case ticket.sla_status
                   when "warning" then " sla_warning"
                   when "breached" then " sla_breached"
                   else ""
                   end
      escalation_marker = ticket.escalation_needed? ? " escalate" : ""
      pinned_marker = ticket.pinned? ? " pinned" : ""
      archived_marker = ticket.archived? ? " archived" : ""
      deleted_marker = ticket.deleted? ? " deleted" : ""
      merged_marker = ticket.merged? ? " merged" : ""
      merged_from_marker = ticket.merged_from_ids.empty? ? "" : " merged_from:#{ticket.merged_from_ids.join(',')}"
      "##{ticket.id} [#{ticket.ticket_type}/#{ticket.status}/#{ticket.priority}#{overdue_marker}#{sla_marker}#{escalation_marker}#{pinned_marker}#{archived_marker}#{deleted_marker}#{merged_marker}#{merged_from_marker}] #{ticket.title}#{ticket.tags.empty? ? '' : " ##{ticket.tags.join(' #')}"}"
    end

    def format_sla_status(ticket)
      case ticket.sla_status
      when "breached"
        rule = ticket.sla_rule
        age = ticket.sla_age_days
        "breached (age #{age} days, threshold #{rule[:breach_days]} days)"
      when "warning"
        rule = ticket.sla_rule
        age = ticket.sla_age_days
        "warning (age #{age} days, threshold #{rule[:warning_days]} days)"
      when "ok"
        rule = ticket.sla_rule
        age = ticket.sla_age_days
        "ok (age #{age} days, threshold #{rule[:warning_days]} days)"
      else
        "none"
      end
    end

    def format_escalation_status(ticket)
      rule = ticket.escalation_rule
      return "none" unless rule
      return "disabled" unless rule[:enabled]
      return "needed (trigger #{rule[:trigger]}, target #{rule[:target_role]})" if ticket.escalation_needed?

      "none"
    end

    def format_filter_options(options)
      options = options || {}
      parts = []
      parts << "--status #{option_value(options, :status)}" if option_value(options, :status)
      parts << "--priority #{option_value(options, :priority)}" if option_value(options, :priority)
      parts << "--tag #{option_value(options, :tag)}" if option_value(options, :tag)
      parts << "--sort #{option_value(options, :sort)}" if option_value(options, :sort)
      parts << "--overdue" if truthy_option?(options, :overdue)
      parts << "--archived" if truthy_option?(options, :archived)
      parts << "--active" if truthy_option?(options, :active)
      parts << "--deleted" if truthy_option?(options, :deleted)
      parts.empty? ? "none" : parts.join(" ")
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

    def overdue
      tickets = @store.all.select(&:overdue?)
      if tickets.empty?
        puts "No overdue tickets."
        return
      end

      tickets.each { |ticket| puts format_ticket_row(ticket) }
    end

    def manage_sla(args)
      action = args[0]
      case action
      when nil
        sla_warnings
      when "rules"
        manage_sla_rules(args.drop(1))
      else
        puts "Usage: sla | sla rules show | sla rules set PRIORITY WARNING_DAYS BREACH_DAYS | sla rules reset [PRIORITY|all]"
      end
    end

    def manage_sla_rules(args)
      action = args[0]
      case action
      when nil, "show"
        show_sla_rules
      when "set"
        return unless require_permission!(:admin)

        priority = args[1]
        warning_days = args[2]
        breach_days = args[3]
        return puts "Usage: sla rules set PRIORITY WARNING_DAYS BREACH_DAYS" if [priority, warning_days, breach_days].any? { |value| value.to_s.strip.empty? }

        rules = @sla_rules.set(priority, warning_days: warning_days, breach_days: breach_days)
        @sla_rules.reload_ticket_rules!
        log_action("sla.rules_set", "sla", priority: priority.to_s.strip.downcase, rules: rules[priority.to_s.strip.downcase])
        puts "Updated SLA rule for #{priority}."
      when "reset"
        return unless require_permission!(:admin)

        priority = args[1]
        rules = @sla_rules.reset(priority)
        @sla_rules.reload_ticket_rules!
        log_action("sla.rules_reset", "sla", priority: priority.to_s.strip.empty? ? "all" : priority.to_s.strip.downcase, rules: rules)
        normalized_priority = priority.to_s.strip.downcase
        puts normalized_priority.empty? || normalized_priority == "all" ? "Reset all SLA rules." : "Reset SLA rule for #{priority}."
      else
        puts "Usage: sla rules show | sla rules set PRIORITY WARNING_DAYS BREACH_DAYS | sla rules reset [PRIORITY|all]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_escalation(args)
      action = args[0]
      case action
      when nil
        escalations
      when "history"
        show_escalation_history(args.drop(1))
      when "rules"
        manage_escalation_rules(args.drop(1))
      else
        puts "Usage: escalation | escalation history [--last N] [--ticket ID] | escalation rules show | escalation rules set PRIORITY ENABLED TRIGGER TARGET_ROLE | escalation rules reset [PRIORITY|all]"
      end
    end

    def manage_escalation_rules(args)
      action = args[0]
      case action
      when nil, "show"
        show_escalation_rules
      when "set"
        return unless require_permission!(:admin)

        priority = args[1]
        enabled = args[2]
        trigger = args[3]
        target_role = args[4]
        return puts "Usage: escalation rules set PRIORITY ENABLED TRIGGER TARGET_ROLE" if [priority, enabled, trigger, target_role].any? { |value| value.to_s.strip.empty? }

        rules = @escalation_rules.set(priority, enabled: enabled, trigger: trigger, target_role: target_role)
        @escalation_rules.reload_ticket_rules!
        log_action("escalation.rules_set", "escalation", priority: priority.to_s.strip.downcase, rules: rules[priority.to_s.strip.downcase])
        puts "Updated escalation rule for #{priority}."
      when "reset"
        return unless require_permission!(:admin)

        priority = args[1]
        rules = @escalation_rules.reset(priority)
        @escalation_rules.reload_ticket_rules!
        log_action("escalation.rules_reset", "escalation", priority: priority.to_s.strip.empty? ? "all" : priority.to_s.strip.downcase, rules: rules)
        normalized_priority = priority.to_s.strip.downcase
        puts normalized_priority.empty? || normalized_priority == "all" ? "Reset all escalation rules." : "Reset escalation rule for #{priority}."
      else
        puts "Usage: escalation rules show | escalation rules set PRIORITY ENABLED TRIGGER TARGET_ROLE | escalation rules reset [PRIORITY|all]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def show_escalation_rules
      rules = @escalation_rules.all
      rules.each do |priority, rule|
        puts "#{priority}: enabled #{rule["enabled"]}, trigger #{rule["trigger"]}, target #{rule["target_role"]}"
      end
    end

    def escalations
      tickets = @store.all.select(&:escalation_needed?)
      if tickets.empty?
        puts "No escalation candidates."
        return
      end

      tickets.each do |ticket|
        puts format_ticket_row(ticket)
        puts "  Escalation: #{format_escalation_status(ticket)}"
      end
    end

    def escalate_ticket(args)
      return unless require_permission!(:ticket_write)

      ticket = @store.find(required_id(args))
      return puts "Ticket not found." unless ticket

      note = args.drop(1).join(" ").strip
      note = "manual escalation" if note.empty?
      status = ticket.escalation_needed? ? ticket.escalation_status : "manual"
      trigger = ticket.escalation_trigger || "manual"
      target_role = ticket.escalation_target_role || "admin"
      log_action(
        "escalation.record",
        "ticket ##{ticket.id}",
        status: status,
        trigger: trigger,
        target_role: target_role,
        note: note
      )
      puts "Recorded escalation history for ticket ##{ticket.id}."
    end

    def show_escalation_history(args_or_ticket)
      options =
        if args_or_ticket.is_a?(Ticket)
          { ticket: args_or_ticket.id, last: 5 }
        else
          parse_activity_options(Array(args_or_ticket))
        end

      entries = escalation_history_entries(options[:ticket])
      entries = entries.last(options[:last]) if options[:last]
      puts "Escalation history:"
      if entries.empty?
        puts "  none"
        return
      end

      entries.each { |entry| puts "  #{format_escalation_history_entry(entry)}" }
    end

    def show_duplicate_candidates(ticket)
      candidates = @store.duplicate_candidates_for(ticket)
      puts "Possible duplicates:"
      if candidates.empty?
        puts "  none"
      else
        candidates.each do |candidate|
          puts "  #{format_ticket_row(candidate)}"
        end
      end
    end

    def show_related_tickets(ticket)
      related = @store.related_tickets(ticket)
      puts "Related tickets:"
      if related.empty?
        puts "  none"
      else
        related.each do |related_ticket|
          puts "  #{format_ticket_row(related_ticket)}"
        end
      end
    end

    def show_hierarchy(ticket)
      parent = @store.parent_ticket(ticket)
      children = @store.child_tickets(ticket)

      puts "Parent ticket:"
      if parent
        puts "  #{format_ticket_row(parent)}"
      else
        puts "  none"
      end

      puts "Child tickets:"
      if children.empty?
        puts "  none"
      else
        children.each do |child|
          puts "  #{format_ticket_row(child)}"
        end
      end
    end

    def show_dependencies(ticket)
      dependencies = @store.dependencies_for(ticket)
      dependents = @store.dependent_tickets(ticket)

      puts "Depends on:"
      if dependencies.empty?
        puts "  none"
      else
        dependencies.each do |dependency|
          puts "  #{format_ticket_row(dependency)}"
        end
      end

      puts "Blocked by:"
      if dependents.empty?
        puts "  none"
      else
        dependents.each do |dependent|
          puts "  #{format_ticket_row(dependent)}"
        end
      end
    end

    def show_sla_rules
      rules = @sla_rules.all
      rules.each do |priority, rule|
        puts "#{priority}: warning #{rule["warning_days"]} days, breach #{rule["breach_days"]} days"
      end
    end

    def escalation_history_entries(ticket_id = nil)
      entries = @audit_log.all.select { |entry| entry["action"] == "escalation.record" }
      entries = entries.select { |entry| activity_entry_for_ticket?(entry, ticket_id) } if ticket_id
      entries
    end

    def format_escalation_history_entry(entry)
      subject = entry["subject"].to_s
      actor = entry["actor"].to_s
      created_at = entry["created_at"].to_s
      details = entry["details"] || {}
      status = details["status"].to_s
      trigger = details["trigger"].to_s
      target_role = details["target_role"].to_s
      note = details["note"].to_s

      parts = []
      parts << status unless status.empty?
      parts << "trigger #{trigger}" unless trigger.empty?
      parts << "target #{target_role}" unless target_role.empty?
      parts << "note: #{note}" unless note.empty?
      suffix = parts.empty? ? "" : " (#{parts.join(", ")})"

      "#{created_at} #{actor} escalated #{subject}#{suffix}"
    end

    def sla_warnings
      tickets = @store.all.select { |ticket| %w[warning breached].include?(ticket.sla_status) }
      if tickets.empty?
        puts "No SLA warnings."
        return
      end

      tickets.each do |ticket|
        puts format_ticket_row(ticket)
        puts "  SLA: #{format_sla_status(ticket)}"
      end
    end

    def analytics_summary
      tickets = @store.all
      open_tickets = open_ticket_scope(tickets)
      closed_tickets = tickets.select(&:closed?)

      puts "Analytics"
      puts "Total tickets: #{tickets.count}"
      puts "Open tickets: #{open_tickets.count}"
      puts "Closed tickets: #{closed_tickets.count}"
      puts "Overdue tickets: #{tickets.count(&:overdue?)}"
      puts "Escalation candidates: #{tickets.count(&:escalation_needed?)}"
      puts "SLA breaches: #{tickets.count { |ticket| ticket.sla_status == 'breached' }}"
      puts "Average open age (days): #{format_average_days(open_tickets, :created_at)}"
      puts "Average time to close (days): #{format_average_days(closed_tickets, :closed_at)}"
      puts "Total comments: #{tickets.sum { |ticket| ticket.comments.count }}"
    end

    def analytics_status
      tickets = @store.all
      counts = tickets.group_by(&:status).transform_values(&:count)
      total = tickets.count

      puts "Status analytics"
      Ticket::STATUSES.each do |status|
        count = counts.fetch(status, 0)
        percentage = total.zero? ? 0 : ((count.to_f / total) * 100).round(1)
        puts "#{status}: #{count} (#{percentage}%)"
      end
      puts "Archived: #{tickets.count(&:archived?)}"
      puts "Pinned: #{tickets.count(&:pinned?)}"
    end

    def analytics_aging
      tickets = open_ticket_scope(@store.all)
      if tickets.empty?
        puts "No open tickets."
        return
      end

      buckets = {
        "0-2 days" => 0,
        "3-7 days" => 0,
        "8-14 days" => 0,
        "15+ days" => 0
      }
      tickets.each do |ticket|
        age = ticket_age_days(ticket)
        next if age.nil?

        case age
        when 0..2 then buckets["0-2 days"] += 1
        when 3..7 then buckets["3-7 days"] += 1
        when 8..14 then buckets["8-14 days"] += 1
        else buckets["15+ days"] += 1
        end
      end

      oldest_ticket = tickets.max_by { |ticket| ticket_age_days(ticket) || -1 }
      puts "Aging analytics"
      puts "Average open age (days): #{format_average_days(tickets, :created_at)}"
      puts "Oldest open ticket: ##{oldest_ticket.id} #{oldest_ticket.title}"
      puts "Aging buckets:"
      buckets.each do |label, count|
        puts "  #{label}: #{count}"
      end
    end

    def analytics_trend
      tickets = @store.all
      today = Date.today
      days = 7

      puts "Trend analytics"
      days.downto(1) do |offset|
        date = today - offset
        created = tickets.count { |ticket| parse_date(ticket.created_at) == date }
        closed = tickets.count { |ticket| parse_date(ticket.closed_at) == date }
        puts "#{date}: created #{created}, closed #{closed}"
      end
    end

    def report_daily(date_string = nil)
      date = parse_report_date(date_string) || Date.today - 1
      tickets = @store.all
      puts "Daily summary report for #{date}"
      print_summary_metrics(tickets, date, date)
      print_priority_breakdown(tickets)
      print_top_tags(tickets)
    end

    def report_duplicate_candidates(ticket)
      candidates = @store.duplicate_candidates_for(ticket)
      return if candidates.empty?

      puts "Warning: possible duplicates found for ticket ##{ticket.id}:"
      candidates.each do |candidate|
        puts "  #{format_ticket_row(candidate)}"
      end
    end

    def report_duplicate_groups
      groups = @store.duplicate_groups
      return if groups.empty?

      puts "Duplicate ticket groups detected:"
      groups.each_with_index do |group, index|
        puts "  Group #{index + 1}:"
        group.each do |ticket|
          puts "    #{format_ticket_row(ticket)}"
        end
      end
    end

    def report_weekly(date_string = nil)
      reference_date = parse_report_date(date_string) || Date.today - 7
      week_start = reference_date - (reference_date.wday - 1) % 7
      week_end = week_start + 6
      tickets = @store.all

      puts "Weekly summary report for #{week_start} to #{week_end}"
      print_summary_metrics(tickets, week_start, week_end)
      print_priority_breakdown(tickets)
      print_top_tags(tickets)
      puts "Daily breakdown:"
      (week_start..week_end).each do |date|
        day_stats = summary_metrics_for(tickets, date, date)
        puts "  #{date}: created #{day_stats[:created]}, closed #{day_stats[:closed]}, updated #{day_stats[:updated]}"
      end
    end

    def print_summary_metrics(tickets, start_date, end_date)
      stats = summary_metrics_for(tickets, start_date, end_date)
      open_tickets = open_ticket_scope(tickets)

      puts "Created: #{stats[:created]}"
      puts "Closed: #{stats[:closed]}"
      puts "Updated: #{stats[:updated]}"
      puts "Open now: #{open_tickets.count}"
      puts "Overdue now: #{tickets.count(&:overdue?)}"
      puts "Due in range: #{stats[:due]}"
      puts "Reminders due in range: #{stats[:reminders]}"
      puts "Escalation candidates in range: #{stats[:escalations]}"
      puts "SLA breaches in range: #{stats[:breaches]}"
    end

    def print_priority_breakdown(tickets)
      puts "Top priorities:"
      Ticket::PRIORITIES.each do |priority|
        puts "  #{priority}: #{tickets.count { |ticket| ticket.priority == priority }}"
      end
    end

    def print_top_tags(tickets)
      puts "Top tags:"
      tag_counts = tickets.flat_map(&:tags).tally.sort_by { |tag, count| [-count, tag] }.first(5)
      if tag_counts.empty?
        puts "  none"
      else
        tag_counts.each do |tag, count|
          puts "  #{tag}: #{count}"
        end
      end
    end

    def summary_metrics_for(tickets, start_date, end_date)
      range = start_date..end_date
      {
        created: tickets.count { |ticket| date_in_range?(parse_date(ticket.created_at), range) },
        closed: tickets.count { |ticket| date_in_range?(parse_date(ticket.closed_at), range) },
        updated: tickets.count { |ticket| date_in_range?(parse_date(ticket.updated_at), range) },
        due: tickets.count { |ticket| date_in_range?(parse_date(ticket.due_at), range) },
        reminders: tickets.count { |ticket| date_in_range?(parse_time(ticket.reminder_at)&.to_date, range) },
        escalations: tickets.count { |ticket| ticket.escalation_needed? && date_in_range?(parse_date(ticket.created_at), range) },
        breaches: tickets.count { |ticket| ticket.sla_status == "breached" && date_in_range?(parse_date(ticket.created_at), range) }
      }
    end

    def open_ticket_scope(tickets)
      tickets.select { |ticket| %w[open in_progress waiting].include?(ticket.status) }
    end

    def format_average_days(tickets, field)
      values =
        case field
        when :created_at
          tickets.map { |ticket| ticket_age_days(ticket) }.compact
        when :closed_at
          tickets.map { |ticket| ticket_close_duration_days(ticket) }.compact
        else
          []
        end

      return "n/a" if values.empty?

      (values.sum.to_f / values.count).round(1)
    end

    def ticket_age_days(ticket, reference_date = Date.today)
      date = parse_date(ticket.created_at)
      return nil unless date

      (reference_date - date).to_i
    end

    def ticket_close_duration_days(ticket)
      created = parse_date(ticket.created_at)
      closed = parse_date(ticket.closed_at)
      return nil unless created && closed

      (closed - created).to_i
    end

    def parse_date(value)
      return nil if value.to_s.strip.empty?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def date_in_range?(date, range)
      date && range.cover?(date)
    end

    def parse_time(value)
      return nil if value.to_s.strip.empty?

      Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end

    def parse_report_date(value)
      return nil if value.to_s.strip.empty?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_duplicate_options(args)
      options = {}
      idx = 0
      while idx < args.length
        case args[idx]
        when "--ticket"
          options[:ticket] = args[idx + 1].to_i
          idx += 2
        else
          idx += 1
        end
      end
      options
    end

    def reminders
      return unless require_permission!(:ticket_write)

      tickets = @store.all.select(&:reminder_due?)
      if tickets.empty?
        puts "No due reminders."
        return
      end

      tickets.each do |ticket|
        puts "##{ticket.id} #{ticket.title} [reminder #{ticket.reminder_at}]"
        next unless ticket.recurring_reminder?

        ticket.advance_reminder!
        @store.save_ticket(ticket)
        log_action("reminder.advance", "ticket ##{ticket.id}", reminder_at: ticket.reminder_at)
      end
    end

    def remind(args)
      return unless require_permission!(:ticket_write)

      action = args[0]
      id = args[1]
      ticket = @store.find(id)
      return puts "Ticket not found." unless ticket

      case action
      when "set"
        timestamp = args.drop(2).join(" ")
        timestamp = prompt("Reminder time (YYYY-MM-DD HH:MM)") if timestamp.strip.empty?
        ticket.update(reminder_at: timestamp)
        @store.save_ticket(ticket)
        log_action("reminder.set", "ticket ##{id}", reminder_at: ticket.reminder_at)
        puts "Reminder set for ticket ##{id}."
      when "clear"
        ticket.update(reminder_at: nil)
        @store.save_ticket(ticket)
        log_action("reminder.clear", "ticket ##{id}")
        puts "Reminder cleared for ticket ##{id}."
      when "repeat"
        repeat = args[2]
        if repeat == "clear"
          ticket.update(reminder_repeat: nil)
          @store.save_ticket(ticket)
          log_action("reminder.repeat_clear", "ticket ##{id}")
          puts "Reminder repeat cleared for ticket ##{id}."
        else
          repeat = args.drop(2).join(" ")
          repeat = prompt("Reminder repeat (daily, weekly, monthly)") if repeat.strip.empty?
          ticket.update(reminder_repeat: repeat)
          @store.save_ticket(ticket)
          log_action("reminder.repeat_set", "ticket ##{id}", reminder_repeat: ticket.reminder_repeat)
          puts "Reminder repeat set for ticket ##{id}."
        end
      else
        puts "Usage: remind set ID TIMESTAMP | remind clear ID | remind repeat ID INTERVAL | remind repeat clear ID"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def required_id(args)
      id = args[0]
      raise ArgumentError, "Usage requires an ID" if id.nil? || id.strip.empty?

      id.to_i
    end

    def current_user_name
      @current_user ? @current_user.name : "agent"
    end

    def seed_default_user
      return unless @users.all.empty?

      @users.create(name: "agent", email: "", role: "agent")
    end

    def show_notification_preferences
      prefs = @current_user.notification_preferences || {}
      if prefs.empty?
        puts "No notification preferences."
        return
      end

      prefs.each do |key, value|
        puts "#{key}: #{value}"
      end
    end

    def manage_notification_suppression(args)
      action = args[0]
      case action
      when "show"
        show_notification_suppression_rules
      when "add"
        rule = args[1]
        return puts "Usage: notify suppress add RULE" if rule.to_s.strip.empty?

        update_notification_suppression_rules(:add, rule)
      when "remove"
        rule = args[1]
        return puts "Usage: notify suppress remove RULE" if rule.to_s.strip.empty?

        update_notification_suppression_rules(:remove, rule)
      else
        puts "Usage: notify suppress show | notify suppress add RULE | notify suppress remove RULE"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def show_notification_suppression_rules
      rules = @current_user.notification_suppression_rules || []
      if rules.empty?
        puts "No suppression rules."
        return
      end

      rules.each { |rule| puts rule }
    end

    def update_notification_suppression_rules(action, rule)
      rules = (@current_user.notification_suppression_rules || []).dup
      rule = rule.to_s.strip.downcase
      return puts "Rule cannot be empty." if rule.empty?

      case action
      when :add
        rules << rule unless rules.include?(rule)
      when :remove
        rules.delete(rule)
      end

      updated_user = @users.update(@current_user.id, notification_suppression_rules: rules)
      if updated_user
        @current_user = updated_user
      else
        @current_user.notification_suppression_rules = rules
        @users.save_user(@current_user)
      end
      log_action("user.notification_suppression_rules", "user ##{@current_user.id}", notification_suppression_rules: rules)
      puts "Updated suppression rules: #{rules.empty? ? 'none' : rules.join(', ')}"
    end

    def update_notification_preferences(key, value)
      prefs = (@current_user.notification_preferences || {}).dup
      prefs[key.to_s] = parse_boolean(value)
      updated_user = @users.update(@current_user.id, notification_preferences: prefs)
      if updated_user
        @current_user = updated_user
      else
        @current_user.notification_preferences = prefs
        @users.save_user(@current_user)
      end
      log_action("user.notification_preferences", "user ##{@current_user.id}", notification_preferences: prefs)
      puts "Updated notification preference #{key} to #{prefs[key.to_s]}."
    end

    def send_email_notifications(ticket, subject:, body:, event:)
      recipients = email_recipients(ticket)
      if recipients.empty?
        puts "No email recipients for ticket ##{ticket.id}."
        return
      end

      recipients.each do |user|
        next if suppressed_notification?(user, ticket, event)

        puts "[email mock] To: #{user.display_name}"
        puts "[email mock] Subject: #{subject}"
        puts "[email mock] Body: #{body}"
      end
      log_action("notification.email", "ticket ##{ticket.id}", recipients: recipients.map(&:display_name), subject: subject)
    end

    def email_recipients(ticket)
      watcher_ids = ticket.watchers || []
      users = watcher_ids.map { |watcher_id| @users.find(watcher_id) }.compact
      users.select do |user|
        user.email.to_s.strip != "" &&
          user.email_notifications_enabled? &&
          user.preference_enabled?("watchers")
      end
    end

    def suppressed_notification?(user, ticket, event)
      rules = user.notification_suppression_rules || []
      rules.include?("all") ||
        (event == "comments" && rules.include?("comments")) ||
        (event == "reminders" && rules.include?("reminders")) ||
        (event == "manual" && rules.include?("manual")) ||
        rules.include?("watchers") ||
        (ticket.closed? && rules.include?("closed_tickets"))
    end

    def parse_boolean(value)
      case value.to_s.strip.downcase
      when "true", "yes", "on", "1" then true
      when "false", "no", "off", "0" then false
      else
        raise ArgumentError, "invalid boolean value: #{value}"
      end
    end

    def log_action(action, subject, details = {})
      actor = @current_user ? @current_user.display_name : "system"
      @audit_log.append(action: action, actor: actor, subject: subject, details: details)
      dispatch_hooks(action, actor, subject, details)
      dispatch_webhooks(action, actor, subject, details)
    end

    def run_plugin_command(command, args)
      plugin = @plugins.find_by_name(command)
      return false if plugin.nil? || plugin["enabled"] == false

      run_plugin(plugin, args)
      true
    end

    def run_plugin_by_name(name, args)
      plugin = @plugins.find_by_name(name)
      return puts("Plugin not found.") unless plugin
      return puts("Plugin is disabled.") if plugin["enabled"] == false

      run_plugin(plugin, args)
    end

    def run_plugin(plugin, args)
      command = @plugins.run(plugin["name"], args: args)
      return puts("Plugin not found.") unless command

      rendered = command[:command]
      env = {
        "HELPDESK_PLUGIN_ID" => plugin["id"].to_s,
        "HELPDESK_PLUGIN_NAME" => plugin["name"].to_s,
        "HELPDESK_PLUGIN_ARGS" => Array(args).join(" "),
        "HELPDESK_PLUGIN_COMMAND" => rendered
      }

      puts "[plugin mock] Running plugin ##{plugin["id"]} #{plugin["name"]}: #{rendered}"
      success = system(env, rendered)
      if success
        puts "[plugin mock] Completed."
      else
        status = $?.respond_to?(:exitstatus) ? $?.exitstatus : nil
        puts "[plugin mock] Failed#{status ? " (exit #{status})" : ""}."
      end

      log_action("plugin.run", "plugin ##{plugin["id"]}", name: plugin["name"], args: Array(args), success: success)
      success
    end

    def dispatch_hooks(action, actor, subject, details)
      return if @hooks.nil?

      @hooks.matching(action).each do |hook|
        payload = hook_payload(action, subject, details, actor: actor)
        deliver_hook(hook, payload)
      end
    end

    def dispatch_webhooks(action, actor, subject, details)
      return if @webhooks.nil?

      @webhooks.matching(action).each do |webhook|
        payload = webhook_payload(action, subject, details, actor: actor)
        deliver_webhook(webhook, payload)
      end
    end

    def webhook_payload(action, subject, details, actor: nil)
      {
        "action" => action,
        "subject" => subject,
        "actor" => actor || (@current_user ? @current_user.display_name : "system"),
        "details" => details,
        "created_at" => Time.now.utc.iso8601
      }
    end

    def hook_payload(action, subject, details, actor: nil)
      webhook_payload(action, subject, details, actor: actor)
    end

    def deliver_hook(hook, payload)
      command = hook["command"].to_s.strip
      env = {
        "HELPDESK_HOOK_ID" => hook["id"].to_s,
        "HELPDESK_HOOK_NAME" => hook["name"].to_s,
        "HELPDESK_HOOK_EVENT" => payload["action"].to_s,
        "HELPDESK_HOOK_SUBJECT" => payload["subject"].to_s,
        "HELPDESK_HOOK_ACTOR" => payload["actor"].to_s,
        "HELPDESK_HOOK_DETAILS" => JSON.generate(payload["details"] || {}),
        "HELPDESK_HOOK_PAYLOAD" => JSON.generate(payload)
      }

      puts "[hook mock] Running hook ##{hook["id"]} #{hook["name"]}: #{command}"
      success = system(env, command)
      if success
        puts "[hook mock] Completed."
      else
        status = $?.respond_to?(:exitstatus) ? $?.exitstatus : nil
        puts "[hook mock] Failed#{status ? " (exit #{status})" : ""}."
      end

      @audit_log.append(
        action: "hook.trigger",
        actor: payload["actor"],
        subject: "hook ##{hook["id"]}",
        details: {
          event: payload["action"],
          target: payload["subject"],
          success: success
        }
      )
      success
    end

    def deliver_webhook(webhook, payload)
      max_attempts = 3
      max_attempts.times do |attempt_index|
        attempt = attempt_index + 1
        puts "[webhook mock] Attempt #{attempt}/#{max_attempts} POST #{webhook["url"]}"
        puts "[webhook mock] Webhook ##{webhook["id"]} #{webhook["name"]}"
        puts "[webhook mock] Event: #{payload["action"]}"
        puts "[webhook mock] Payload: #{JSON.generate(payload)}"

        if webhook_delivery_succeeds?(webhook, payload, attempt)
          puts "[webhook mock] Delivered."
          return true
        end

        if attempt < max_attempts
          puts "[webhook mock] Delivery failed, retrying..."
        else
          puts "[webhook mock] Delivery failed after #{max_attempts} attempts."
        end
      end

      false
    end

    def webhook_delivery_succeeds?(webhook, payload, attempt)
      url = webhook["url"].to_s
      mode = payload.dig("details", "mode").to_s

      return false if mode == "fail"
      return attempt >= 3 if mode == "flaky"
      return false if url.include?("fail")
      return attempt >= 3 if url.include?("flaky")

      true
    end

    def parse_audit_options(args)
      options = {}
      idx = 0
      while idx < args.length
        case args[idx]
        when "--last"
          options[:last] = args[idx + 1].to_i
          idx += 2
        when "--action"
          options[:action] = args[idx + 1]
          idx += 2
        when "--actor"
          options[:actor] = args[idx + 1]
          idx += 2
        when "--subject"
          options[:subject] = args[idx + 1]
          idx += 2
        else
          idx += 1
        end
      end
      options
    end

    def parse_activity_options(args)
      options = { last: 10 }
      idx = 0
      while idx < args.length
        case args[idx]
        when "--last"
          options[:last] = args[idx + 1].to_i
          idx += 2
        when "--ticket"
          options[:ticket] = args[idx + 1].to_i
          idx += 2
        else
          idx += 1
        end
      end
      options
    end

    def activity_visible?(entry)
      action = entry["action"].to_s
      action.start_with?("ticket.") ||
        action.start_with?("reminder.") ||
        action.start_with?("notification.") ||
        action.start_with?("user.") ||
        action.start_with?("hook.") ||
        action.start_with?("plugin.") ||
        action.start_with?("escalation.") ||
        action == "tickets.import"
    end

    def resolve_alias(command)
      command_aliases.fetch(command.to_s, command.to_s)
    end

    def normalize_menu_choice(choice)
      choice.to_s.strip.downcase
    end

    def command_aliases
      {
        "ls" => "list",
        "showt" => "show",
        "newt" => "new",
        "create" => "new",
        "add" => "new",
        "rm" => "delete",
        "del" => "delete",
        "done" => "close",
        "q" => "quit",
        "quit" => "quit",
        "stats" => "dashboard"
      }
    end

    def activity_entries_for_ticket(ticket_id)
      @audit_log.all.select do |entry|
        activity_visible?(entry) && activity_entry_for_ticket?(entry, ticket_id)
      end.last(5)
    end

    def activity_entry_for_ticket?(entry, ticket_id)
      return false if ticket_id.nil?

      entry["subject"].to_s.match?(/\bticket ##{Regexp.escape(ticket_id.to_s)}\b/)
    end

    def format_activity_entry(entry)
      action = entry["action"].to_s
      subject = entry["subject"].to_s
      actor = entry["actor"].to_s
      created_at = entry["created_at"].to_s

      label =
        case action
        when "ticket.create"
          "created #{subject}"
        when "ticket.update"
          "updated #{subject}"
        when "ticket.delete"
          "deleted #{subject}"
        when "ticket.restore"
          "restored #{subject}"
        when "hook.create"
          "created #{subject}"
        when "hook.delete"
          "removed #{subject}"
        when "hook.trigger"
          "triggered #{subject}"
        when "plugin.create"
          "created #{subject}"
        when "plugin.delete"
          "removed #{subject}"
        when "plugin.run"
          "ran #{subject}"
        when "ticket.close"
          "closed #{subject}"
        when "ticket.status"
          "changed #{subject} to #{entry.dig("details", "status")}"
        when "ticket.comment"
          "commented on #{subject}"
        when "ticket.note"
          "added an internal note to #{subject}"
        when "ticket.watch_add"
          "added watcher to #{subject}"
        when "ticket.watch_remove"
          "removed watcher from #{subject}"
        when "ticket.attach_add"
          "added attachment to #{subject}"
        when "ticket.attach_remove"
          "removed attachment from #{subject}"
        when "ticket.merge"
          "merged #{subject}"
        when "ticket.relate"
          "related #{subject}"
        when "ticket.unrelate"
          "removed relationship for #{subject}"
        when "ticket.parent_set"
          "set parent for #{subject}"
        when "ticket.parent_clear"
          "cleared parent for #{subject}"
        when "ticket.dependency_add"
          "added dependency to #{subject}"
        when "ticket.dependency_remove"
          "removed dependency from #{subject}"
        when "ticket.archive"
          "archived #{subject}"
        when "ticket.unarchive"
          "unarchived #{subject}"
        when "ticket.tag.add"
          "added tag to #{subject}"
        when "ticket.tag.remove"
          "removed tag from #{subject}"
        when "reminder.set"
          "set a reminder on #{subject}"
        when "reminder.clear"
          "cleared a reminder on #{subject}"
        when "reminder.repeat_set"
          "set a repeating reminder on #{subject}"
        when "reminder.repeat_clear"
          "cleared repeating reminder on #{subject}"
        when "notification.email"
          "sent email notification for #{subject}"
        when "user.create"
          "created #{subject}"
        when "user.switch"
          "switched to #{subject}"
        when "user.role"
          "changed role for #{subject}"
        when "escalation.record"
          "escalated #{subject}"
        when "escalation.rules_set"
          "updated escalation rules for #{subject}"
        when "escalation.rules_reset"
          "reset escalation rules for #{subject}"
        when "user.notification_preferences"
          "updated notification preferences for #{subject}"
        when "user.notification_suppression_rules"
          "updated suppression rules for #{subject}"
        when "tickets.import"
          "imported tickets"
        else
          "#{action} #{subject}"
        end

      "#{created_at} #{actor} #{label}"
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
