require "shellwords"
require "time"
require "csv"
require "json"
require "fileutils"
require "helpdesk/audit_log"
require "helpdesk/store"
require "helpdesk/user_store"

module Helpdesk
  class CLI
    def initialize(store: Store.new)
      @store = store
      @audit_log = AuditLog.new
      @users = UserStore.new
      seed_default_user
      @current_user = @users.all.first
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
        case command
        when "help" then print_help
        when "list" then list(args)
        when "show" then show(args)
        when "new" then create_ticket
        when "edit" then edit_ticket(args)
        when "delete" then delete_ticket(args)
        when "close" then close_tickets(args)
        when "status" then change_status(args)
        when "comment" then add_comment(args)
        when "note" then add_note(args)
        when "watch" then manage_watchers(args)
        when "tag" then manage_tags(args)
        when "search" then search(args)
        when "overdue" then overdue
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
        when "exit", "quit" then break
        else
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
          list [--status STATUS] [--priority PRIORITY] [--tag TAG] [--sort created_at|priority] [--overdue]
          overdue
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
          status ID STATUS
          comment ID TEXT
          note ID TEXT
          watch add ID USER_ID
          watch remove ID USER_ID
          watch list ID
          tag add ID [ID ...] TAG
          tag remove ID [ID ...] TAG
          search QUERY
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
          whoami
          audit [--last N] [--action ACTION] [--actor NAME] [--subject TEXT]
          exit
      HELP
    end

    def list(args)
      options = parse_options(args)
      tickets = @store.all
      tickets = tickets.select { |ticket| ticket.status == options[:status] } if options[:status]
      tickets = tickets.select { |ticket| ticket.priority == options[:priority] } if options[:priority]
      tickets = tickets.select { |ticket| ticket.tags.include?(options[:tag]) } if options[:tag]
      tickets = tickets.select(&:overdue?) if options[:overdue]
      tickets = sort_tickets(tickets, options[:sort])

      if tickets.empty?
        puts "No tickets found."
        return
      end

      tickets.each { |ticket| puts format_ticket_row(ticket) }
    end

    def show(args)
      ticket = @store.find(required_id(args))
      return puts "Ticket not found." unless ticket

      puts "##{ticket.id} #{ticket.title}"
      puts "Status: #{ticket.status}"
      puts "Priority: #{ticket.priority}"
      puts "Due: #{ticket.due_at || 'none'}"
      puts "Overdue: #{ticket.overdue? ? 'yes' : 'no'}"
      puts "Reminder: #{ticket.reminder_at || 'none'}"
      puts "Reminder repeat: #{ticket.reminder_repeat || 'none'}"
      puts "Reminder due: #{ticket.reminder_due? ? 'yes' : 'no'}"
      puts "Tags: #{ticket.tags.join(", ")}"
      puts "Created: #{ticket.created_at}"
      puts "Updated: #{ticket.updated_at}"
      puts "Description:"
      puts ticket.description
      puts "Comments:"
      if ticket.comments.empty?
        puts "  none"
      else
        ticket.comments.each do |comment|
          puts "  [#{comment["id"]}] #{comment["author"]} @ #{comment["created_at"]}: #{comment["body"]}"
        end
      end
      puts "Internal notes:"
      if ticket.internal_notes.empty?
        puts "  none"
      else
        ticket.internal_notes.each do |note|
          puts "  [#{note["id"]}] #{note["author"]} @ #{note["created_at"]}: #{note["body"]}"
        end
      end
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

    def create_ticket
      return unless require_permission!(:ticket_write)

      title = prompt("Title")
      description = prompt("Description")
      status = prompt("Status", "open")
      priority = prompt("Priority", "medium")
      due_at = prompt("Due date (YYYY-MM-DD)", "")
      reminder_at = prompt("Reminder time (YYYY-MM-DD HH:MM, optional)", "")
      reminder_repeat = prompt("Reminder repeat (daily, weekly, monthly, optional)", "")
      tags = prompt("Tags (comma separated)", "").split(",").map(&:strip).reject(&:empty?)
      ticket = @store.create(
        title: title,
        description: description,
        status: status,
        priority: priority,
        due_at: due_at,
        reminder_at: reminder_at,
        reminder_repeat: reminder_repeat,
        tags: tags
      )
      log_action("ticket.create", "ticket ##{ticket.id}", title: ticket.title, status: ticket.status, priority: ticket.priority)
      puts "Created ticket ##{ticket.id}."
    rescue ArgumentError => e
      puts e.message
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
      attrs[:due_at] = prompt("Due date (YYYY-MM-DD)", ticket.due_at || "")
      attrs[:reminder_at] = prompt("Reminder time (YYYY-MM-DD HH:MM, optional)", ticket.reminder_at || "")
      attrs[:reminder_repeat] = prompt("Reminder repeat (daily, weekly, monthly, optional)", ticket.reminder_repeat || "")
      attrs[:tags] = prompt("Tags (comma separated)", ticket.tags.join(", ")).split(",").map(&:strip).reject(&:empty?)
      @store.update(id, attrs)
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
        puts "Deleted ticket ##{id}."
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

      closed_ids = @store.bulk_close(ids)
      if closed_ids.empty?
        puts "No matching tickets found."
      else
        closed_ids.each { |ticket_id| log_action("ticket.close", "ticket ##{ticket_id}") }
        puts "Closed tickets: #{closed_ids.map { |id| "##{id}" }.join(", ")}"
      end
    end

    def change_status(args)
      return unless require_permission!(:ticket_write)

      id = required_id(args)
      status = args[1]
      ticket = @store.update(id, status: status)
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
      query = args.join(" ").strip.downcase
      if query.empty?
        puts "Usage: search QUERY"
        return
      end

      matches = @store.all.select do |ticket|
        haystack = [
          ticket.title,
          ticket.description,
          ticket.status,
          ticket.priority,
          ticket.tags.join(" "),
          ticket.comments.map { |comment| comment["body"] }.join(" ")
        ].join(" ").downcase
        haystack.include?(query)
      end

      if matches.empty?
        puts "No tickets found."
      else
        matches.each { |ticket| puts format_ticket_row(ticket) }
      end
    end

    def dashboard
      tickets = @store.all
      counts = tickets.group_by(&:status).transform_values(&:count)
      priority_counts = tickets.group_by(&:priority).transform_values(&:count)
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
        count = @store.import_json(path)
        log_action("tickets.import", "tickets", source: path, count: count)
        puts "Imported #{count} tickets from #{path}."
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
        log_action("user.create", "user ##{user.id}", name: user.name, role: user.role_label)
        puts "Created user ##{user.id}."
      when "switch"
        user = @users.find(required_id(args.drop(1)))
        return puts "User not found." unless user

        log_action("user.switch", "user ##{user.id}", name: user.name, role: user.role_label)
        @current_user = user
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
      else
        puts "Usage: notify show | notify set KEY VALUE"
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
        tickets.sort_by { |ticket| order.fetch(ticket.priority, 99) }
      else
        tickets.sort_by { |ticket| ticket.created_at }
      end
    end

    def format_ticket_row(ticket)
      overdue_marker = ticket.overdue? ? " overdue" : ""
      "##{ticket.id} [#{ticket.status}/#{ticket.priority}#{overdue_marker}] #{ticket.title}#{ticket.tags.empty? ? '' : " ##{ticket.tags.join(' #')}"}"
    end

    def overdue
      tickets = @store.all.select(&:overdue?)
      if tickets.empty?
        puts "No overdue tickets."
        return
      end

      tickets.each { |ticket| puts format_ticket_row(ticket) }
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
