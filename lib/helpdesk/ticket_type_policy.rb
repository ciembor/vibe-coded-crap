module Helpdesk
  class TicketTypePolicy
    TYPES = %w[general bug feature incident].freeze
    REQUIRED_FIELDS = {
      "bug" => { "severity" => "bug tickets require a severity field" },
      "feature" => { "requested_by" => "feature tickets require a requested_by field" },
      "incident" => { "impact" => "incident tickets require an impact field" }
    }.freeze

    def self.normalize(value)
      value = value.to_s.strip.downcase
      value = "general" if value.empty?
      return value if TYPES.include?(value)

      raise ArgumentError, "invalid ticket type: #{value}"
    end

    def self.validation_errors(ticket_type, custom_fields)
      requirements = REQUIRED_FIELDS.fetch(ticket_type.to_s, {})
      requirements.each_with_object([]) do |(field, message), errors|
        errors << message if custom_fields[field].to_s.strip.empty?
      end
    end
  end
end
