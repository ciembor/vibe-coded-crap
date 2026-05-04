require "time"

module Helpdesk
  class User
    ROLES = %w[admin agent viewer].freeze

    attr_accessor :id, :name, :email, :role, :created_at, :updated_at

    def self.from_h(hash)
      new(
        id: hash["id"],
        name: hash["name"],
        email: hash["email"],
        role: hash["role"],
        created_at: hash["created_at"],
        updated_at: hash["updated_at"]
      ).normalize!
    end

    def initialize(id: nil, name: "", email: "", role: "agent", created_at: nil, updated_at: nil)
      @id = id
      @name = name
      @email = email
      @role = role
      @created_at = created_at
      @updated_at = updated_at
    end

    def normalize!
      self.name = name.to_s.strip
      raise ArgumentError, "user name cannot be empty" if name.empty?

      self.email = email.to_s.strip
      self.role = normalize_role(role)
      self.created_at ||= Time.now.utc.iso8601
      self.updated_at ||= created_at
      self
    end

    def update(attrs = {})
      self.name = attrs.fetch(:name, name).to_s.strip
      raise ArgumentError, "user name cannot be empty" if name.empty?

      self.email = attrs.fetch(:email, email).to_s.strip
      self.role = normalize_role(attrs.fetch(:role, role))
      self.updated_at = Time.now.utc.iso8601
      self
    end

    def display_name
      email.empty? ? name : "#{name} <#{email}>"
    end

    def role_label
      role.to_s.empty? ? "agent" : role
    end

    def to_h
      {
        "id" => id,
        "name" => name,
        "email" => email,
        "role" => role,
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
  end
end
