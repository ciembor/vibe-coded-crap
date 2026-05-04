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
        internal_notes: attrs.fetch(:internal_notes, []),
        attachments: attrs.fetch(:attachments, []),
        custom_fields: attrs.fetch(:custom_fields, {}),
        ticket_type: attrs.fetch(:ticket_type, "general"),
        due_at: attrs.fetch(:due_at, nil),
        reminder_at: attrs.fetch(:reminder_at, nil),
        reminder_repeat: attrs.fetch(:reminder_repeat, nil)
      ).normalize!
      validate_ticket!(ticket)
      tickets << ticket.to_h
      save!(tickets)
      ticket
    end

    def update(id, attrs)
      tickets = load_data
      index = tickets.index { |row| row["id"].to_i == id.to_i }
      return nil unless index

      ticket = Ticket.from_h(tickets[index]).update(attrs)
      validate_ticket!(ticket)
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
      validate_ticket!(ticket)
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

    def merge(source_id, target_id)
      source_id = source_id.to_i
      target_id = target_id.to_i
      raise ArgumentError, "merge requires two ticket IDs" if source_id.zero? || target_id.zero?
      raise ArgumentError, "cannot merge a ticket into itself" if source_id == target_id

      tickets = load_data
      source_index = tickets.index { |row| row["id"].to_i == source_id }
      target_index = tickets.index { |row| row["id"].to_i == target_id }
      return nil unless source_index && target_index

      source = Ticket.from_h(tickets[source_index])
      target = Ticket.from_h(tickets[target_index])

      source.comments.each do |comment|
        target.add_comment(
          body: "[Merged from ##{source.id}] #{comment["body"]}",
          author: comment["author"]
        )
      end

      source.internal_notes.each do |note|
        target.add_internal_note(
          body: "[Merged from ##{source.id}] #{note["body"]}",
          author: note["author"]
        )
      end

      source.attachments.each do |attachment|
        target.add_attachment(
          name: "[Merged from ##{source.id}] #{attachment["name"]}",
          content_type: attachment["content_type"],
          size: attachment["size"],
          description: attachment["description"],
          uploaded_by: attachment["uploaded_by"]
        )
      end

      source.tags.each { |tag| target.add_tag(tag) }
      source.watchers.each { |watcher_id| target.add_watcher(watcher_id) }

      source.custom_fields.each do |key, value|
        target.custom_fields[key] = value if target.custom_fields[key].to_s.strip.empty?
      end

      target.send(:add_merged_from, source.id)
      source.send(:merge_into!, target.id)
      source.description = [source.description, "Merged into ticket ##{target.id}."].reject(&:empty?).join("\n\n")
      source.custom_fields = source.custom_fields.merge("merged_into" => target.id.to_s)

      tickets[target_index] = target.to_h
      tickets[source_index] = source.to_h
      save!(tickets)
      { source: source, target: target }
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

    def validate_ticket!(ticket)
      errors = ticket.validation_errors
      return if errors.empty?

      raise ArgumentError, errors.join("; ")
    end
  end
end
