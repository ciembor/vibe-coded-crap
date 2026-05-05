require "json"
require "fileutils"
require "time"

module Helpdesk
  class WebhookStore
    attr_reader :path

    def initialize(path: default_path)
      @path = path
      FileUtils.mkdir_p(File.dirname(path))
      save!([]) unless File.exist?(path)
    end

    def all
      load_data.sort_by { |row| row["id"].to_i }
    end

    def find(id)
      all.find { |webhook| webhook["id"].to_i == id.to_i }
    end

    def create(attrs)
      webhooks = load_data
      webhook = {
        "id" => next_id(webhooks),
        "name" => attrs.fetch(:name).to_s.strip,
        "url" => attrs.fetch(:url).to_s.strip,
        "events" => normalize_events(attrs.fetch(:events, [])),
        "enabled" => attrs.fetch(:enabled, true),
        "created_at" => Time.now.utc.iso8601,
        "updated_at" => Time.now.utc.iso8601
      }
      raise ArgumentError, "webhook name cannot be empty" if webhook["name"].empty?
      raise ArgumentError, "webhook url cannot be empty" if webhook["url"].empty?

      webhooks << webhook
      save!(webhooks)
      webhook
    end

    def delete(id)
      webhooks = load_data
      removed = webhooks.reject! { |row| row["id"].to_i == id.to_i }
      save!(webhooks) if removed
      !removed.nil?
    end

    def update(id, attrs)
      webhooks = load_data
      index = webhooks.index { |row| row["id"].to_i == id.to_i }
      return nil unless index

      webhook = webhooks[index].dup
      webhook["name"] = attrs[:name].to_s.strip if attrs.key?(:name)
      webhook["url"] = attrs[:url].to_s.strip if attrs.key?(:url)
      webhook["events"] = normalize_events(attrs[:events]) if attrs.key?(:events)
      webhook["enabled"] = attrs[:enabled] if attrs.key?(:enabled)
      webhook["updated_at"] = Time.now.utc.iso8601
      raise ArgumentError, "webhook name cannot be empty" if webhook["name"].to_s.strip.empty?
      raise ArgumentError, "webhook url cannot be empty" if webhook["url"].to_s.strip.empty?

      webhooks[index] = webhook
      save!(webhooks)
      webhook
    end

    def matching(event)
      normalized_event = event.to_s.strip
      all.select do |webhook|
        webhook["enabled"] != false && subscribed_to_event?(webhook, normalized_event)
      end
    end

    private

    def default_path
      File.expand_path("../../data/webhooks.json", __dir__)
    end

    def load_data
      JSON.parse(File.read(path))
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def save!(webhooks)
      File.write(path, JSON.pretty_generate(webhooks))
    end

    def next_id(rows)
      (rows.map { |row| row["id"].to_i }.max || 0) + 1
    end

    def normalize_events(events)
      Array(events).flat_map { |event| event.to_s.split(",") }.map { |event| event.strip }.reject(&:empty?).uniq.sort
    end

    def subscribed_to_event?(webhook, event)
      events = Array(webhook["events"]).map(&:to_s)
      return true if events.empty?
      return true if events.include?("*")
      return true if events.include?(event)

      events.any? do |subscribed|
        subscribed.end_with?("*") && event.start_with?(subscribed.delete_suffix("*"))
      end
    end
  end
end
