require "time"
require "helpdesk/json_file"

module Helpdesk
  class HookStore
    include JsonFileStore

    def initialize(path: default_path)
      configure_json_file(path, default: [])
    end

    def all
      load_data.sort_by { |row| row["id"].to_i }
    end

    def find(id)
      all.find { |hook| hook["id"].to_i == id.to_i }
    end

    def create(attrs)
      hooks = load_data
      hook = {
        "id" => next_id(hooks),
        "name" => attrs.fetch(:name).to_s.strip,
        "events" => normalize_events(attrs.fetch(:events, [])),
        "command" => attrs.fetch(:command).to_s.strip,
        "enabled" => attrs.fetch(:enabled, true),
        "created_at" => Time.now.utc.iso8601,
        "updated_at" => Time.now.utc.iso8601
      }
      raise ArgumentError, "hook name cannot be empty" if hook["name"].empty?
      raise ArgumentError, "hook command cannot be empty" if hook["command"].empty?

      hooks << hook
      save!(hooks)
      hook
    end

    def delete(id)
      hooks = load_data
      removed = hooks.reject! { |row| row["id"].to_i == id.to_i }
      save!(hooks) if removed
      !removed.nil?
    end

    def matching(event)
      normalized_event = event.to_s.strip
      all.select do |hook|
        hook["enabled"] != false && subscribed_to_event?(hook, normalized_event)
      end
    end

    private

    def default_path
      File.expand_path("../../data/hooks.json", __dir__)
    end

    def normalize_events(events)
      Array(events).flat_map { |event| event.to_s.split(",") }.map { |event| event.strip }.reject(&:empty?).uniq.sort
    end

    def subscribed_to_event?(hook, event)
      events = Array(hook["events"]).map(&:to_s)
      return true if events.empty?
      return true if events.include?("*")
      return true if events.include?(event)

      events.any? do |subscribed|
        subscribed.end_with?("*") && event.start_with?(subscribed.delete_suffix("*"))
      end
    end
  end
end
