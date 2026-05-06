module Helpdesk
  class TicketPresenter
    def self.row(ticket)
      overdue_marker = ticket.overdue? ? " overdue" : ""
      sla_marker = case ticket.sla_status
                   when "warning" then " sla_warning"
                   when "breached" then " sla_breached"
                   else ""
                   end
      escalation_marker = ticket.escalation_needed? ? " escalate" : ""
      pinned_marker = ticket.pinned? ? " pinned" : ""
      archived_marker = ticket.archived? ? " archived" : ""
      deleted_marker = ticket.deleted? ? " deleted" : ""
      merged_marker = ticket.merged? ? " merged" : ""
      merged_from_marker = ticket.merged_from_ids.empty? ? "" : " merged_from:#{ticket.merged_from_ids.join(',')}"
      tags = ticket.tags.empty? ? "" : " ##{ticket.tags.join(' #')}"

      "##{ticket.id} [#{ticket.ticket_type}/#{ticket.status}/#{ticket.priority}#{overdue_marker}#{sla_marker}#{escalation_marker}#{pinned_marker}#{archived_marker}#{deleted_marker}#{merged_marker}#{merged_from_marker}] #{ticket.title}#{tags}"
    end

    def self.sla_status(ticket)
      case ticket.sla_status
      when "breached"
        rule = ticket.sla_rule
        age = ticket.sla_age_days
        "breached (age #{age} days, threshold #{rule[:breach_days]} days)"
      when "warning"
        rule = ticket.sla_rule
        age = ticket.sla_age_days
        "warning (age #{age} days, threshold #{rule[:warning_days]} days)"
      when "ok"
        rule = ticket.sla_rule
        age = ticket.sla_age_days
        "ok (age #{age} days, threshold #{rule[:warning_days]} days)"
      else
        "none"
      end
    end

    def self.escalation_status(ticket)
      rule = ticket.escalation_rule
      return "none" unless rule
      return "disabled" unless rule[:enabled]
      return "needed (trigger #{rule[:trigger]}, target #{rule[:target_role]})" if ticket.escalation_needed?

      "none"
    end

    def self.filter_options(options)
      options = options || {}
      parts = []
      parts << "--status #{option_value(options, :status)}" if option_value(options, :status)
      parts << "--priority #{option_value(options, :priority)}" if option_value(options, :priority)
      parts << "--tag #{option_value(options, :tag)}" if option_value(options, :tag)
      parts << "--sort #{option_value(options, :sort)}" if option_value(options, :sort)
      parts << "--overdue" if truthy_option?(options, :overdue)
      parts << "--archived" if truthy_option?(options, :archived)
      parts << "--active" if truthy_option?(options, :active)
      parts << "--deleted" if truthy_option?(options, :deleted)
      parts.empty? ? "none" : parts.join(" ")
    end

    def self.option_value(options, key)
      options[key] || options[key.to_s]
    end
    private_class_method :option_value

    def self.truthy_option?(options, key)
      value = option_value(options, key)
      value == true || %w[true yes on 1].include?(value.to_s.strip.downcase)
    end
    private_class_method :truthy_option?
  end
end
