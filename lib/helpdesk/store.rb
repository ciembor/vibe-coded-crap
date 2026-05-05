require "helpdesk/bulk_action_log"
require "helpdesk/ticket"
require "helpdesk/ticket_graph"
require "helpdesk/ticket_importer"
require "helpdesk/ticket_merger"
require "helpdesk/ticket_transition_policy"
require "helpdesk/json_file_store"

module Helpdesk
  class Store < JsonFileStore

    def initialize(path: default_path)
      @bulk_action_log = BulkActionLog.new
      super(path: path)
    end

    def all(include_deleted: false)
      load_data.map { |row| Ticket.from_h(row) }.select { |ticket| include_deleted || !ticket.deleted? }
    end

    def deleted_tickets
      all(include_deleted: true).select(&:deleted?)
    end

    def duplicate_groups
      tickets = all.reject(&:archived?)
      tickets.group_by(&:duplicate_key).values.select { |group| group.count > 1 }
    end

    def duplicate_candidates_for(ticket, limit: 5)
      key = ticket.duplicate_key
      candidates = all.reject { |existing| existing.id.to_i == ticket.id.to_i }
      matches =
        candidates.select do |existing|
          existing.duplicate_key == key ||
            existing.duplicate_title_key == ticket.duplicate_title_key
        end
      matches.sort_by { |existing| [existing.status == "closed" ? 1 : 0, existing.updated_at.to_s] }.take(limit)
    end

    def related_tickets(ticket)
      TicketGraph.related_tickets(ticket, all)
    end

    def parent_ticket(ticket)
      TicketGraph.parent_ticket(ticket, all)
    end

    def child_tickets(ticket)
      TicketGraph.child_tickets(ticket, all)
    end

    def dependencies_for(ticket)
      TicketGraph.dependencies_for(ticket, all)
    end

    def dependent_tickets(ticket)
      TicketGraph.dependent_tickets(ticket, all)
    end

    def open_dependencies_for(ticket)
      TicketGraph.open_dependencies_for(ticket, all)
    end

    def closeable_ticket?(ticket)
      TicketGraph.closeable?(ticket, all)
    end

    def relate(source_id, target_id)
      tickets = load_data
      result = TicketGraph.new(tickets).relate(source_id, target_id)
      return nil unless result

      save!(tickets)
      result
    end

    def unrelate(source_id, target_id)
      tickets = load_data
      result = TicketGraph.new(tickets).unrelate(source_id, target_id)
      return nil unless result

      save!(tickets)
      result
    end

    def set_parent(child_id, parent_id)
      tickets = load_data
      result = TicketGraph.new(tickets).set_parent(child_id, parent_id)
      return nil unless result

      save!(tickets)
      result
    end

    def clear_parent(child_id)
      tickets = load_data
      result = TicketGraph.new(tickets).clear_parent(child_id)
      return nil unless result

      save!(tickets)
      result
    end

    def add_dependency(ticket_id, dependency_id)
      tickets = load_data
      result = TicketGraph.new(tickets).add_dependency(ticket_id, dependency_id)
      return nil unless result

      save!(tickets)
      result
    end

    def remove_dependency(ticket_id, dependency_id)
      tickets = load_data
      result = TicketGraph.new(tickets).remove_dependency(ticket_id, dependency_id)
      return nil unless result

      save!(tickets)
      result
    end

    def find(id, include_deleted: false)
      all(include_deleted: include_deleted).find { |ticket| ticket.id.to_i == id.to_i }
    end

    def create(attrs)
      tickets = load_data
      ticket_type = attrs.fetch(:ticket_type, "general")
      ticket = Ticket.new(
        id: next_id(tickets),
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
      validate_ticket!(ticket)
      tickets << ticket.to_h
      save!(tickets)
      ticket
    end

    def update(id, attrs, actor_role: nil)
      tickets = load_data
      index = tickets.index { |row| row["id"].to_i == id.to_i }
      return nil unless index

      ticket = Ticket.from_h(tickets[index])
      return nil if ticket.deleted?
      if attrs.key?(:status)
        target_type = attrs.fetch(:ticket_type, ticket.ticket_type)
        target_status = TicketTransitionPolicy.new(ticket).normalize_status(attrs[:status], ticket_type: target_type)
        unless ticket.can_transition_to?(target_status, role: actor_role)
          raise ArgumentError, "transition #{ticket.status} -> #{target_status} is not permitted for #{actor_role || 'system'}"
        end

        if target_status == "closed"
          open_dependencies = open_dependencies_for(ticket)
          unless open_dependencies.empty?
            raise ArgumentError, "cannot close ticket ##{ticket.id} with open dependencies: #{open_dependencies.map { |dependency| "##{dependency.id}" }.join(", ")}"
          end
        end
      end

      ticket.update(attrs)
      validate_ticket!(ticket)
      tickets[index] = ticket.to_h
      save!(tickets)
      ticket
    end

    def delete(id)
      tickets = load_data
      index = tickets.index { |row| row["id"].to_i == id.to_i }
      return false unless index

      ticket = Ticket.from_h(tickets[index])
      return false if ticket.deleted?

      ticket.delete!
      tickets[index] = ticket.to_h
      save!(tickets)
      true
    end

    def restore(id)
      tickets = load_data
      index = tickets.index { |row| row["id"].to_i == id.to_i }
      return false unless index

      ticket = Ticket.from_h(tickets[index])
      return false unless ticket.deleted?

      ticket.restore_deleted!
      tickets[index] = ticket.to_h
      save!(tickets)
      true
    end

    def bulk_close(ids, actor_role: nil)
      id_list = Array(ids).map(&:to_i).uniq
      return [] if id_list.empty?

      tickets = load_data
      closed_ids = []
      affected_rows = []

      tickets.each do |row|
        next unless id_list.include?(row["id"].to_i)

        ticket = Ticket.from_h(row)
        next if ticket.deleted?
        next unless closeable_ticket?(ticket)
        next unless ticket.can_transition_to?("closed", role: actor_role)

        affected_rows << row.dup
        ticket.update(status: "closed")
        row.replace(ticket.to_h)
        closed_ids << ticket.id
      end

      save!(tickets)
      @bulk_action_log.append(action: "bulk_close", rows: affected_rows) unless affected_rows.empty?
      closed_ids
    end

    def bulk_tag(ids, tag, action:)
      id_list = Array(ids).map(&:to_i).uniq
      tag = tag.to_s.strip
      return [] if id_list.empty? || tag.empty?

      tickets = load_data
      touched_ids = []
      affected_rows = []

      tickets.each do |row|
        next unless id_list.include?(row["id"].to_i)

        ticket = Ticket.from_h(row)
        next if ticket.deleted?
        affected_rows << row.dup
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
      @bulk_action_log.append(action: "bulk_tag_#{action}", rows: affected_rows, metadata: { "tag" => tag }) unless affected_rows.empty?
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
      tickets = load_data
      result = TicketMerger.new(tickets).merge(source_id, target_id)
      return nil unless result

      save!(tickets)
      result
    end

    def undo_last_bulk_action
      entry = @bulk_action_log.pop_last
      return nil unless entry

      rows = entry["rows"] || []
      return nil if rows.empty?

      tickets = load_data
      rows.each do |row|
        index = tickets.index { |existing| existing["id"].to_i == row["id"].to_i }
        if index
          tickets[index] = row
        else
          tickets << row
        end
      end
      save!(tickets)
      entry
    end

    def import_json(path)
      tickets = load_data
      result = TicketImporter.new(tickets, next_id: method(:next_id)).import_json(path)
      save!(tickets)
      result
    end

    private

    def default_path
      File.expand_path("../../data/tickets.json", __dir__)
    end

    def validate_ticket!(ticket)
      errors = ticket.validation_errors
      return if errors.empty?

      raise ArgumentError, errors.join("; ")
    end

  end
end
