require "json"
require "fileutils"
require "helpdesk/user"

module Helpdesk
  class UserStore
    attr_reader :path

    def initialize(path: default_path)
      @path = path
      FileUtils.mkdir_p(File.dirname(path))
      save!([]) unless File.exist?(path)
    end

    def all
      load_data.map { |row| User.from_h(row) }
    end

    def find(id)
      all.find { |user| user.id.to_i == id.to_i }
    end

    def create(attrs)
      users = load_data
      user = User.new(
        id: next_id(users),
        name: attrs.fetch(:name),
        email: attrs.fetch(:email, ""),
        role: attrs.fetch(:role, "agent")
      ).normalize!
      users << user.to_h
      save!(users)
      user
    end

    def update(id, attrs)
      users = load_data
      index = users.index { |row| row["id"].to_i == id.to_i }
      return nil unless index

      user = User.from_h(users[index]).update(attrs)
      users[index] = user.to_h
      save!(users)
      user
    end

    def save_user(user)
      users = load_data
      index = users.index { |row| row["id"].to_i == user.id.to_i }
      if index
        users[index] = user.to_h
      else
        users << user.to_h
      end
      save!(users)
      user
    end

    private

    def default_path
      File.expand_path("../../data/users.json", __dir__)
    end

    def load_data
      JSON.parse(File.read(path))
    rescue Errno::ENOENT, JSON::ParserError
      []
    end

    def save!(rows)
      File.write(path, JSON.pretty_generate(rows))
    end

    def next_id(rows)
      (rows.map { |row| row["id"].to_i }.max || 0) + 1
    end
  end
end
