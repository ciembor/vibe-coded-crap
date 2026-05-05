require "json"
require "fileutils"
require "helpdesk/template"

module Helpdesk
  class TemplateStore
    attr_reader :path

    def initialize(path: default_path)
      @path = path
      FileUtils.mkdir_p(File.dirname(path))
      save!([]) unless File.exist?(path)
    end

    def all
      load_data.map { |row| Template.from_h(row) }
    end

    def find(name)
      all.find { |template| template.name.casecmp?(name.to_s.strip) }
    end

    def create(attrs)
      templates = load_data
      template = Template.new(
        name: attrs.fetch(:name),
        ticket_type: attrs.fetch(:ticket_type, "general"),
        title: attrs.fetch(:title, ""),
        description: attrs.fetch(:description, ""),
        status: attrs.fetch(:status, "open"),
        priority: attrs.fetch(:priority, "medium"),
        tags: attrs.fetch(:tags, []),
        custom_fields: attrs.fetch(:custom_fields, {})
      ).normalize!
      templates.reject! { |row| row["name"].to_s.casecmp?(template.name) }
      templates << template.to_h
      save!(templates)
      template
    end

    def update(name, attrs)
      templates = load_data
      index = templates.index { |row| row["name"].to_s.casecmp?(name.to_s.strip) }
      return nil unless index

      template = Template.from_h(templates[index]).update(attrs)
      templates[index] = template.to_h
      save!(templates)
      template
    end

    def delete(name)
      templates = load_data
      removed = templates.reject! { |row| row["name"].to_s.casecmp?(name.to_s.strip) }
      save!(templates) if removed
      !removed.nil?
    end

    private

    def default_path
      File.expand_path("../../data/ticket_templates.json", __dir__)
    end

    def load_data
      JSON.parse(File.read(path))
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def save!(rows)
      File.write(path, JSON.pretty_generate(rows))
    end
  end
end
