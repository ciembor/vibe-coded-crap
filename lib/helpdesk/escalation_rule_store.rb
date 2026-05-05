require "helpdesk/ticket"
require "helpdesk/json_file_store"
require "helpdesk/domain_normalization"

module Helpdesk
  class EscalationRuleStore < JsonFileStore

    def all
      normalize_rules(load_data)
    end

    def set(priority, enabled:, trigger:, target_role:)
      priority = normalize_priority(priority)

      enabled = normalize_boolean(enabled)
      trigger = normalize_trigger(trigger)
      target_role = normalize_target_role(target_role)

      rules = all
      rules[priority] = {
        "enabled" => enabled,
        "trigger" => trigger,
        "target_role" => target_role
      }
      save!(rules)
      rules
    end

    def reset(priority = nil)
      rules = all
      normalized_priority = DomainNormalization.present_string(priority, downcase: true)
      if normalized_priority.empty? || normalized_priority == "all"
        rules = default_rules
      else
        normalize_priority(normalized_priority)

        rules[normalized_priority] = default_rules.fetch(normalized_priority)
      end

      save!(rules)
      rules
    end

    def reload_ticket_rules!
      Ticket.escalation_rules = all
    end

    private

    def default_path
      File.expand_path("../../data/escalation_rules.json", __dir__)
    end

    def default_rules
      Ticket::DEFAULT_ESCALATION_RULES.transform_values do |rule|
        {
          "enabled" => rule[:enabled],
          "trigger" => rule[:trigger],
          "target_role" => rule[:target_role]
        }
      end
    end

    def default_payload
      default_rules
    end

    def normalize_rules(rules)
      source = rules.is_a?(Hash) ? rules : {}
      Ticket::PRIORITIES.each_with_object({}) do |priority, normalized|
        rule = source[priority] || source[priority.to_sym] || default_rules[priority]
        normalized[priority] = {
          "enabled" => normalize_boolean(rule.fetch("enabled", rule.fetch(:enabled, default_rules[priority]["enabled"]))),
          "trigger" => normalize_trigger(rule.fetch("trigger", rule.fetch(:trigger, default_rules[priority]["trigger"]))),
          "target_role" => normalize_target_role(rule.fetch("target_role", rule.fetch(:target_role, default_rules[priority]["target_role"])))
        }
      end
    end

    def save!(rules)
      super(normalize_rules(rules))
    end

    def normalize_boolean(value)
      DomainNormalization.boolean(value)
    end

    def normalize_trigger(value)
      DomainNormalization.enum(
        value,
        allowed: %w[sla_warning sla_breached overdue],
        default: "sla_breached",
        label: "escalation trigger",
        downcase: true
      )
    end

    def normalize_target_role(value)
      DomainNormalization.enum(
        value,
        allowed: %w[admin agent viewer],
        default: "admin",
        label: "escalation target role",
        downcase: true
      )
    end

    def normalize_priority(value)
      priority = DomainNormalization.present_string(value, downcase: true)
      return priority if Ticket::PRIORITIES.include?(priority)

      raise ArgumentError, "invalid priority: #{priority}"
    end
  end
end
