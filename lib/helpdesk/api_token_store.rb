require "helpdesk/api_token_record"
require "helpdesk/json_file"

module Helpdesk
  class ApiTokenStore
    include JsonFileStore

    def initialize(path: default_path)
      configure_json_file(path, default: [])
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
      token = ApiTokenRecord.create(id: next_id(tokens), attrs: attrs)
      tokens << token
      save!(tokens)
      token
    end

    def revoke(id)
      tokens = load_data
      token = tokens.find { |row| row["id"].to_i == id.to_i }
      return nil unless token

      token.replace(ApiTokenRecord.from_h(token).revoke)
      save!(tokens)
      token
    end

    def touch!(raw_token)
      tokens = load_data
      index = tokens.index { |row| row["token"].to_s == raw_token.to_s }
      return nil unless index

      tokens[index] = ApiTokenRecord.from_h(tokens[index]).touch
      save!(tokens)
      tokens[index]
    end

    def consume!(raw_token, limit:, window_seconds:)
      tokens = load_data
      index = tokens.index { |row| row["token"].to_s == raw_token.to_s }
      return nil unless index

      result = ApiTokenRecord.from_h(tokens[index]).consume(limit: limit, window_seconds: window_seconds)
      tokens[index] = result[:token]
      save!(tokens)
      result[:response]
    end

    private

    def default_path
      File.expand_path("../../data/api_tokens.json", __dir__)
    end
  end
end
