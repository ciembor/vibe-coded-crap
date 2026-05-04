require "json"
require "fileutils"
require "helpdesk/ticket"

module Helpdesk
  class SortRuleStore
    ALLOWED_FIELDS = %w[
      pinned
      archived
      overdue
      escalation
      sla
      priority
      status
      due_at
      updated_at
      created_at
      title
    ].freeze

    DEFAULT_RULE = %w[pinned archived overdue escalation sla priority due_at updated_at created_at title].freeze

    def initialize(path: default_path)
      @path = path
      FileUtils.mkdir_p(File.dirname(path))
      save!(default_rule) unless File.exist?(path)
    end

    def current
      normalize_rule(load_data)
    end

    def set(fields)
      fields = normalize_fields(fields)
      raise ArgumentError, "sort rule cannot be empty" if fields.empty?

      save!(fields)
      fields
    end

    def reset
      save!(default_rule)
      default_rule
    end

    private

    def default_path
      File.expand_path("../../data/sort_rules.json", __dir__)
    end

    def default_rule
      DEFAULT_RULE.dup
    end

    def load_data
      JSON.parse(File.read(@path))
    rescue Errno::ENOENT, JSON::ParserError
      default_rule
    end

    def normalize_rule(rule)
      normalize_fields(Array(rule))
    end

    def normalize_fields(fields)
      fields = Array(fields).map { |field| field.to_s.strip.downcase }.reject(&:empty?)
      fields.each do |field|
        raise ArgumentError, "invalid sort field: #{field}" unless ALLOWED_FIELDS.include?(field)
      end
      fields = fields.uniq
      fields += default_rule.reject { |field| fields.include?(field) }
      fields
    end

    def save!(fields)
      File.write(@path, JSON.pretty_generate(fields))
    end
  end
end
