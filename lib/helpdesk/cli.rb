require "shellwords"
require "time"
require "helpdesk/store"

module Helpdesk
  class CLI
    def initialize(store: Store.new)
      @store = store
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
        when "status" then change_status(args)
        when "comment" then add_comment(args)
        when "tag" then manage_tags(args)
        when "search" then search(args)
        when "overdue" then overdue
        when "stats" then stats
        when "exit", "quit" then break
        else
          puts "Unknown command: #{command}. Type 'help'."
        end
      end
    end

    private

    def banner
      "Helpdesk CLI - type 'help' for commands"
    end

    def print_help
      puts <<~HELP
        Commands:
          help
          list [--status STATUS] [--priority PRIORITY] [--tag TAG] [--sort created_at|priority] [--overdue]
          overdue
          show ID
          new
          edit ID
          delete ID
          status ID STATUS
          comment ID TEXT
          tag add ID TAG
          tag remove ID TAG
          search QUERY
          stats
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
    end

    def create_ticket
      title = prompt("Title")
      description = prompt("Description")
      status = prompt("Status", "open")
      priority = prompt("Priority", "medium")
      due_at = prompt("Due date (YYYY-MM-DD)", "")
      tags = prompt("Tags (comma separated)", "").split(",").map(&:strip).reject(&:empty?)
      ticket = @store.create(
        title: title,
        description: description,
        status: status,
        priority: priority,
        due_at: due_at,
        tags: tags
      )
      puts "Created ticket ##{ticket.id}."
    rescue ArgumentError => e
      puts e.message
    end

    def edit_ticket(args)
      id = required_id(args)
      ticket = @store.find(id)
      return puts "Ticket not found." unless ticket

      attrs = {}
      attrs[:title] = prompt("Title", ticket.title)
      attrs[:description] = prompt("Description", ticket.description)
      attrs[:status] = prompt("Status", ticket.status)
      attrs[:priority] = prompt("Priority", ticket.priority)
      attrs[:due_at] = prompt("Due date (YYYY-MM-DD)", ticket.due_at || "")
      attrs[:tags] = prompt("Tags (comma separated)", ticket.tags.join(", ")).split(",").map(&:strip).reject(&:empty?)
      @store.update(id, attrs)
      puts "Updated ticket ##{id}."
    rescue ArgumentError => e
      puts e.message
    end

    def delete_ticket(args)
      id = required_id(args)
      if @store.delete(id)
        puts "Deleted ticket ##{id}."
      else
        puts "Ticket not found."
      end
    end

    def change_status(args)
      id = required_id(args)
      status = args[1]
      ticket = @store.update(id, status: status)
      if ticket
        puts "Updated ticket ##{id} to #{ticket.status}."
      else
        puts "Ticket not found."
      end
    rescue ArgumentError => e
      puts e.message
    end

    def add_comment(args)
      id = required_id(args)
      ticket = @store.find(id)
      return puts "Ticket not found." unless ticket

      body = args.drop(1).join(" ")
      body = prompt("Comment") if body.strip.empty?
      ticket.add_comment(body: body, author: prompt("Author", "agent"))
      @store.save_ticket(ticket)
      puts "Added comment to ticket ##{id}."
    end

    def manage_tags(args)
      action = args[0]
      id = args[1]
      tag = args[2]
      ticket = @store.find(id)
      return puts "Ticket not found." unless ticket

      case action
      when "add"
        ticket.add_tag(tag)
        @store.save_ticket(ticket)
        puts "Added tag to ticket ##{id}."
      when "remove"
        ticket.remove_tag(tag)
        @store.save_ticket(ticket)
        puts "Removed tag from ticket ##{id}."
      else
        puts "Usage: tag add|remove ID TAG"
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

    def stats
      tickets = @store.all
      counts = tickets.group_by(&:status).transform_values(&:count)
      puts "Total tickets: #{tickets.count}"
      puts "Overdue: #{tickets.count(&:overdue?)}"
      puts "Open: #{counts.fetch("open", 0)}"
      puts "In progress: #{counts.fetch("in_progress", 0)}"
      puts "Waiting: #{counts.fetch("waiting", 0)}"
      puts "Resolved: #{counts.fetch("resolved", 0)}"
      puts "Closed: #{counts.fetch("closed", 0)}"
      puts "Total comments: #{tickets.sum { |ticket| ticket.comments.count }}"
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

    def required_id(args)
      id = args[0]
      raise ArgumentError, "Usage requires an ID" if id.nil? || id.strip.empty?

      id.to_i
    end
  end
end
