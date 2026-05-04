require "time"

module Helpdesk
  class Template
    attr_accessor :name, :ticket_type, :title, :description, :status, :priority, :tags, :custom_fields, :created_at, :updated_at

    def self.from_h(hash)
      new(
        name: hash["name"],
        ticket_type: hash["ticket_type"],
        title: hash["title"],
        description: hash["description"],
        status: hash["status"],
        priority: hash["priority"],
        tags: hash["tags"] || [],
        custom_fields: hash["custom_fields"] || {},
        created_at: hash["created_at"],
        updated_at: hash["updated_at"]
      ).normalize!
    end

    def initialize(name: "", ticket_type: "general", title: "", description: "", status: "open", priority: "medium", tags: [], custom_fields: {}, created_at: nil, updated_at: nil)
      @name = name
      @ticket_type = ticket_type
      @title = title
      @description = description
      @status = status
      @priority = priority
      @tags = tags.dup
      @custom_fields = custom_fields
      @created_at = created_at
      @updated_at = updated_at
    end

    def normalize!
      self.name = name.to_s.strip
      raise ArgumentError, "template name cannot be empty" if name.empty?

      self.ticket_type = ticket_type.to_s.strip.downcase
      self.ticket_type = "general" if ticket_type.empty?
      self.title = title.to_s
      self.description = description.to_s
      self.status = normalize_status(status)
      self.priority = normalize_priority(priority)
      self.tags = Array(tags).map { |tag| tag.to_s.strip }.reject(&:empty?).uniq.sort
      self.custom_fields = normalize_custom_fields(custom_fields)
      self.created_at ||= Time.now.utc.iso8601
      self.updated_at ||= created_at
      self
    end

    def update(attrs = {})
      self.name = attrs.fetch(:name, name).to_s.strip
      raise ArgumentError, "template name cannot be empty" if name.empty?

      self.ticket_type = attrs.fetch(:ticket_type, ticket_type)
      self.title = attrs.fetch(:title, title).to_s
      self.description = attrs.fetch(:description, description).to_s
      self.status = normalize_status(attrs.fetch(:status, status))
      self.priority = normalize_priority(attrs.fetch(:priority, priority))
      self.tags = Array(attrs.fetch(:tags, tags)).map { |tag| tag.to_s.strip }.reject(&:empty?).uniq.sort
      self.custom_fields = normalize_custom_fields(attrs.fetch(:custom_fields, custom_fields))
      self.updated_at = Time.now.utc.iso8601
      self
    end

    def to_h
      {
        "name" => name,
        "ticket_type" => ticket_type,
        "title" => title,
        "description" => description,
        "status" => status,
        "priority" => priority,
        "tags" => tags,
        "custom_fields" => custom_fields,
        "created_at" => created_at,
        "updated_at" => updated_at
      }
    end

    private

    def normalize_status(value)
      value = value.to_s.strip
      return "open" if value.empty?

      %w[open in_progress waiting resolved closed].include?(value) ? value : "open"
    end

    def normalize_priority(value)
      value = value.to_s.strip
      return "medium" if value.empty?

      %w[low medium high urgent].include?(value) ? value : "medium"
    end

    def normalize_custom_fields(value)
      hash = value.is_a?(Hash) ? value : {}
      hash.each_with_object({}) do |(key, val), normalized|
        key = key.to_s.strip
        next if key.empty?

        normalized[key] = val.to_s
      end
    end
  end
end
