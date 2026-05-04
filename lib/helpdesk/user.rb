require "time"

module Helpdesk
  class User
    ROLES = %w[admin agent viewer].freeze

    attr_accessor :id, :name, :email, :role, :notification_preferences, :created_at, :updated_at

    def self.from_h(hash)
      new(
        id: hash["id"],
        name: hash["name"],
        email: hash["email"],
        role: hash["role"],
        notification_preferences: hash["notification_preferences"] || {},
        created_at: hash["created_at"],
        updated_at: hash["updated_at"]
      ).normalize!
    end

    def initialize(id: nil, name: "", email: "", role: "agent", notification_preferences: {}, created_at: nil, updated_at: nil)
      @id = id
      @name = name
      @email = email
      @role = role
      @notification_preferences = notification_preferences
      @created_at = created_at
      @updated_at = updated_at
    end

    def normalize!
      self.name = name.to_s.strip
      raise ArgumentError, "user name cannot be empty" if name.empty?

      self.email = email.to_s.strip
      self.role = normalize_role(role)
      self.notification_preferences = normalize_notification_preferences(notification_preferences)
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

    def to_h
      {
        "id" => id,
        "name" => name,
        "email" => email,
        "role" => role,
        "notification_preferences" => notification_preferences,
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
  end
end
