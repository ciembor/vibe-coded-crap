require "time"
require "helpdesk/event_subscription"

module Helpdesk
  class WebhookDefinition
    def self.create(id:, attrs:, now: Time.now.utc)
      row = {
        "id" => id,
        "name" => attrs.fetch(:name).to_s.strip,
        "url" => attrs.fetch(:url).to_s.strip,
        "events" => EventSubscription.normalize(attrs.fetch(:events, [])),
        "enabled" => attrs.fetch(:enabled, true),
        "created_at" => now.utc.iso8601,
        "updated_at" => now.utc.iso8601
      }
      validate!(row)
      row
    end

    def self.from_h(row)
      new(row)
    end

    def initialize(row)
      @row = normalize_row(row)
    end

    def update(attrs, now: Time.now.utc)
      updated = to_h
      updated["name"] = attrs[:name].to_s.strip if attrs.key?(:name)
      updated["url"] = attrs[:url].to_s.strip if attrs.key?(:url)
      updated["events"] = EventSubscription.normalize(attrs[:events]) if attrs.key?(:events)
      updated["enabled"] = attrs[:enabled] if attrs.key?(:enabled)
      updated["updated_at"] = now.utc.iso8601
      self.class.send(:validate!, updated)
      updated
    end

    def matches?(event)
      @row["enabled"] != false && EventSubscription.new(@row["events"]).include?(event)
    end

    def to_h
      @row.each_with_object({}) do |(key, value), copy|
        copy[key] = value.is_a?(Array) ? value.dup : value
      end
    end

    def self.validate!(row)
      raise ArgumentError, "webhook name cannot be empty" if row["name"].to_s.empty?
      raise ArgumentError, "webhook url cannot be empty" if row["url"].to_s.empty?
    end
    private_class_method :validate!

    def normalize_row(row)
      row = row.is_a?(Hash) ? row : {}
      now = Time.now.utc.iso8601
      {
        "id" => row["id"] || row[:id],
        "name" => (row["name"] || row[:name]).to_s.strip,
        "url" => (row["url"] || row[:url]).to_s.strip,
        "events" => EventSubscription.normalize(row["events"] || row[:events] || []),
        "enabled" => row.key?("enabled") ? row["enabled"] : row.fetch(:enabled, true),
        "created_at" => row["created_at"] || row[:created_at] || now,
        "updated_at" => row["updated_at"] || row[:updated_at] || now
      }
    end
    private :normalize_row
  end
end
