require "shellwords"
require "time"

module Helpdesk
  class PluginDefinition
    def self.create(id:, attrs:, now: Time.now.utc)
      record = new(
        "id" => id,
        "name" => attrs.fetch(:name).to_s.strip,
        "command" => attrs.fetch(:command).to_s.strip,
        "enabled" => attrs.fetch(:enabled, true),
        "created_at" => now.utc.iso8601,
        "updated_at" => now.utc.iso8601
      )
      record.send(:validate!)
      record.to_h
    end

    def self.from_h(row)
      new(row)
    end

    def self.from_config(row, fallback_id:, now: Time.now.utc)
      row = row.is_a?(Hash) ? row : {}
      name = row["name"] || row[:name]
      command = row["command"] || row[:command]
      return nil if name.to_s.strip.empty? || command.to_s.strip.empty?

      enabled = row.key?("enabled") ? row["enabled"] : row[:enabled]
      new(
        "id" => (row["id"] || row[:id] || fallback_id).to_i,
        "name" => name.to_s.strip,
        "command" => command.to_s.strip,
        "enabled" => enabled.nil? ? true : enabled,
        "created_at" => row["created_at"] || row[:created_at] || now.utc.iso8601,
        "updated_at" => row["updated_at"] || row[:updated_at] || now.utc.iso8601
      ).to_h
    end

    def initialize(row)
      @row = normalize_row(row)
    end

    def name
      @row["name"]
    end

    def enabled?
      @row["enabled"] != false
    end

    def render_command(args)
      rendered = @row["command"].to_s.dup
      rendered.gsub!("{{args}}", Shellwords.join(Array(args).map(&:to_s)))
      Array(args).each_with_index do |arg, idx|
        rendered.gsub!("{{#{idx + 1}}}", Shellwords.escape(arg.to_s))
      end
      rendered
    end

    def to_h
      @row.dup
    end

    private

    def validate!
      raise ArgumentError, "plugin name cannot be empty" if @row["name"].empty?
      raise ArgumentError, "plugin command cannot be empty" if @row["command"].empty?

      self
    end

    def normalize_row(row)
      row = row.is_a?(Hash) ? row : {}
      now = Time.now.utc.iso8601
      {
        "id" => row["id"] || row[:id],
        "name" => (row["name"] || row[:name]).to_s.strip,
        "command" => (row["command"] || row[:command]).to_s.strip,
        "enabled" => row.key?("enabled") ? row["enabled"] : row.fetch(:enabled, true),
        "created_at" => row["created_at"] || row[:created_at] || now,
        "updated_at" => row["updated_at"] || row[:updated_at] || now
      }
    end
  end
end
