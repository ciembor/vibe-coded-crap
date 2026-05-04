require "time"

module Helpdesk
  class User
    ROLES = %w[admin agent viewer].freeze

    attr_accessor :id, :name, :email, :role, :notification_preferences, :notification_suppression_rules, :saved_searches, :favorite_filters, :created_at, :updated_at

    def self.from_h(hash)
      new(
        id: hash["id"],
        name: hash["name"],
        email: hash["email"],
        role: hash["role"],
        notification_preferences: hash["notification_preferences"] || {},
        notification_suppression_rules: hash["notification_suppression_rules"] || [],
        saved_searches: hash["saved_searches"] || [],
        favorite_filters: hash["favorite_filters"] || [],
        created_at: hash["created_at"],
        updated_at: hash["updated_at"]
      ).normalize!
    end

    def initialize(id: nil, name: "", email: "", role: "agent", notification_preferences: {}, notification_suppression_rules: [], saved_searches: [], favorite_filters: [], created_at: nil, updated_at: nil)
      @id = id
      @name = name
      @email = email
      @role = role
      @notification_preferences = notification_preferences
      @notification_suppression_rules = notification_suppression_rules
      @saved_searches = saved_searches
      @favorite_filters = favorite_filters
      @created_at = created_at
      @updated_at = updated_at
    end

    def normalize!
      self.name = name.to_s.strip
      raise ArgumentError, "user name cannot be empty" if name.empty?

      self.email = email.to_s.strip
      self.role = normalize_role(role)
      self.notification_preferences = normalize_notification_preferences(notification_preferences)
      self.notification_suppression_rules = normalize_suppression_rules(notification_suppression_rules)
      self.saved_searches = normalize_saved_searches(saved_searches)
      self.favorite_filters = normalize_favorite_filters(favorite_filters)
      self.created_at ||= Time.now.utc.iso8601
      self.updated_at ||= created_at
      self
    end

    def update(attrs = {})
      self.name = attrs.fetch(:name, name).to_s.strip
      raise ArgumentError, "user name cannot be empty" if name.empty?

      self.email = attrs.fetch(:email, email).to_s.strip
      self.role = normalize_role(attrs.fetch(:role, role))
      self.notification_preferences = normalize_notification_preferences(
        attrs.fetch(:notification_preferences, notification_preferences)
      )
      self.notification_suppression_rules = normalize_suppression_rules(
        attrs.fetch(:notification_suppression_rules, notification_suppression_rules)
      )
      self.saved_searches = normalize_saved_searches(
        attrs.fetch(:saved_searches, saved_searches)
      )
      self.favorite_filters = normalize_favorite_filters(
        attrs.fetch(:favorite_filters, favorite_filters)
      )
      self.updated_at = Time.now.utc.iso8601
      self
    end

    def display_name
      email.empty? ? name : "#{name} <#{email}>"
    end

    def role_label
      role.to_s.empty? ? "agent" : role
    end

    def notification_preferences_label
      preferences = notification_preferences || {}
      preferences.map { |key, value| "#{key}=#{value}" }.join(", ")
    end

    def notification_suppression_rules_label
      rules = notification_suppression_rules || []
      rules.empty? ? "none" : rules.join(", ")
    end

    def saved_searches_label
      searches = saved_searches || []
      searches.empty? ? "none" : "#{searches.count} saved"
    end

    def favorite_filters_label
      filters = favorite_filters || []
      filters.empty? ? "none" : "#{filters.count} saved"
    end

    def email_notifications_enabled?
      preference_enabled?("email")
    end

    def preference_enabled?(key)
      preferences = notification_preferences || {}
      value = preferences[key.to_s]
      return true if value.nil?

      value == true || %w[true yes on 1].include?(value.to_s.strip.downcase)
    end

    def to_h
      {
        "id" => id,
        "name" => name,
        "email" => email,
        "role" => role,
        "notification_preferences" => notification_preferences,
        "notification_suppression_rules" => notification_suppression_rules,
        "saved_searches" => saved_searches,
        "favorite_filters" => favorite_filters,
        "created_at" => created_at,
        "updated_at" => updated_at
      }
    end

    private

    def normalize_role(value)
      value = value.to_s.strip
      return "agent" if value.empty?
      return value if ROLES.include?(value)

      raise ArgumentError, "invalid role: #{value}"
    end

    def normalize_notification_preferences(value)
      defaults = {
        "email" => true,
        "reminders" => true,
        "watchers" => true,
        "audit_summary" => false
      }

      hash = value.is_a?(Hash) ? value : {}
      normalized = defaults.dup
      hash.each do |key, val|
        key = key.to_s
        next unless defaults.key?(key)

        normalized[key] = case val
        when true, false
          val
        when nil
          normalized[key]
        else
          %w[true yes on 1].include?(val.to_s.strip.downcase)
        end
      end
      normalized
    end

    def normalize_suppression_rules(value)
      rules = Array(value).map { |rule| rule.to_s.strip.downcase }.reject(&:empty?).uniq.sort
      allowed = %w[all comments reminders manual watchers closed_tickets]
      rules.select { |rule| allowed.include?(rule) }
    end

    def normalize_saved_searches(value)
      Array(value).map do |search|
        {
          "name" => search["name"] || search[:name] || "",
          "query" => search["query"] || search[:query] || "",
          "created_at" => search["created_at"] || search[:created_at] || Time.now.utc.iso8601,
          "updated_at" => search["updated_at"] || search[:updated_at] || Time.now.utc.iso8601
        }
      end.reject { |search| search["name"].to_s.strip.empty? || search["query"].to_s.strip.empty? }.uniq { |search| search["name"].to_s.downcase }.sort_by { |search| search["name"].to_s.downcase }
    end

    def normalize_favorite_filters(value)
      Array(value).map do |filter|
        {
          "name" => filter["name"] || filter[:name] || "",
          "options" => normalize_filter_options(filter["options"] || filter[:options] || {}),
          "created_at" => filter["created_at"] || filter[:created_at] || Time.now.utc.iso8601,
          "updated_at" => filter["updated_at"] || filter[:updated_at] || Time.now.utc.iso8601
        }
      end.reject { |filter| filter["name"].to_s.strip.empty? }.uniq { |filter| filter["name"].to_s.downcase }.sort_by { |filter| filter["name"].to_s.downcase }
    end

    def normalize_filter_options(value)
      value = value.is_a?(Hash) ? value : {}
      normalized = {}
      normalized["status"] = fetch_option(value, "status").to_s.strip unless fetch_option(value, "status").to_s.strip.empty?
      normalized["priority"] = fetch_option(value, "priority").to_s.strip unless fetch_option(value, "priority").to_s.strip.empty?
      normalized["tag"] = fetch_option(value, "tag").to_s.strip unless fetch_option(value, "tag").to_s.strip.empty?
      normalized["sort"] = fetch_option(value, "sort").to_s.strip unless fetch_option(value, "sort").to_s.strip.empty?
      normalized["overdue"] = truthy?(fetch_option(value, "overdue"))
      normalized["archived"] = truthy?(fetch_option(value, "archived"))
      normalized["active"] = truthy?(fetch_option(value, "active"))
      normalized.reject { |_key, val| val == false || val.nil? || val.to_s.strip.empty? }
    end

    def fetch_option(hash, key)
      hash[key] || hash[key.to_sym] || hash[key.to_s]
    end

    def truthy?(value)
      case value
      when true then true
      when false, nil then false
      else
        %w[true yes on 1].include?(value.to_s.strip.downcase)
      end
    end
  end
end
