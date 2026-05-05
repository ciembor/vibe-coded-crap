require "time"
require "helpdesk/json_file_store"

module Helpdesk
  class SessionStore < JsonFileStore

    def current_user_id
      load_data["current_user_id"]
    end

    def current_user_id=(value)
      data = load_data
      data["current_user_id"] = value.nil? ? nil : value.to_i
      data["updated_at"] = Time.now.utc.iso8601
      save!(data)
    end

    def debug_enabled
      !!load_data["debug_enabled"]
    end

    def debug_enabled=(value)
      data = load_data
      data["debug_enabled"] = !!value
      data["updated_at"] = Time.now.utc.iso8601
      save!(data)
    end

    def clear!
      self.current_user_id = nil
    end

    def to_h
      load_data
    end

    private

    def default_path
      File.expand_path("../../data/session.json", __dir__)
    end

    def default_payload
      {
        "current_user_id" => nil,
        "debug_enabled" => false,
        "updated_at" => Time.now.utc.iso8601
      }
    end

    def normalize_loaded_payload(payload)
      payload.is_a?(Hash) ? payload : default_payload
    end
  end
end
