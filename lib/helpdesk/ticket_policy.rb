require "date"
require "time"

module Helpdesk
  class TicketPolicy
    STATUSES = %w[open in_progress waiting resolved closed].freeze
    PRIORITIES = %w[low medium high urgent].freeze
    TICKET_TYPES = %w[general bug feature incident].freeze
    DEFAULT_SLA_RULES = {
      "low" => { warning_days: 14, breach_days: 21 },
      "medium" => { warning_days: 7, breach_days: 10 },
      "high" => { warning_days: 3, breach_days: 5 },
      "urgent" => { warning_days: 1, breach_days: 2 }
    }.freeze
    DEFAULT_ESCALATION_RULES = {
      "low" => { enabled: false, trigger: "sla_breached", target_role: "admin" },
      "medium" => { enabled: true, trigger: "sla_breached", target_role: "admin" },
      "high" => { enabled: true, trigger: "sla_warning", target_role: "admin" },
      "urgent" => { enabled: true, trigger: "overdue", target_role: "admin" }
    }.freeze
    DEFAULT_WORKFLOWS = {
      "general" => { name: "General", statuses: STATUSES, initial_status: "open" },
      "bug" => { name: "Bug", statuses: STATUSES, initial_status: "open" },
      "feature" => { name: "Feature", statuses: STATUSES, initial_status: "open" },
      "incident" => { name: "Incident", statuses: STATUSES, initial_status: "open" }
    }.freeze
    DEFAULT_TRANSITION_ROLES = %w[admin agent].freeze

    attr_reader :sla_rules, :escalation_rules, :workflows

    def initialize(sla_rules: DEFAULT_SLA_RULES, escalation_rules: DEFAULT_ESCALATION_RULES, workflows: DEFAULT_WORKFLOWS)
      self.sla_rules = sla_rules
      self.escalation_rules = escalation_rules
      self.workflows = workflows
    end

    def sla_rules=(rules)
      @sla_rules = normalize_sla_rules(rules)
    end

    def escalation_rules=(rules)
      @escalation_rules = normalize_escalation_rules(rules)
    end

    def workflows=(workflows)
      @workflows = normalize_workflows(workflows)
    end

    def sla_rule_for(priority)
      sla_rules[priority.to_s]
    end

    def escalation_rule_for(priority)
      escalation_rules[priority.to_s]
    end

    def workflow_for(ticket_type)
      workflows[ticket_type.to_s] || workflows["general"]
    end

    def workflow_statuses_for(ticket_type)
      Array(workflow_for(ticket_type)["statuses"])
    end

    def initial_status_for(ticket_type)
      workflow_for(ticket_type)["initial_status"].to_s
    end

    def workflow_transitions_for(ticket_type)
      workflow_for(ticket_type)["transitions"] || {}
    end

    def workflow_next_statuses_for(ticket_type, status)
      Array(workflow_transitions_for(ticket_type)[status.to_s])
    end

    def workflow_transition_permissions_for(ticket_type)
      workflow_for(ticket_type)["permissions"] || {}
    end

    def workflow_transition_roles_for(ticket_type, from_status, to_status)
      workflow_transition_permissions_for(ticket_type)
        .fetch(from_status.to_s, {})
        .fetch(to_status.to_s, DEFAULT_TRANSITION_ROLES)
    end

    def workflow_transition_allowed?(ticket_type, from_status, to_status, role)
      role = role.to_s.strip
      return true if role.empty?

      workflow_transition_roles_for(ticket_type, from_status, to_status).include?(role)
    end

    def normalize_ticket_type(value)
      value = value.to_s.strip.downcase
      value = "general" if value.empty?
      return value if TICKET_TYPES.include?(value)

      raise ArgumentError, "invalid ticket type: #{value}"
    end

    def normalize_status(value, ticket_type:)
      value = value.to_s.strip
      allowed = workflow_statuses_for(ticket_type)
      initial = initial_status_for(ticket_type)
      return initial if value.empty? && !initial.empty?
      return value if allowed.include?(value)

      normalized = value.tr(" ", "_")
      return normalized if allowed.include?(normalized)

      raise ArgumentError, "invalid status: #{value}"
    end

    def normalize_priority(value)
      value = value.to_s.strip
      return "medium" if value.empty?
      return value if PRIORITIES.include?(value)

      raise ArgumentError, "invalid priority: #{value}"
    end

    def normalize_due_at(value)
      value = value.to_s.strip
      return nil if value.empty?

      Date.parse(value).iso8601
    rescue ArgumentError
      raise ArgumentError, "invalid due date: #{value}"
    end

    def normalize_reminder_at(value)
      value = value.to_s.strip
      return nil if value.empty?

      Time.parse(value).utc.iso8601
    rescue ArgumentError
      raise ArgumentError, "invalid reminder time: #{value}"
    end

    def normalize_reminder_repeat(value)
      value = value.to_s.strip
      return nil if value.empty?
      return value if %w[daily weekly monthly].include?(value)

      raise ArgumentError, "invalid reminder repeat: #{value}"
    end

    def validation_errors(ticket)
      errors = []
      case ticket.ticket_type
      when "bug"
        errors << "bug tickets require a severity field" if ticket.custom_fields["severity"].to_s.strip.empty?
      when "feature"
        errors << "feature tickets require a requested_by field" if ticket.custom_fields["requested_by"].to_s.strip.empty?
      when "incident"
        errors << "incident tickets require an impact field" if ticket.custom_fields["impact"].to_s.strip.empty?
      end
      errors
    end

    def due_date(ticket)
      return nil if ticket.due_at.to_s.strip.empty?

      Date.parse(ticket.due_at)
    rescue ArgumentError
      nil
    end

    def overdue?(ticket, reference_date: Date.today)
      return false if terminal_for_time_policy?(ticket)

      date = due_date(ticket)
      date && date < reference_date
    end

    def sla_status(ticket, reference_time = Time.now.utc)
      return "none" if terminal_for_sla_policy?(ticket)

      age_days = sla_age_days(ticket, reference_time)
      return "none" unless age_days

      rule = sla_rule(ticket)
      return "none" unless rule
      return "breached" if age_days >= rule[:breach_days]
      return "warning" if age_days >= rule[:warning_days]

      "ok"
    end

    def sla_warning?(ticket)
      %w[warning breached].include?(sla_status(ticket))
    end

    def sla_breached?(ticket)
      sla_status(ticket) == "breached"
    end

    def sla_age_days(ticket, reference_time = Time.now.utc)
      ((reference_time - Time.parse(ticket.created_at)) / 86_400).floor
    rescue ArgumentError, TypeError
      nil
    end

    def sla_rule(ticket)
      sla_rule_for(ticket.priority)
    end

    def escalation_rule(ticket)
      escalation_rule_for(ticket.priority)
    end

    def escalation_status(ticket, reference_time = Time.now.utc)
      return "none" if terminal_for_sla_policy?(ticket)

      rule = escalation_rule(ticket)
      return "none" unless rule && rule[:enabled]
      return "needed" if escalation_triggered?(ticket, rule, reference_time)

      "none"
    end

    def escalation_needed?(ticket)
      escalation_status(ticket) == "needed"
    end

    def escalation_target_role(ticket)
      rule = escalation_rule(ticket)
      rule ? rule[:target_role] : nil
    end

    def escalation_trigger(ticket)
      rule = escalation_rule(ticket)
      rule ? rule[:trigger] : nil
    end

    def can_transition?(ticket, to_status, role: nil)
      workflow_transition_allowed?(ticket.ticket_type, ticket.status, to_status, role)
    end

    def escalation_triggered?(ticket, rule = escalation_rule(ticket), _reference_time = Time.now.utc)
      return false unless rule

      case rule[:trigger]
      when "sla_warning"
        sla_warning?(ticket)
      when "sla_breached"
        sla_breached?(ticket)
      when "overdue"
        overdue?(ticket)
      else
        false
      end
    end

    def reminder_due?(ticket, reference_time = Time.now.utc)
      return false if ticket.closed?
      return false if ticket.reminder_at.to_s.strip.empty?

      Time.parse(ticket.reminder_at) <= reference_time
    rescue ArgumentError
      false
    end

    def recurring_reminder?(ticket)
      !ticket.reminder_repeat.to_s.strip.empty?
    end

    def advance_reminder!(ticket)
      return ticket unless recurring_reminder?(ticket)

      next_time =
        case ticket.reminder_repeat
        when "daily"
          Time.parse(ticket.reminder_at) + 86_400
        when "weekly"
          Time.parse(ticket.reminder_at) + 604_800
        when "monthly"
          Time.parse(ticket.reminder_at) + 2_592_000
        end
      ticket.reminder_at = next_time&.utc&.iso8601
      ticket.updated_at = Time.now.utc.iso8601
      ticket
    rescue ArgumentError
      ticket.reminder_at = nil
      ticket
    end

    def duplicate_key(ticket)
      [duplicate_title_key(ticket), normalized_duplicate_description(ticket)].join("|")
    end

    def duplicate_title_key(ticket)
      normalized_duplicate_title(ticket)
    end

    private

    def terminal_for_time_policy?(ticket)
      ticket.closed? || ticket.status == "resolved"
    end

    def terminal_for_sla_policy?(ticket)
      terminal_for_time_policy?(ticket) || ticket.archived?
    end

    def normalize_sla_rules(rules)
      source = rules.is_a?(Hash) ? rules : {}
      PRIORITIES.each_with_object({}) do |priority, normalized|
        rule = source[priority] || source[priority.to_sym] || DEFAULT_SLA_RULES[priority]
        normalized[priority] = {
          warning_days: rule.fetch("warning_days", rule.fetch(:warning_days, DEFAULT_SLA_RULES[priority][:warning_days])).to_i,
          breach_days: rule.fetch("breach_days", rule.fetch(:breach_days, DEFAULT_SLA_RULES[priority][:breach_days])).to_i
        }
      end
    end

    def normalize_escalation_rules(rules)
      source = rules.is_a?(Hash) ? rules : {}
      PRIORITIES.each_with_object({}) do |priority, normalized|
        rule = source[priority] || source[priority.to_sym] || DEFAULT_ESCALATION_RULES[priority]
        normalized[priority] = {
          enabled: normalize_boolean(rule.fetch("enabled", rule.fetch(:enabled, DEFAULT_ESCALATION_RULES[priority][:enabled]))),
          trigger: normalize_escalation_trigger(rule.fetch("trigger", rule.fetch(:trigger, DEFAULT_ESCALATION_RULES[priority][:trigger]))),
          target_role: normalize_escalation_target_role(rule.fetch("target_role", rule.fetch(:target_role, DEFAULT_ESCALATION_RULES[priority][:target_role])))
        }
      end
    end

    def normalize_boolean(value)
      case value
      when true, false
        value
      else
        %w[true yes on 1].include?(value.to_s.strip.downcase)
      end
    end

    def normalize_escalation_trigger(value)
      value = value.to_s.strip.downcase
      value = "sla_breached" if value.empty?
      return value if %w[sla_warning sla_breached overdue].include?(value)

      raise ArgumentError, "invalid escalation trigger: #{value}"
    end

    def normalize_escalation_target_role(value)
      value = value.to_s.strip.downcase
      value = "admin" if value.empty?
      return value if %w[admin agent viewer].include?(value)

      raise ArgumentError, "invalid escalation target role: #{value}"
    end

    def normalize_workflows(workflows)
      source = workflows.is_a?(Hash) ? workflows : {}
      source.each_with_object({}) do |(ticket_type, workflow), normalized|
        ticket_type = ticket_type.to_s.strip
        next if ticket_type.empty?

        workflow = workflow.is_a?(Hash) ? workflow : {}
        statuses = normalize_workflow_statuses(workflow["statuses"] || workflow[:statuses] || STATUSES)
        initial_status = normalize_workflow_status(
          workflow["initial_status"] || workflow[:initial_status] || statuses.first || "open"
        )
        raise ArgumentError, "workflow #{ticket_type} must define at least one status" if statuses.empty?
        raise ArgumentError, "workflow #{ticket_type} must include closed" unless statuses.include?("closed")
        raise ArgumentError, "workflow #{ticket_type} initial status must be in statuses" unless statuses.include?(initial_status)

        transitions = normalize_workflow_transitions(
          workflow["transitions"] || workflow[:transitions] || default_workflow_transitions(statuses),
          statuses: statuses,
          ticket_type: ticket_type
        )
        permissions = normalize_workflow_permissions(
          workflow["permissions"] || workflow[:permissions] || default_workflow_permissions(transitions),
          statuses: statuses,
          ticket_type: ticket_type
        )

        normalized[ticket_type] = {
          "name" => (workflow["name"] || workflow[:name] || ticket_type.tr("_", " ").capitalize).to_s,
          "statuses" => statuses,
          "initial_status" => initial_status,
          "transitions" => transitions,
          "permissions" => permissions
        }
      end
    end

    def normalize_workflow_statuses(statuses)
      Array(statuses).map { |status| normalize_workflow_status(status) }.reject(&:empty?).uniq
    end

    def normalize_workflow_transitions(transitions, statuses:, ticket_type:)
      source = transitions.is_a?(Hash) ? transitions : {}
      source.each_with_object({}) do |(from_status, next_statuses), normalized|
        from_status = normalize_workflow_status(from_status)
        next if from_status.empty?

        normalized[from_status] = normalize_workflow_next_statuses(next_statuses, allowed_statuses: statuses, ticket_type: ticket_type)
      end
    end

    def normalize_workflow_next_statuses(next_statuses, allowed_statuses:, ticket_type:)
      normalized = Array(next_statuses).map { |status| normalize_workflow_status(status) }.reject(&:empty?).uniq
      invalid = normalized - allowed_statuses
      raise ArgumentError, "workflow #{ticket_type} has invalid transition targets: #{invalid.join(', ')}" if invalid.any?

      normalized
    end

    def default_workflow_transitions(statuses)
      statuses.each_cons(2).each_with_object({}) do |(from_status, to_status), normalized|
        normalized[from_status] ||= []
        normalized[from_status] << to_status
      end
    end

    def default_workflow_permissions(transitions)
      transitions.each_with_object({}) do |(from_status, next_statuses), normalized|
        normalized[from_status] = Array(next_statuses).each_with_object({}) do |to_status, per_from|
          per_from[to_status] = DEFAULT_TRANSITION_ROLES.dup
        end
      end
    end

    def normalize_workflow_permissions(permissions, statuses:, ticket_type:)
      source = permissions.is_a?(Hash) ? permissions : {}
      source.each_with_object({}) do |(from_status, next_statuses), normalized|
        from_status = normalize_workflow_status(from_status)
        next if from_status.empty?
        raise ArgumentError, "workflow #{ticket_type} has invalid permission source: #{from_status}" unless statuses.include?(from_status)

        normalized[from_status] = {}
        Hash(next_statuses).each do |to_status, roles|
          to_status = normalize_workflow_status(to_status)
          next if to_status.empty?
          raise ArgumentError, "workflow #{ticket_type} has invalid permission target: #{to_status}" unless statuses.include?(to_status)

          normalized_roles = Array(roles).map { |role| role.to_s.strip.downcase }.reject(&:empty?).uniq
          normalized_roles = DEFAULT_TRANSITION_ROLES.dup if normalized_roles.empty?
          invalid_roles = normalized_roles - %w[admin agent viewer]
          raise ArgumentError, "workflow #{ticket_type} has invalid permission roles: #{invalid_roles.join(', ')}" if invalid_roles.any?

          normalized[from_status][to_status] = normalized_roles
        end
      end
    end

    def normalize_workflow_status(status)
      value = status.to_s.strip
      return "" if value.empty?
      return value if value.match?(/\A[a-zA-Z0-9_]+\z/)

      value.tr(" ", "_")
    end

    def normalized_duplicate_title(ticket)
      ticket.title.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip.squeeze(" ")
    end

    def normalized_duplicate_description(ticket)
      ticket.description.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip.squeeze(" ")
    end
  end
end
