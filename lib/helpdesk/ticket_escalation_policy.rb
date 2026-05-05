require "time"
require "helpdesk/ticket_sla_policy"

module Helpdesk
  class TicketEscalationPolicy
    def initialize(ticket)
      @ticket = ticket
    end

    def status(reference_time = Time.now.utc)
      return "none" if inactive?

      current_rule = rule
      return "none" unless current_rule && current_rule[:enabled]
      return "needed" if triggered?(current_rule, reference_time)

      "none"
    end

    def needed?
      status == "needed"
    end

    def target_role
      current_rule = rule
      current_rule ? current_rule[:target_role] : nil
    end

    def trigger
      current_rule = rule
      current_rule ? current_rule[:trigger] : nil
    end

    def rule
      @ticket.class.escalation_rule_for(@ticket.priority)
    end

    def triggered?(current_rule = rule, _reference_time = Time.now.utc)
      return false unless current_rule

      case current_rule[:trigger]
      when "sla_warning"
        TicketSlaPolicy.new(@ticket).warning?
      when "sla_breached"
        TicketSlaPolicy.new(@ticket).breached?
      when "overdue"
        @ticket.overdue?
      else
        false
      end
    end

    private

    def inactive?
      @ticket.closed? || @ticket.status == "resolved" || @ticket.archived?
    end
  end
end
