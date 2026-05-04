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
        when "attach" then manage_attachments(args)
        when "pin" then manage_pins(args)
        when "archive" then manage_archives(args)
        when "tag" then manage_tags(args)
        when "search" then search(args)
        when "searches" then list_saved_searches
        when "filter" then filter(args)
        when "filters" then list_favorite_filters
        when "field" then manage_custom_fields(args)
        when "activity" then activity(args)
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
          list [--status STATUS] [--priority PRIORITY] [--tag TAG] [--sort created_at|priority] [--overdue] [--archived|--active]
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
          activity [--last N] [--ticket ID]
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
          exit
      HELP
    end

    def list(args)
      options = parse_options(args)
      tickets = filter_tickets(@store.all, options)

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
      sort_tickets(tickets, option_value(options, :sort))
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
      puts "Pinned: #{ticket.pinned? ? 'yes' : 'no'}"
      puts "Pinned at: #{ticket.pinned_at || 'none'}"
      puts "Archived: #{ticket.archived? ? 'yes' : 'no'}"
      puts "Archived at: #{ticket.archived_at || 'none'}"
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
      puts "Custom fields:"
      if ticket.custom_fields.empty?
        puts "  none"
      else
        ticket.custom_fields.each do |key, value|
          puts "  #{key}: #{value}"
        end
      end
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
      else
        tickets.sort_by { |ticket| [ticket.archived? ? 1 : 0, ticket.pinned? ? 0 : 1, ticket.created_at.to_s] }
      end
    end

    def format_ticket_row(ticket)
      overdue_marker = ticket.overdue? ? " overdue" : ""
      pinned_marker = ticket.pinned? ? " pinned" : ""
      archived_marker = ticket.archived? ? " archived" : ""
      "##{ticket.id} [#{ticket.status}/#{ticket.priority}#{overdue_marker}#{pinned_marker}#{archived_marker}] #{ticket.title}#{ticket.tags.empty? ? '' : " ##{ticket.tags.join(' #')}"}"
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
      parts.empty? ? "none" : parts.join(" ")
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
        action == "tickets.import"
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
