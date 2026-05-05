require "time"

module Helpdesk
  class TicketSlaPolicy
    def initialize(ticket)
      @ticket = ticket
    end

    def status(reference_time = Time.now.utc)
      return "none" if inactive?

      days = age_days(reference_time)
      return "none" unless days

      current_rule = rule
      return "none" unless current_rule

      return "breached" if days >= current_rule[:breach_days]
      return "warning" if days >= current_rule[:warning_days]

      "ok"
    end

    def warning?
      %w[warning breached].include?(status)
    end

    def breached?
      status == "breached"
    end

    def age_days(reference_time = Time.now.utc)
      ((reference_time - Time.parse(@ticket.created_at)) / 86_400).floor
    rescue ArgumentError, TypeError
      nil
    end

    def rule
      @ticket.class.sla_rule_for(@ticket.priority)
    end

    private

    def inactive?
      @ticket.closed? || @ticket.status == "resolved" || @ticket.archived?
    end
  end
end
