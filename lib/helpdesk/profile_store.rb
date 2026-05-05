require "time"
require "helpdesk/json_file"

module Helpdesk
  class ProfileStore
    include JsonFileStore

    def initialize(path: default_path)
      configure_json_file(path, default: default_payload)
      ensure_default_profile!
    end

    def all
      load_data.fetch("profiles", {}).each_with_object([]) do |(name, profile), rows|
        rows << normalize_profile(name, profile)
      end.sort_by { |profile| profile["name"].to_s }
    end

    def active_profile_name
      configured = ENV.fetch("HELPDESK_PROFILE", "").to_s.strip
      return configured unless configured.empty?

      load_data["active_profile"].to_s
    end

    def active_profile
      find(active_profile_name) || find("default")
    end

    def find(name)
      name = name.to_s
      profile = load_data.fetch("profiles", {})[name]
      profile ? normalize_profile(name, profile) : nil
    end

    def upsert(name, attrs)
      data = load_data
      data["profiles"] ||= {}
      profile = normalize_profile(name, attrs)
      data["profiles"][profile["name"]] = profile
      save!(data)
      profile
    end

    def set_active(name)
      name = name.to_s
      return false if name.empty?
      return false unless find(name)

      data = load_data
      data["active_profile"] = name
      save!(data)
      true
    end

    def delete(name)
      name = name.to_s
      return false if name.empty? || name == "default"

      data = load_data
      data["profiles"] ||= {}
      removed = data["profiles"].delete(name)
      return false unless removed

      data["active_profile"] = "default" if data["active_profile"].to_s == name
      save!(data)
      true
    end

    private

    def default_path
      File.expand_path("../../data/application_profiles.json", __dir__)
    end

    def default_payload
      {
        "active_profile" => "default",
        "profiles" => {
          "default" => normalize_profile("default", "data_dir" => File.expand_path("../../data", __dir__))
        }
      }
    end

    def ensure_default_profile!
      data = load_data
      data["profiles"] ||= {}
      data["profiles"]["default"] ||= normalize_profile("default", "data_dir" => File.expand_path("../../data", __dir__))
      data["active_profile"] = "default" if data["active_profile"].to_s.empty?
      save!(data)
    end

    def load_data
      data = super
      data.is_a?(Hash) ? data : default_payload
    end

    def normalize_profile(name, attrs)
      attrs = attrs.is_a?(Hash) ? attrs : {}
      data_dir = attrs["data_dir"] || attrs[:data_dir] || File.expand_path("../../data", __dir__)
      {
        "name" => name.to_s.strip,
        "data_dir" => File.expand_path(data_dir.to_s.strip.empty? ? "../../data" : data_dir.to_s),
        "created_at" => attrs["created_at"] || attrs[:created_at] || Time.now.utc.iso8601,
        "updated_at" => Time.now.utc.iso8601
      }
    end
  end
end
