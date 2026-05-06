require "helpdesk/bulk_action_log"
require "helpdesk/ticket_bulk_actions"
require "helpdesk/ticket_merger"
require "helpdesk/ticket_relationships"
require "helpdesk/ticket_repository"

module Helpdesk
  class Store
    def initialize(path: default_path)
      @tickets = TicketRepository.new(path: path, validator: ->(ticket) { validate_ticket!(ticket) })
      @relationships = TicketRelationships.new(@tickets)
      @bulk_actions = TicketBulkActions.new(@tickets, @relationships, BulkActionLog.new)
      @merger = TicketMerger.new(@tickets)
    end

    def path
      @tickets.path
    end

    def all(include_deleted: false)
      @tickets.all(include_deleted: include_deleted)
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
      @relationships.related_tickets(ticket)
    end

    def parent_ticket(ticket)
      @relationships.parent_ticket(ticket)
    end

    def child_tickets(ticket)
      @relationships.child_tickets(ticket)
    end

    def dependencies_for(ticket)
      @relationships.dependencies_for(ticket)
    end

    def dependent_tickets(ticket)
      @relationships.dependent_tickets(ticket)
    end

    def open_dependencies_for(ticket)
      @relationships.open_dependencies_for(ticket)
    end

    def closeable_ticket?(ticket)
      @relationships.closeable_ticket?(ticket)
    end

    def relate(source_id, target_id)
      @relationships.relate(source_id, target_id)
    end

    def unrelate(source_id, target_id)
      @relationships.unrelate(source_id, target_id)
    end

    def set_parent(child_id, parent_id)
      @relationships.set_parent(child_id, parent_id)
    end

    def clear_parent(child_id)
      @relationships.clear_parent(child_id)
    end

    def add_dependency(ticket_id, dependency_id)
      @relationships.add_dependency(ticket_id, dependency_id)
    end

    def remove_dependency(ticket_id, dependency_id)
      @relationships.remove_dependency(ticket_id, dependency_id)
    end

    def find(id, include_deleted: false)
      @tickets.find(id, include_deleted: include_deleted)
    end

    def create(attrs)
      @tickets.create(attrs)
    end

    def update(id, attrs, actor_role: nil)
      @tickets.update(id, attrs) do |ticket, update_attrs, tickets|
        @relationships.ensure_closing_allowed!(ticket, update_attrs, actor_role: actor_role, tickets: tickets)
      end
    end

    def delete(id)
      @tickets.transaction do |tickets|
        ticket = tickets.find(id)
        next false unless ticket
        next false if ticket.deleted?

        ticket.delete!
        @tickets.validate!(ticket)
        true
      end
    end

    def restore(id)
      @tickets.transaction do |tickets|
        ticket = tickets.find(id)
        next false unless ticket
        next false unless ticket.deleted?

        ticket.restore_deleted!
        @tickets.validate!(ticket)
        true
      end
    end

    def bulk_close(ids, actor_role: nil)
      @bulk_actions.bulk_close(ids, actor_role: actor_role)
    end

    def bulk_tag(ids, tag, action:)
      @bulk_actions.bulk_tag(ids, tag, action: action)
    end

    def save_ticket(ticket)
      @tickets.save_ticket(ticket)
    end

    def merge(source_id, target_id)
      @merger.merge(source_id, target_id)
    end

    def undo_last_bulk_action
      @bulk_actions.undo_last_bulk_action
    end

    def import_json(path)
      @merger.import_json(path)
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
