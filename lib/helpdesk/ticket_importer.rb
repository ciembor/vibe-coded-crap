require "date"
require "json"
require "time"
require "helpdesk/ticket"
require "helpdesk/ticket_merger"

module Helpdesk
  class TicketImporter
    def initialize(rows, next_id:)
      @rows = rows
      @next_id = next_id
    end

    def import_json(path)
      imported_rows = JSON.parse(File.read(path))
      unless imported_rows.is_a?(Array)
        raise ArgumentError, "import file must contain an array of tickets"
      end

      imported = 0
      merged = 0
      remapped = 0

      imported_rows.each do |row|
        imported_ticket = Ticket.from_h(row)
        existing_index = index_for(imported_ticket.id)
        duplicate_index = duplicate_index_for(imported_ticket)

        if duplicate_index
          merged_ticket = merge_imported_ticket(Ticket.from_h(@rows[duplicate_index]), imported_ticket)
          @rows[duplicate_index] = merged_ticket.to_h
          merged += 1
        elsif existing_index
          remapped_ticket = Ticket.from_h(imported_ticket.to_h)
          remapped_ticket.id = @next_id.call(@rows)
          remapped_ticket.normalize!
          @rows << remapped_ticket.to_h
          remapped += 1
        else
          @rows << imported_ticket.to_h
        end

        imported += 1
      end

      { imported: imported, merged: merged, remapped: remapped }
    rescue Errno::ENOENT
      raise ArgumentError, "import file not found: #{path}"
    rescue JSON::ParserError
      raise ArgumentError, "import file is not valid JSON: #{path}"
    end

    private

    def index_for(id)
      @rows.index { |row| row["id"].to_i == id.to_i }
    end

    def duplicate_index_for(imported_ticket)
      @rows.index do |existing|
        Ticket.from_h(existing).duplicate_key == imported_ticket.duplicate_key
      end
    end

    def merge_imported_ticket(existing_ticket, imported_ticket)
      existing = Ticket.from_h(existing_ticket.to_h)
      source = imported_ticket

      existing.title = choose_nonempty(existing.title, source.title)
      existing.description = choose_nonempty(existing.description, source.description)
      existing.status = choose_status(existing.status, source.status)
      existing.priority = choose_priority(existing.priority, source.priority)
      existing.ticket_type = choose_nonempty(existing.ticket_type, source.ticket_type)
      existing.due_at = choose_due_at(existing.due_at, source.due_at)
      existing.reminder_at = choose_reminder_at(existing.reminder_at, source.reminder_at)
      existing.reminder_repeat = choose_nonempty(existing.reminder_repeat, source.reminder_repeat)
      existing.tags = (existing.tags + source.tags).uniq.sort
      existing.watchers = (existing.watchers + source.watchers).uniq.sort
      existing.pinned = existing.pinned? || source.pinned?
      existing.archived = existing.archived? || source.archived?
      existing.custom_fields = existing.custom_fields.merge(source.custom_fields) do |_key, left, right|
        left.to_s.strip.empty? ? right : left
      end

      TicketMerger.copy_activity(source, existing, label: "Imported from")
      existing.normalize!
    end

    def choose_nonempty(current, incoming)
      current.to_s.strip.empty? ? incoming : current
    end

    def choose_status(current, incoming)
      choose_by_order(current, incoming, %w[open in_progress waiting resolved closed])
    end

    def choose_priority(current, incoming)
      choose_by_order(current, incoming, %w[urgent high medium low])
    end

    def choose_by_order(current, incoming, order)
      current_index = order.index(current.to_s) || order.length
      incoming_index = order.index(incoming.to_s) || order.length
      incoming_index < current_index ? incoming : current
    end

    def choose_due_at(current, incoming)
      choose_earlier(current, incoming) { |value| parse_date(value) }
    end

    def choose_reminder_at(current, incoming)
      choose_earlier(current, incoming) { |value| parse_time(value) }
    end

    def choose_earlier(current, incoming)
      current_value = yield(current)
      incoming_value = yield(incoming)
      return incoming if current_value.nil? && incoming_value
      return current if incoming_value.nil? && current_value
      return current if current_value.nil? && incoming_value.nil?

      incoming_value < current_value ? incoming : current
    end

    def parse_date(value)
      return nil if value.to_s.strip.empty?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_time(value)
      return nil if value.to_s.strip.empty?

      Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end
  end
end
