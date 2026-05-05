require "json"
require "fileutils"
require "time"

module Helpdesk
  class SessionStore
    attr_reader :path

    def initialize(path: default_path)
      @path = path
      FileUtils.mkdir_p(File.dirname(path))
      save!("current_user_id" => nil, "updated_at" => Time.now.utc.iso8601) unless File.exist?(path)
    end

    def current_user_id
      load_data["current_user_id"]
    end

    def current_user_id=(value)
      save!("current_user_id" => value.nil? ? nil : value.to_i, "updated_at" => Time.now.utc.iso8601)
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

    def load_data
      data = JSON.parse(File.read(path))
      data.is_a?(Hash) ? data : {}
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end

    def save!(payload)
      File.write(path, JSON.pretty_generate(payload))
    end
  end
end
