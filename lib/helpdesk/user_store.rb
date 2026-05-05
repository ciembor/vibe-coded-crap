require "helpdesk/user"
require "helpdesk/json_file_store"

module Helpdesk
  class UserStore < JsonFileStore

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
  end
end
