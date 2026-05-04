require "json"
require "fileutils"
require "helpdesk/ticket"

module Helpdesk
  class Store
    attr_reader :path

    def initialize(path: default_path)
      @path = path
      FileUtils.mkdir_p(File.dirname(path))
      save!([]) unless File.exist?(path)
    end

    def all
      load_data.map { |row| Ticket.from_h(row) }
    end

    def find(id)
      all.find { |ticket| ticket.id.to_i == id.to_i }
    end

    def create(attrs)
      tickets = load_data
      ticket = Ticket.new(
        id: next_id(tickets),
        title: attrs.fetch(:title),
        description: attrs.fetch(:description, ""),
        status: attrs.fetch(:status, "open"),
        priority: attrs.fetch(:priority, "medium"),
        tags: attrs.fetch(:tags, []),
        due_at: attrs.fetch(:due_at, nil),
        reminder_at: attrs.fetch(:reminder_at, nil),
        reminder_repeat: attrs.fetch(:reminder_repeat, nil)
      ).normalize!
      tickets << ticket.to_h
      save!(tickets)
      ticket
    end

    def update(id, attrs)
      tickets = load_data
      index = tickets.index { |row| row["id"].to_i == id.to_i }
      return nil unless index

      ticket = Ticket.from_h(tickets[index]).update(attrs)
      tickets[index] = ticket.to_h
      save!(tickets)
      ticket
    end

    def delete(id)
      tickets = load_data
      removed = tickets.reject! { |row| row["id"].to_i == id.to_i }
      save!(tickets) if removed
      !removed.nil?
    end

    def bulk_close(ids)
      id_list = Array(ids).map(&:to_i).uniq
      return [] if id_list.empty?

      tickets = load_data
      closed_ids = []

      tickets.each do |row|
        next unless id_list.include?(row["id"].to_i)

        ticket = Ticket.from_h(row)
        ticket.update(status: "closed")
        row.replace(ticket.to_h)
        closed_ids << ticket.id
      end

      save!(tickets)
      closed_ids
    end

    def bulk_tag(ids, tag, action:)
      id_list = Array(ids).map(&:to_i).uniq
      tag = tag.to_s.strip
      return [] if id_list.empty? || tag.empty?

      tickets = load_data
      touched_ids = []

      tickets.each do |row|
        next unless id_list.include?(row["id"].to_i)

        ticket = Ticket.from_h(row)
        case action
        when "add"
          ticket.add_tag(tag)
        when "remove"
          ticket.remove_tag(tag)
        else
          raise ArgumentError, "invalid bulk tag action: #{action}"
        end
        row.replace(ticket.to_h)
        touched_ids << ticket.id
      end

      save!(tickets)
      touched_ids
    end

    def save_ticket(ticket)
      tickets = load_data
      index = tickets.index { |row| row["id"].to_i == ticket.id.to_i }
      if index
        tickets[index] = ticket.to_h
      else
        tickets << ticket.to_h
      end
      save!(tickets)
      ticket
    end

    def import_json(path)
      rows = JSON.parse(File.read(path))
      unless rows.is_a?(Array)
        raise ArgumentError, "import file must contain an array of tickets"
      end

      tickets = rows.map { |row| Ticket.from_h(row).to_h }
      save!(tickets)
      tickets.count
    rescue Errno::ENOENT
      raise ArgumentError, "import file not found: #{path}"
    rescue JSON::ParserError
      raise ArgumentError, "import file is not valid JSON: #{path}"
    end

    private

    def default_path
      File.expand_path("../../data/tickets.json", __dir__)
    end

    def load_data
      JSON.parse(File.read(path))
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def save!(rows)
      File.write(path, JSON.pretty_generate(rows))
    end

    def next_id(rows)
      (rows.map { |row| row["id"].to_i }.max || 0) + 1
    end
  end
end
