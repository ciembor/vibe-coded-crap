require "json"
require "shellwords"
require "time"
require "helpdesk/api_presenter"

module Helpdesk
  module CliApiCommands
    def api(args)
      if args[0].to_s == "tokens"
        manage_api_tokens(args.drop(1))
        return
      end

      token_index = args.index("--token")
      raw_token = token_index ? args[token_index + 1].to_s.strip : ""
      if raw_token.empty?
        puts ApiPresenter.response(401, {}, "Missing API token.")
        return
      end

      method_args = args.dup
      method_args.slice!(token_index, 2) if token_index

      method = method_args[0].to_s.strip.upcase
      path = method_args[1].to_s.strip
      body = method_args.drop(2).join(" ")
      if method.empty? || path.empty?
        puts "Usage: api --token TOKEN METHOD PATH [JSON_BODY]"
        return
      end

      auth_token = @api_tokens.find_by_token(raw_token)
      if auth_token.nil? || auth_token["enabled"] == false
        puts ApiPresenter.response(401, {}, "Invalid API token.")
        return
      end

      rate = @api_tokens.consume!(raw_token, limit: @api_rate_limit, window_seconds: @api_rate_window_seconds)
      if rate.nil?
        puts ApiPresenter.response(401, {}, "Invalid API token.")
        return
      end
      unless rate[:allowed]
        puts ApiPresenter.response(429, {}, "API rate limit exceeded.", rate_limit_remaining: rate[:remaining], rate_limit_reset_at: rate[:reset_at])
        return
      end

      previous_user = @current_user
      @current_user = @users.find(auth_token["user_id"]) || previous_user

      payload = parse_api_body(body)
      response =
        if method == "GET" && path == "/tickets"
          cached_api_response([@current_user&.id, method, path, body]) do
            { status: 200, data: @store.all.map { |ticket| ApiPresenter.ticket(ticket) } }
          end
        elsif method == "GET" && path.match?(%r{\A/tickets/\d+\z})
          cached_api_response([@current_user&.id, method, path, body]) do
            ticket = @store.find(path.split("/").last)
            return { status: 404, error: "Ticket not found." } unless ticket

            { status: 200, data: ApiPresenter.ticket(ticket) }
          end
        elsif method == "POST" && path == "/tickets"
          return unless require_permission!(:ticket_write)

          ticket = @store.create(payload.transform_keys(&:to_sym))
          invalidate_api_cache!
          log_action("ticket.create", "ticket ##{ticket.id}", title: ticket.title, status: ticket.status, priority: ticket.priority)
          { status: 201, data: ApiPresenter.ticket(ticket) }
        elsif method == "PATCH" && path.match?(%r{\A/tickets/\d+\z})
          return unless require_permission!(:ticket_write)

          id = path.split("/").last
          ticket = @store.update(id, payload.transform_keys(&:to_sym), actor_role: @current_user&.role_label)
          return puts(ApiPresenter.response(404, {}, "Ticket not found.")) unless ticket

          invalidate_api_cache!
          log_action("ticket.update", "ticket ##{id}", changes: payload)
          { status: 200, data: ApiPresenter.ticket(ticket) }
        elsif method == "DELETE" && path.match?(%r{\A/tickets/\d+\z})
          return unless require_permission!(:ticket_write)

          id = path.split("/").last
          if @store.delete(id)
            invalidate_api_cache!
            log_action("ticket.delete", "ticket ##{id}")
            { status: 200, data: { deleted: true, id: id.to_i } }
          else
            { status: 404, error: "Ticket not found." }
          end
        elsif method == "POST" && path.match?(%r{\A/tickets/\d+/restore\z})
          return unless require_permission!(:ticket_write)

          id = path.split("/")[2]
          if @store.restore(id)
            invalidate_api_cache!
            log_action("ticket.restore", "ticket ##{id}")
            { status: 200, data: { restored: true, id: id.to_i } }
          else
            { status: 404, error: "Ticket not found." }
          end
        elsif method == "GET" && path == "/users"
          cached_api_response([@current_user&.id, method, path, body]) do
            { status: 200, data: @users.all.map { |user| ApiPresenter.user(user) } }
          end
        elsif method == "GET" && path == "/webhooks"
          cached_api_response([@current_user&.id, method, path, body]) do
            { status: 200, data: @webhooks.all }
          end
        elsif method == "POST" && path == "/webhooks"
          return unless require_permission!(:admin)

          webhook = @webhooks.create(
            name: payload["name"] || payload[:name],
            url: payload["url"] || payload[:url],
            events: payload["events"] || payload[:events] || []
          )
          invalidate_api_cache!
          { status: 201, data: webhook }
        elsif method == "DELETE" && path.match?(%r{\A/webhooks/\d+\z})
          return unless require_permission!(:admin)

          id = path.split("/").last
          if @webhooks.delete(id)
            invalidate_api_cache!
            { status: 200, data: { deleted: true, id: id.to_i } }
          else
            { status: 404, error: "Webhook not found." }
          end
        else
          { status: 404, error: "Unknown API route." }
        end

      puts ApiPresenter.response(response[:status], response[:data] || {}, response[:error])
    rescue ArgumentError, JSON::ParserError => e
      puts ApiPresenter.response(400, {}, e.message)
    ensure
      @current_user = previous_user if defined?(previous_user)
    end

    def manage_api_tokens(args)
      action = args[0]
      case action
      when "list"
        return unless require_permission!(:admin)

        tokens = @api_tokens.all
        if tokens.empty?
          puts "No API tokens."
          return
        end

        tokens.each do |token|
          user = @users.find(token["user_id"])
          puts "##{token["id"]} #{token["name"]} user=#{user ? user.display_name : "user ##{token["user_id"]}"} enabled=#{token["enabled"]} last_used=#{token["last_used_at"] || 'never'} requests=#{token["request_count"].to_i} window_started=#{token["window_started_at"] || 'never'}"
        end
      when "create"
        return unless require_permission!(:admin)

        name = args[1]
        user_id = args[2] || @current_user.id
        if name.to_s.strip.empty?
          puts "Usage: api tokens create NAME [USER_ID]"
          return
        end

        token = @api_tokens.create(name: name, user_id: user_id, scopes: ["*"])
        invalidate_api_cache!
        user = @users.find(token["user_id"])
        puts "Created API token ##{token["id"]} for #{user ? user.display_name : "user ##{token["user_id"]}"}."
        puts "Token: #{token["token"]}"
      when "revoke"
        return unless require_permission!(:admin)

        id = required_id(args.drop(1))
        token = @api_tokens.revoke(id)
        if token
          invalidate_api_cache!
          puts "Revoked API token ##{id}."
        else
          puts "API token not found."
        end
      else
        puts "Usage: api tokens list | api tokens create NAME [USER_ID] | api tokens revoke ID"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def cached_api_response(key)
      normalized_key = Array(key).map(&:to_s).join("|")
      entry = @api_response_cache[normalized_key]
      if entry && (Time.now.utc - entry[:cached_at]) < API_CACHE_TTL_SECONDS
        return entry[:value]
      end

      value = yield
      @api_response_cache[normalized_key] = { value: value, cached_at: Time.now.utc }
      value
    end

    def invalidate_api_cache!
      @api_response_cache.clear
    end

    def parse_api_body(body)
      body = body.to_s.strip
      return {} if body.empty?

      if body.start_with?("{", "[")
        parsed = JSON.parse(body)
        return parsed if parsed.is_a?(Hash)

        raise ArgumentError, "API body must be a JSON object"
      end

      pairs = Shellwords.split(body)
      pairs.each_with_object({}) do |pair, hash|
        key, value = pair.split("=", 2)
        raise ArgumentError, "invalid body pair: #{pair}" if key.to_s.strip.empty?

        hash[key] = value.nil? ? true : value
      end
    end

  end
end
