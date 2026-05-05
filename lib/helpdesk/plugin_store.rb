require "json"
require "shellwords"
require "time"
require "helpdesk/json_file"

module Helpdesk
  class PluginStore
    include JsonFileStore

    def initialize(path: default_path, config_path: default_config_path)
      @config_path = config_path
      configure_json_file(path, default: [])
    end

    def all
      (load_data + config_data).uniq { |row| row["name"].to_s }.sort_by { |row| row["id"].to_i }
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
      raise ArgumentError, "plugin name already exists" if all.any? { |row| row["name"].to_s == name }

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

    def config_path
      @config_path || ENV.fetch("HELPDESK_PLUGINS_CONFIG", default_config_path)
    end

    def default_config_path
      File.expand_path("../../data/plugins.config.json", __dir__)
    end

    def config_data
      parsed = JSON.parse(File.read(config_path))
      rows = parsed.is_a?(Array) ? parsed : (parsed["plugins"] || parsed[:plugins] || [])
      Array(rows).map.with_index(1) do |row, idx|
        normalize_plugin(row, idx)
      end.compact
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def normalize_plugin(row, fallback_id)
      row = row.is_a?(Hash) ? row : {}
      name = row["name"] || row[:name]
      command = row["command"] || row[:command]
      enabled = row.key?("enabled") ? row["enabled"] : row[:enabled]
      return nil if name.to_s.strip.empty? || command.to_s.strip.empty?

      {
        "id" => (row["id"] || row[:id] || fallback_id).to_i,
        "name" => name.to_s.strip,
        "command" => command.to_s.strip,
        "enabled" => enabled.nil? ? true : enabled,
        "created_at" => row["created_at"] || row[:created_at] || Time.now.utc.iso8601,
        "updated_at" => row["updated_at"] || row[:updated_at] || Time.now.utc.iso8601
      }
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
