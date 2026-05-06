module Helpdesk
  class TicketRelationships
    def initialize(repository)
      @repository = repository
    end

    def related_tickets(ticket)
      @repository.all.select { |existing| ticket.related_ids.include?(existing.id.to_i) }
    end

    def parent_ticket(ticket)
      return nil if ticket.parent_id.nil?

      @repository.find(ticket.parent_id)
    end

    def child_tickets(ticket)
      @repository.all.select { |existing| ticket.child_ids.include?(existing.id.to_i) }
    end

    def dependencies_for(ticket)
      @repository.all.select { |existing| ticket.dependency_ids.include?(existing.id.to_i) }
    end

    def dependent_tickets(ticket)
      @repository.all.select { |existing| existing.dependency_ids.include?(ticket.id.to_i) }
    end

    def open_dependencies_for(ticket, tickets: nil)
      dependencies = tickets ? dependencies_for_in(ticket, tickets) : dependencies_for(ticket)
      dependencies.reject(&:closed?)
    end

    def closeable_ticket?(ticket, tickets: nil)
      open_dependencies_for(ticket, tickets: tickets).empty?
    end

    def ensure_closing_allowed!(ticket, attrs, actor_role:, tickets: nil)
      return unless attrs.key?(:status)

      target_type = attrs.fetch(:ticket_type, ticket.ticket_type)
      target_status = Ticket.policy.normalize_status(attrs[:status], ticket_type: target_type)
      unless ticket.can_transition_to?(target_status, role: actor_role)
        raise ArgumentError, "transition #{ticket.status} -> #{target_status} is not permitted for #{actor_role || 'system'}"
      end

      return unless target_status == "closed"

      open_dependencies = open_dependencies_for(ticket, tickets: tickets)
      return if open_dependencies.empty?

      ids = open_dependencies.map { |dependency| "##{dependency.id}" }.join(", ")
      raise ArgumentError, "cannot close ticket ##{ticket.id} with open dependencies: #{ids}"
    end

    def relate(source_id, target_id)
      source_id, target_id = validate_pair!(source_id, target_id, action: "relate", self_message: "cannot relate a ticket to itself")
      @repository.transaction do |tickets|
        source = tickets.find(source_id)
        target = tickets.find(target_id)
        next nil unless source && target

        source.update(related_ids: source.related_ids + [target.id])
        target.update(related_ids: target.related_ids + [source.id])
        { source: source, target: target }
      end
    end

    def unrelate(source_id, target_id)
      source_id, target_id = validate_pair!(source_id, target_id, action: "unrelate", self_message: "cannot unrelate a ticket from itself")
      @repository.transaction do |tickets|
        source = tickets.find(source_id)
        target = tickets.find(target_id)
        next nil unless source && target

        source.update(related_ids: source.related_ids.reject { |id| id.to_i == target.id.to_i })
        target.update(related_ids: target.related_ids.reject { |id| id.to_i == source.id.to_i })
        { source: source, target: target }
      end
    end

    def set_parent(child_id, parent_id)
      child_id, parent_id = validate_pair!(child_id, parent_id, action: "set_parent", self_message: "cannot set a ticket as its own parent")
      @repository.transaction do |tickets|
        child = tickets.find(child_id)
        parent = tickets.find(parent_id)
        next nil unless child && parent

        old_parent = child.parent_id ? tickets.find(child.parent_id) : nil
        child.update(parent_id: parent.id)
        parent.update(child_ids: parent.child_ids + [child.id])
        old_parent.update(child_ids: old_parent.child_ids.reject { |id| id.to_i == child.id.to_i }) if old_parent && old_parent.id.to_i != parent.id.to_i
        { child: child, parent: parent }
      end
    end

    def clear_parent(child_id)
      child_id = child_id.to_i
      raise ArgumentError, "clear_parent requires a ticket ID" if child_id.zero?

      @repository.transaction do |tickets|
        child = tickets.find(child_id)
        next nil unless child

        parent = child.parent_id ? tickets.find(child.parent_id) : nil
        child.update(parent_id: nil)
        parent.update(child_ids: parent.child_ids.reject { |id| id.to_i == child.id.to_i }) if parent
        { child: child, parent: parent }
      end
    end

    def add_dependency(ticket_id, dependency_id)
      ticket_id, dependency_id = validate_pair!(ticket_id, dependency_id, action: "add_dependency", self_message: "cannot add a dependency to itself")
      @repository.transaction do |tickets|
        ticket = tickets.find(ticket_id)
        dependency = tickets.find(dependency_id)
        next nil unless ticket && dependency

        ticket.update(dependency_ids: ticket.dependency_ids + [dependency.id])
        { ticket: ticket, dependency: dependency }
      end
    end

    def remove_dependency(ticket_id, dependency_id)
      ticket_id, dependency_id = validate_pair!(ticket_id, dependency_id, action: "remove_dependency", self_message: "cannot remove a dependency from itself")
      @repository.transaction do |tickets|
        ticket = tickets.find(ticket_id)
        dependency = tickets.find(dependency_id)
        next nil unless ticket && dependency

        ticket.update(dependency_ids: ticket.dependency_ids.reject { |id| id.to_i == dependency.id.to_i })
        { ticket: ticket, dependency: dependency }
      end
    end

    private

    def dependencies_for_in(ticket, tickets)
      tickets.select { |existing| ticket.dependency_ids.include?(existing.id.to_i) }
    end

    def validate_pair!(left_id, right_id, action:, self_message:)
      left_id = left_id.to_i
      right_id = right_id.to_i
      raise ArgumentError, "#{action} requires two ticket IDs" if left_id.zero? || right_id.zero?
      raise ArgumentError, self_message if left_id == right_id

      [left_id, right_id]
    end
  end
end
