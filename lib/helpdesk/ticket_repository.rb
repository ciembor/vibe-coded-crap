require "helpdesk/json_file"
require "helpdesk/ticket"

module Helpdesk
  class TicketRepository
    include JsonFileStore

    class TicketSet
      include Enumerable

      def initialize(tickets)
        @tickets = tickets
      end

      def each(&block)
        @tickets.each(&block)
      end

      def all(include_deleted: false)
        include_deleted ? @tickets : @tickets.reject(&:deleted?)
      end

      def find(id = nil, &block)
        return @tickets.find(&block) if block_given?

        @tickets.find { |ticket| ticket.id.to_i == id.to_i }
      end

      def add(ticket)
        @tickets << ticket
      end

      def upsert(ticket)
        index = @tickets.index { |existing| existing.id.to_i == ticket.id.to_i }
        if index
          @tickets[index] = ticket
        else
          @tickets << ticket
        end
      end

      def next_id
        (@tickets.map { |ticket| ticket.id.to_i }.max || 0) + 1
      end

      def to_rows
        @tickets.map(&:to_h)
      end
    end

    def initialize(path:, validator: nil)
      configure_json_file(path, default: [])
      @validator = validator || ->(_ticket) {}
    end

    def all(include_deleted: false)
      ticket_set.all(include_deleted: include_deleted)
    end

    def find(id, include_deleted: false)
      all(include_deleted: include_deleted).find { |ticket| ticket.id.to_i == id.to_i }
    end

    def create(attrs)
      transaction do |tickets|
        ticket = build_ticket(tickets.next_id, attrs)
        validate!(ticket)
        tickets.add(ticket)
        ticket
      end
    end

    def update(id, attrs)
      transaction do |tickets|
        ticket = tickets.find(id)
        next nil unless ticket
        next nil if ticket.deleted?

        yield ticket, attrs, tickets if block_given?
        ticket.update(attrs)
        validate!(ticket)
        ticket
      end
    end

    def save_ticket(ticket)
      validate!(ticket)
      transaction do |tickets|
        tickets.upsert(ticket)
        ticket
      end
    end

    def restore_rows(rows)
      stored_rows = load_data
      Array(rows).each do |row|
        index = stored_rows.index { |existing| existing["id"].to_i == row["id"].to_i }
        if index
          stored_rows[index] = row
        else
          stored_rows << row
        end
      end
      save!(stored_rows)
    end

    def transaction
      tickets = ticket_set
      result = yield tickets
      save!(tickets.to_rows)
      result
    end

    def validate!(ticket)
      @validator.call(ticket)
    end

    private

    def ticket_set
      TicketSet.new(load_data.map { |row| Ticket.from_h(row) })
    end

    def build_ticket(id, attrs)
      ticket_type = attrs.fetch(:ticket_type, "general")
      Ticket.new(
        id: id,
        title: attrs.fetch(:title),
        description: attrs.fetch(:description, ""),
        status: attrs.fetch(:status, Ticket.initial_status_for(ticket_type)),
        priority: attrs.fetch(:priority, "medium"),
        tags: attrs.fetch(:tags, []),
        internal_notes: attrs.fetch(:internal_notes, []),
        attachments: attrs.fetch(:attachments, []),
        custom_fields: attrs.fetch(:custom_fields, {}),
        ticket_type: ticket_type,
        due_at: attrs.fetch(:due_at, nil),
        reminder_at: attrs.fetch(:reminder_at, nil),
        reminder_repeat: attrs.fetch(:reminder_repeat, nil)
      ).normalize!
    end
  end
end
