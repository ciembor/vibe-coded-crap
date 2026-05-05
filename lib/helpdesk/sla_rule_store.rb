require "helpdesk/json_file"
require "helpdesk/ticket"

module Helpdesk
  class SlaRuleStore
    include JsonFileStore

    def initialize(path: default_path)
      configure_json_file(path, default: default_rules)
    end

    def all
      normalize_rules(load_data)
    end

    def set(priority, warning_days:, breach_days:)
      priority = priority.to_s.strip.downcase
      raise ArgumentError, "invalid priority: #{priority}" unless Ticket::PRIORITIES.include?(priority)

      warning_days = warning_days.to_i
      breach_days = breach_days.to_i
      raise ArgumentError, "warning days must be positive" if warning_days <= 0
      raise ArgumentError, "breach days must be greater than warning days" if breach_days <= warning_days

      rules = all
      rules[priority] = {
        "warning_days" => warning_days,
        "breach_days" => breach_days
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
        priority = normalized_priority
        raise ArgumentError, "invalid priority: #{priority}" unless Ticket::PRIORITIES.include?(priority)

        rules[priority] = default_rules.fetch(priority)
      end

      save!(rules)
      rules
    end

    def reload_ticket_rules!
      Ticket.sla_rules = all
    end

    private

    def default_path
      File.expand_path("../../data/sla_rules.json", __dir__)
    end

    def default_rules
      Ticket::DEFAULT_SLA_RULES.transform_values do |rule|
        {
          "warning_days" => rule[:warning_days],
          "breach_days" => rule[:breach_days]
        }
      end
    end

    def normalize_rules(rules)
      source = rules.is_a?(Hash) ? rules : {}
      Ticket::PRIORITIES.each_with_object({}) do |priority, normalized|
        rule = source[priority] || source[priority.to_sym] || default_rules[priority]
        normalized[priority] = {
          "warning_days" => rule.fetch("warning_days", rule.fetch(:warning_days, default_rules[priority]["warning_days"])).to_i,
          "breach_days" => rule.fetch("breach_days", rule.fetch(:breach_days, default_rules[priority]["breach_days"])).to_i
        }
      end
    end

    def save!(rules)
      @json_file.write(normalize_rules(rules))
    end
  end
end
