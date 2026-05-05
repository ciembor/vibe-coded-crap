require "securerandom"
require "time"
require "helpdesk/json_file_store"

module Helpdesk
  class ApiTokenStore < JsonFileStore

    def all
      load_data.sort_by { |row| row["id"].to_i }
    end

    def find(id)
      all.find { |token| token["id"].to_i == id.to_i }
    end

    def find_by_token(raw_token)
      all.find { |token| token["token"].to_s == raw_token.to_s }
    end

    def create(attrs)
      tokens = load_data
      token = {
        "id" => next_id(tokens),
        "name" => attrs.fetch(:name).to_s.strip,
        "token" => SecureRandom.hex(24),
        "user_id" => attrs.fetch(:user_id).to_i,
        "scopes" => normalize_scopes(attrs.fetch(:scopes, [])),
        "enabled" => true,
        "request_count" => 0,
        "window_started_at" => nil,
        "created_at" => Time.now.utc.iso8601,
        "updated_at" => Time.now.utc.iso8601,
        "last_used_at" => nil
      }
      raise ArgumentError, "token name cannot be empty" if token["name"].empty?
      raise ArgumentError, "user_id must be positive" if token["user_id"].zero?

      tokens << token
      save!(tokens)
      token
    end

    def revoke(id)
      tokens = load_data
      token = tokens.find { |row| row["id"].to_i == id.to_i }
      return nil unless token

      token["enabled"] = false
      token["updated_at"] = Time.now.utc.iso8601
      save!(tokens)
      token
    end

    def touch!(raw_token)
      tokens = load_data
      index = tokens.index { |row| row["token"].to_s == raw_token.to_s }
      return nil unless index

      tokens[index]["last_used_at"] = Time.now.utc.iso8601
      tokens[index]["updated_at"] = Time.now.utc.iso8601
      save!(tokens)
      tokens[index]
    end

    def consume!(raw_token, limit:, window_seconds:)
      tokens = load_data
      index = tokens.index { |row| row["token"].to_s == raw_token.to_s }
      return nil unless index

      token = tokens[index]
      now = Time.now.utc
      window_started_at = parse_time(token["window_started_at"]) || now
      if window_expired?(window_started_at, now, window_seconds)
        window_started_at = now
        token["request_count"] = 0
      end

      request_count = token["request_count"].to_i
      if request_count >= limit
        token["updated_at"] = now.iso8601
        token["last_used_at"] = now.iso8601
        token["window_started_at"] = window_started_at.iso8601
        save!(tokens)
        return {
          allowed: false,
          token: token,
          remaining: 0,
          reset_at: (window_started_at + window_seconds).iso8601
        }
      end

      token["request_count"] = request_count + 1
      token["window_started_at"] = window_started_at.iso8601
      token["last_used_at"] = now.iso8601
      token["updated_at"] = now.iso8601
      save!(tokens)
      {
        allowed: true,
        token: token,
        remaining: [limit - token["request_count"].to_i, 0].max,
        reset_at: (window_started_at + window_seconds).iso8601
      }
    end

  private

    def default_path
      File.expand_path("../../data/api_tokens.json", __dir__)
    end

    def normalize_scopes(scopes)
      Array(scopes).flat_map { |scope| scope.to_s.split(",") }.map { |scope| scope.strip }.reject(&:empty?).uniq.sort
    end

    def parse_time(value)
      return nil if value.nil? || value.to_s.strip.empty?

      Time.parse(value.to_s).utc
    rescue ArgumentError
      nil
    end

    def window_expired?(window_started_at, now, window_seconds)
      (now - window_started_at) >= window_seconds
    end
  end
end
