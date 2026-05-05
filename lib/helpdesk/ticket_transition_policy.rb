module Helpdesk
  class TicketTransitionPolicy
    def initialize(ticket)
      @ticket = ticket
    end

    def allowed?(to_status, role:)
      @ticket.class.workflow_transition_allowed?(@ticket.ticket_type, @ticket.status, to_status, role)
    end

    def normalize_status(value, ticket_type: @ticket.ticket_type)
      value = value.to_s.strip
      allowed = @ticket.class.workflow_statuses_for(ticket_type)
      initial = @ticket.class.initial_status_for(ticket_type)
      return initial if value.empty? && !initial.empty?
      return value if allowed.include?(value)

      normalized = value.tr(" ", "_")
      return normalized if allowed.include?(normalized)

      raise ArgumentError, "invalid status: #{value}"
    end
  end
end
