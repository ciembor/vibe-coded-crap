require "helpdesk/activity_presenter"
require "helpdesk/ticket_presenter"

module Helpdesk
  module CliTicketCommands
    private

    def list(args)
      options = parse_options(args)
      include_deleted = truthy_option?(options, :deleted)
      tickets = filter_tickets(@store.all(include_deleted: include_deleted), options)

      if tickets.empty?
        puts "No tickets found."
        return
      end

      tickets.each { |ticket| puts TicketPresenter.row(ticket) }
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
      puts "SLA: #{TicketPresenter.sla_status(ticket)}"
      puts "Escalation: #{TicketPresenter.escalation_status(ticket)}"
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
      activity = @audit_log.all.select do |entry|
        ActivityPresenter.visible?(entry) && ActivityPresenter.for_ticket?(entry, ticket.id)
      end.last(5)
      puts "Activity:"
      if activity.empty?
        puts "  none"
      else
        activity.each do |entry|
          puts "  #{ActivityPresenter.line(entry)}"
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
          related.each { |related_ticket| puts TicketPresenter.row(related_ticket) }
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
        puts parent ? "  #{TicketPresenter.row(parent)}" : "  none"
        puts "Children:"
        if children.empty?
          puts "  none"
        else
          children.each { |child| puts "  #{TicketPresenter.row(child)}" }
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
          dependencies.each { |dependency| puts "  #{TicketPresenter.row(dependency)}" }
        end
        puts "Blocked by:"
        if dependents.empty?
          puts "  none"
        else
          dependents.each { |dependent| puts "  #{TicketPresenter.row(dependent)}" }
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
            puts TicketPresenter.row(ticket)
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
            puts TicketPresenter.row(ticket)
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

    def overdue
      tickets = @store.all.select(&:overdue?)
      if tickets.empty?
        puts "No overdue tickets."
        return
      end

      tickets.each { |ticket| puts TicketPresenter.row(ticket) }
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
        puts TicketPresenter.row(ticket)
        puts "  Escalation: #{TicketPresenter.escalation_status(ticket)}"
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
          puts "  #{TicketPresenter.row(candidate)}"
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
          puts "  #{TicketPresenter.row(related_ticket)}"
        end
      end
    end

    def show_hierarchy(ticket)
      parent = @store.parent_ticket(ticket)
      children = @store.child_tickets(ticket)

      puts "Parent ticket:"
      if parent
        puts "  #{TicketPresenter.row(parent)}"
      else
        puts "  none"
      end

      puts "Child tickets:"
      if children.empty?
        puts "  none"
      else
        children.each do |child|
          puts "  #{TicketPresenter.row(child)}"
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
          puts "  #{TicketPresenter.row(dependency)}"
        end
      end

      puts "Blocked by:"
      if dependents.empty?
        puts "  none"
      else
        dependents.each do |dependent|
          puts "  #{TicketPresenter.row(dependent)}"
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
      entries = entries.select { |entry| ActivityPresenter.for_ticket?(entry, ticket_id) } if ticket_id
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
        puts TicketPresenter.row(ticket)
        puts "  SLA: #{TicketPresenter.sla_status(ticket)}"
      end
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
  end
end
