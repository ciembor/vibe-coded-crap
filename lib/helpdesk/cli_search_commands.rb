require "time"
require "helpdesk/ticket_presenter"

module Helpdesk
  module CliSearchCommands
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
        puts "#{filter["name"]}: #{TicketPresenter.filter_options(filter["options"])}"
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
        tickets.each { |ticket| puts TicketPresenter.row(ticket) }
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
        matches.each { |ticket| puts TicketPresenter.row(ticket) }
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
  end
end
