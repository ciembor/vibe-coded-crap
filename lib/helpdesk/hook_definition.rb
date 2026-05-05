require "time"
require "helpdesk/event_subscription"

module Helpdesk
  class HookDefinition
    def self.create(id:, attrs:, now: Time.now.utc)
      record = new(
        "id" => id,
        "name" => attrs.fetch(:name).to_s.strip,
        "events" => EventSubscription.normalize(attrs.fetch(:events, [])),
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

    def initialize(row)
      @row = normalize_row(row)
    end

    def matches?(event)
      @row["enabled"] != false && EventSubscription.new(@row["events"]).include?(event)
    end

    def to_h
      @row.each_with_object({}) do |(key, value), copy|
        copy[key] = value.is_a?(Array) ? value.dup : value
      end
    end

    private

    def validate!
      raise ArgumentError, "hook name cannot be empty" if @row["name"].empty?
      raise ArgumentError, "hook command cannot be empty" if @row["command"].empty?

      self
    end

    def normalize_row(row)
      row = row.is_a?(Hash) ? row : {}
      now = Time.now.utc.iso8601
      {
        "id" => row["id"] || row[:id],
        "name" => (row["name"] || row[:name]).to_s.strip,
        "events" => EventSubscription.normalize(row["events"] || row[:events] || []),
        "command" => (row["command"] || row[:command]).to_s.strip,
        "enabled" => row.key?("enabled") ? row["enabled"] : row.fetch(:enabled, true),
        "created_at" => row["created_at"] || row[:created_at] || now,
        "updated_at" => row["updated_at"] || row[:updated_at] || now
      }
    end
  end
end
