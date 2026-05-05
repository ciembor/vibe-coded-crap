require "json"
require "fileutils"
require "shellwords"
require "time"

module Helpdesk
  class PluginStore
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
      all.find { |plugin| plugin["id"].to_i == id.to_i }
    end

    def find_by_name(name)
      all.find { |plugin| plugin["name"].to_s == name.to_s }
    end

    def create(attrs)
      plugins = load_data
      name = attrs.fetch(:name).to_s.strip
      command = attrs.fetch(:command).to_s.strip
      raise ArgumentError, "plugin name cannot be empty" if name.empty?
      raise ArgumentError, "plugin command cannot be empty" if command.empty?
      raise ArgumentError, "plugin name already exists" if plugins.any? { |row| row["name"].to_s == name }

      plugin = {
        "id" => next_id(plugins),
        "name" => name,
        "command" => command,
        "enabled" => attrs.fetch(:enabled, true),
        "created_at" => Time.now.utc.iso8601,
        "updated_at" => Time.now.utc.iso8601
      }

      plugins << plugin
      save!(plugins)
      plugin
    end

    def delete(id)
      plugins = load_data
      removed = plugins.reject! { |row| row["id"].to_i == id.to_i }
      save!(plugins) if removed
      !removed.nil?
    end

    def run(name, args: [])
      plugin = find_by_name(name)
      return nil unless plugin
      return nil if plugin["enabled"] == false

      {
        plugin: plugin,
        command: render_command(plugin["command"], args)
      }
    end

    private

    def default_path
      File.expand_path("../../data/plugins.json", __dir__)
    end

    def load_data
      JSON.parse(File.read(path))
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def save!(plugins)
      File.write(path, JSON.pretty_generate(plugins))
    end

    def next_id(rows)
      (rows.map { |row| row["id"].to_i }.max || 0) + 1
    end

    def render_command(template, args)
      rendered = template.to_s.dup
      rendered.gsub!("{{args}}", Shellwords.join(args.map(&:to_s)))
      Array(args).each_with_index do |arg, idx|
        rendered.gsub!("{{#{idx + 1}}}", Shellwords.escape(arg.to_s))
      end
      rendered
    end
  end
end
