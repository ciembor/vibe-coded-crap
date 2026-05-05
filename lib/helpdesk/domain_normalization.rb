module Helpdesk
  module DomainNormalization
    TRUE_VALUES = %w[true yes on 1].freeze

    module_function

    def present_string(value, downcase: false)
      normalized = value.to_s.strip
      downcase ? normalized.downcase : normalized
    end

    def boolean(value, default: false)
      case value
      when true, false
        value
      when nil
        default
      else
        TRUE_VALUES.include?(value.to_s.strip.downcase)
      end
    end

    def enum(value, allowed:, default:, label:, strict: true, downcase: false)
      normalized = present_string(value, downcase: downcase)
      normalized = default if normalized.empty?
      return normalized if allowed.include?(normalized)
      return default unless strict

      raise ArgumentError, "invalid #{label}: #{normalized}"
    end

    def tags(value)
      Array(value).map { |tag| tag.to_s.strip }.reject(&:empty?).uniq.sort
    end

    def ids(value)
      Array(value).map(&:to_i).reject(&:zero?).uniq.sort
    end

    def optional_id(value)
      id = value.to_i
      id.zero? ? nil : id
    end

    def custom_fields(value)
      hash = value.is_a?(Hash) ? value : {}
      hash.each_with_object({}) do |(key, field_value), normalized|
        key = key.to_s.strip
        next if key.empty?

        normalized[key] = field_value.to_s
      end
    end

    def hash_value(hash, key, default = nil)
      return default unless hash.is_a?(Hash)

      value = hash[key.to_s]
      return value if value

      value = hash[key.to_sym]
      value || default
    end

    def normalized_strings(value, downcase: false, sort: false)
      strings = Array(value).map { |item| present_string(item, downcase: downcase) }.reject(&:empty?).uniq
      sort ? strings.sort : strings
    end
  end
end
