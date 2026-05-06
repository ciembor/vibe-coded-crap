require "securerandom"
require "time"

module Helpdesk
  class ApiTokenRecord
    def self.create(id:, attrs:, token: SecureRandom.hex(24), now: Time.now.utc)
      row = {
        "id" => id,
        "name" => attrs.fetch(:name).to_s.strip,
        "token" => token,
        "user_id" => attrs.fetch(:user_id).to_i,
        "scopes" => normalize_scopes(attrs.fetch(:scopes, [])),
        "enabled" => true,
        "request_count" => 0,
        "window_started_at" => nil,
        "created_at" => now.utc.iso8601,
        "updated_at" => now.utc.iso8601,
        "last_used_at" => nil
      }
      validate!(row)
      row
    end

    def self.from_h(row)
      new(row)
    end

    def self.normalize_scopes(scopes)
      Array(scopes).flat_map { |scope| scope.to_s.split(",") }.map { |scope| scope.strip }.reject(&:empty?).uniq.sort
    end

    def initialize(row)
      @row = normalize_row(row)
    end

    def revoke(now: Time.now.utc)
      updated = to_h
      updated["enabled"] = false
      updated["updated_at"] = now.utc.iso8601
      updated
    end

    def touch(now: Time.now.utc)
      updated = to_h
      updated["last_used_at"] = now.utc.iso8601
      updated["updated_at"] = now.utc.iso8601
      updated
    end

    def consume(limit:, window_seconds:, now: Time.now.utc)
      updated = to_h
      window_started_at = parse_time(updated["window_started_at"]) || now
      if window_expired?(window_started_at, now, window_seconds)
        window_started_at = now
        updated["request_count"] = 0
      end

      request_count = updated["request_count"].to_i
      if request_count >= limit
        updated["updated_at"] = now.utc.iso8601
        updated["last_used_at"] = now.utc.iso8601
        updated["window_started_at"] = window_started_at.utc.iso8601
        return {
          token: updated,
          response: {
            allowed: false,
            token: updated,
            remaining: 0,
            reset_at: (window_started_at + window_seconds).utc.iso8601
          }
        }
      end

      updated["request_count"] = request_count + 1
      updated["window_started_at"] = window_started_at.utc.iso8601
      updated["last_used_at"] = now.utc.iso8601
      updated["updated_at"] = now.utc.iso8601
      {
        token: updated,
        response: {
          allowed: true,
          token: updated,
          remaining: [limit - updated["request_count"].to_i, 0].max,
          reset_at: (window_started_at + window_seconds).utc.iso8601
        }
      }
    end

    def to_h
      @row.each_with_object({}) do |(key, value), copy|
        copy[key] = value.is_a?(Array) ? value.dup : value
      end
    end

    def self.validate!(row)
      raise ArgumentError, "token name cannot be empty" if row["name"].to_s.empty?
      raise ArgumentError, "user_id must be positive" if row["user_id"].to_i.zero?
    end
    private_class_method :validate!

    def normalize_row(row)
      row = row.is_a?(Hash) ? row : {}
      {
        "id" => row["id"] || row[:id],
        "name" => (row["name"] || row[:name]).to_s.strip,
        "token" => (row["token"] || row[:token]).to_s,
        "user_id" => (row["user_id"] || row[:user_id]).to_i,
        "scopes" => self.class.normalize_scopes(row["scopes"] || row[:scopes] || []),
        "enabled" => row.key?("enabled") ? row["enabled"] : row.fetch(:enabled, true),
        "request_count" => (row["request_count"] || row[:request_count] || 0).to_i,
        "window_started_at" => row["window_started_at"] || row[:window_started_at],
        "created_at" => row["created_at"] || row[:created_at],
        "updated_at" => row["updated_at"] || row[:updated_at],
        "last_used_at" => row["last_used_at"] || row[:last_used_at]
      }
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

    private :normalize_row, :parse_time, :window_expired?
  end
end
