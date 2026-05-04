require "json"
require "fileutils"
require "securerandom"
require "time"

module Helpdesk
  class ApiTokenStore
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

    private

    def default_path
      File.expand_path("../../data/api_tokens.json", __dir__)
    end

    def load_data
      JSON.parse(File.read(path))
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def save!(tokens)
      File.write(path, JSON.pretty_generate(tokens))
    end

    def next_id(rows)
      (rows.map { |row| row["id"].to_i }.max || 0) + 1
    end

    def normalize_scopes(scopes)
      Array(scopes).flat_map { |scope| scope.to_s.split(",") }.map { |scope| scope.strip }.reject(&:empty?).uniq.sort
    end
  end
end
