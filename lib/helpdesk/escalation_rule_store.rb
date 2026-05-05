require "helpdesk/ticket"
require "helpdesk/json_file_store"

module Helpdesk
  class EscalationRuleStore < JsonFileStore

    def default_payload
      default_rules
    end

    def all
      normalize_rules(load_data)
    end

    def set(priority, enabled:, trigger:, target_role:)
      priority = priority.to_s.strip.downcase
      raise ArgumentError, "invalid priority: #{priority}" unless Ticket::PRIORITIES.include?(priority)

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
      normalized_priority = priority.to_s.strip.downcase
      if normalized_priority.empty? || normalized_priority == "all"
        rules = default_rules
      else
        raise ArgumentError, "invalid priority: #{normalized_priority}" unless Ticket::PRIORITIES.include?(normalized_priority)

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

    def normalize_boolean(value)
      case value
      when true, false
        value
      else
        %w[true yes on 1].include?(value.to_s.strip.downcase)
      end
    end

    def normalize_trigger(value)
      value = value.to_s.strip.downcase
      value = "sla_breached" if value.empty?
      return value if %w[sla_warning sla_breached overdue].include?(value)

      raise ArgumentError, "invalid escalation trigger: #{value}"
    end

    def normalize_target_role(value)
      value = value.to_s.strip.downcase
      value = "admin" if value.empty?
      return value if %w[admin agent viewer].include?(value)

      raise ArgumentError, "invalid escalation target role: #{value}"
    end
  end
end
