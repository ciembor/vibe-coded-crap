require "time"

module Helpdesk
  class User
    attr_accessor :id, :name, :email, :created_at, :updated_at

    def self.from_h(hash)
      new(
        id: hash["id"],
        name: hash["name"],
        email: hash["email"],
        created_at: hash["created_at"],
        updated_at: hash["updated_at"]
      ).normalize!
    end

    def initialize(id: nil, name: "", email: "", created_at: nil, updated_at: nil)
      @id = id
      @name = name
      @email = email
      @created_at = created_at
      @updated_at = updated_at
    end

    def normalize!
      self.name = name.to_s.strip
      raise ArgumentError, "user name cannot be empty" if name.empty?

      self.email = email.to_s.strip
      self.created_at ||= Time.now.utc.iso8601
      self.updated_at ||= created_at
      self
    end

    def update(attrs = {})
      self.name = attrs.fetch(:name, name).to_s.strip
      raise ArgumentError, "user name cannot be empty" if name.empty?

      self.email = attrs.fetch(:email, email).to_s.strip
      self.updated_at = Time.now.utc.iso8601
      self
    end

    def display_name
      email.empty? ? name : "#{name} <#{email}>"
    end

    def to_h
      {
        "id" => id,
        "name" => name,
        "email" => email,
        "created_at" => created_at,
        "updated_at" => updated_at
      }
    end
  end
end
