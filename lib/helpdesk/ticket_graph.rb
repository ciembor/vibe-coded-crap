require "helpdesk/ticket"

module Helpdesk
  class TicketGraph
    SELF_RELATIONSHIP_ERRORS = {
      "relate" => "cannot relate a ticket to itself",
      "unrelate" => "cannot unrelate a ticket from itself",
      "set_parent" => "cannot set a ticket as its own parent",
      "add_dependency" => "cannot add a dependency to itself",
      "remove_dependency" => "cannot remove a dependency from itself"
    }.freeze

    def initialize(rows)
      @rows = rows
    end

    def relate(source_id, target_id)
      source_id, target_id = validate_pair!(source_id, target_id, action: "relate")
      source_index, target_index = indexes_for(source_id, target_id)
      return nil unless source_index && target_index

      source = ticket_at(source_index)
      target = ticket_at(target_index)
      source.relate_to(target.id)
      target.relate_to(source.id)
      replace(source_index, source)
      replace(target_index, target)
      { source: source, target: target }
    end

    def unrelate(source_id, target_id)
      source_id, target_id = validate_pair!(source_id, target_id, action: "unrelate")
      source_index, target_index = indexes_for(source_id, target_id)
      return nil unless source_index && target_index

      source = ticket_at(source_index)
      target = ticket_at(target_index)
      source.unrelate(target.id)
      target.unrelate(source.id)
      replace(source_index, source)
      replace(target_index, target)
      { source: source, target: target }
    end

    def set_parent(child_id, parent_id)
      child_id, parent_id = validate_pair!(child_id, parent_id, action: "set_parent")
      child_index, parent_index = indexes_for(child_id, parent_id)
      return nil unless child_index && parent_index

      child = ticket_at(child_index)
      parent = ticket_at(parent_index)
      old_parent_index = child.parent_id ? index_for(child.parent_id) : nil
      child.set_parent(parent.id)
      parent.add_child(child.id)
      replace(child_index, child)
      replace(parent_index, parent)
      remove_child_from_old_parent(old_parent_index, child.id, parent.id)
      { child: child, parent: parent }
    end

    def clear_parent(child_id)
      child_id = child_id.to_i
      raise ArgumentError, "clear_parent requires a ticket ID" if child_id.zero?

      child_index = index_for(child_id)
      return nil unless child_index

      child = ticket_at(child_index)
      parent_index = child.parent_id ? index_for(child.parent_id) : nil
      parent = parent_index ? ticket_at(parent_index) : nil
      child.clear_parent
      replace(child_index, child)
      if parent
        parent.remove_child(child.id)
        replace(parent_index, parent)
      end
      { child: child, parent: parent }
    end

    def add_dependency(ticket_id, dependency_id)
      ticket_id, dependency_id = validate_pair!(ticket_id, dependency_id, action: "add_dependency")
      ticket_index, dependency_index = indexes_for(ticket_id, dependency_id)
      return nil unless ticket_index && dependency_index

      ticket = ticket_at(ticket_index)
      dependency = ticket_at(dependency_index)
      ticket.add_dependency(dependency.id)
      replace(ticket_index, ticket)
      { ticket: ticket, dependency: dependency }
    end

    def remove_dependency(ticket_id, dependency_id)
      ticket_id, dependency_id = validate_pair!(ticket_id, dependency_id, action: "remove_dependency")
      ticket_index, dependency_index = indexes_for(ticket_id, dependency_id)
      return nil unless ticket_index && dependency_index

      ticket = ticket_at(ticket_index)
      dependency = ticket_at(dependency_index)
      ticket.remove_dependency(dependency.id)
      replace(ticket_index, ticket)
      { ticket: ticket, dependency: dependency }
    end

    def self.related_tickets(ticket, tickets)
      tickets.select { |existing| ticket.related_ids.include?(existing.id.to_i) }
    end

    def self.parent_ticket(ticket, tickets)
      return nil if ticket.parent_id.nil?

      tickets.find { |existing| existing.id.to_i == ticket.parent_id.to_i }
    end

    def self.child_tickets(ticket, tickets)
      tickets.select { |existing| ticket.child_ids.include?(existing.id.to_i) }
    end

    def self.dependencies_for(ticket, tickets)
      tickets.select { |existing| ticket.dependency_ids.include?(existing.id.to_i) }
    end

    def self.dependent_tickets(ticket, tickets)
      tickets.select { |existing| existing.dependency_ids.include?(ticket.id.to_i) }
    end

    def self.open_dependencies_for(ticket, tickets)
      dependencies_for(ticket, tickets).reject(&:closed?)
    end

    def self.closeable?(ticket, tickets)
      open_dependencies_for(ticket, tickets).empty?
    end

    private

    def validate_pair!(left_id, right_id, action:)
      left_id = left_id.to_i
      right_id = right_id.to_i
      raise ArgumentError, "#{action} requires two ticket IDs" if left_id.zero? || right_id.zero?
      raise ArgumentError, SELF_RELATIONSHIP_ERRORS.fetch(action) if left_id == right_id

      [left_id, right_id]
    end

    def indexes_for(left_id, right_id)
      [index_for(left_id), index_for(right_id)]
    end

    def index_for(id)
      @rows.index { |row| row["id"].to_i == id.to_i }
    end

    def ticket_at(index)
      Ticket.from_h(@rows[index])
    end

    def replace(index, ticket)
      @rows[index] = ticket.to_h
    end

    def remove_child_from_old_parent(old_parent_index, child_id, new_parent_id)
      return unless old_parent_index

      old_parent = ticket_at(old_parent_index)
      return if old_parent.id.to_i == new_parent_id.to_i

      old_parent.remove_child(child_id)
      replace(old_parent_index, old_parent)
    end
  end
end
