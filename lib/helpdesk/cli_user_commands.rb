module Helpdesk
  module CliUserCommands
    def list_users
      users = @users.all
      if users.empty?
        puts "No users found."
        return
      end

      users.each do |user|
        marker = @current_user && user.id.to_i == @current_user.id.to_i ? " *" : ""
        puts "##{user.id} #{user.display_name} [#{user.role_label}]#{marker}"
      end
    end

    def manage_users(args)
      action = args[0]
      case action
      when "add"
        return unless require_permission!(:admin)

        name = prompt("Name")
        email = prompt("Email", "")
        role = prompt("Role (admin, agent, viewer)", "agent")
        user = @users.create(name: name, email: email, role: role)
        @current_user ||= user
        persist_current_user_session!
        log_action("user.create", "user ##{user.id}", name: user.name, role: user.role_label)
        puts "Created user ##{user.id}."
      when "switch"
        user = @users.find(required_id(args.drop(1)))
        return puts "User not found." unless user

        log_action("user.switch", "user ##{user.id}", name: user.name, role: user.role_label)
        @current_user = user
        persist_current_user_session!
        puts "Switched to #{user.display_name}."
      when "role"
        return unless require_permission!(:admin)

        user = @users.find(required_id(args.drop(1)))
        return puts "User not found." unless user

        role = args[2]
        role = prompt("Role (admin, agent, viewer)", user.role_label) if role.to_s.strip.empty?
        user = @users.update(user.id, role: role)
        log_action("user.role", "user ##{user.id}", name: user.name, role: user.role_label)
        puts "Updated role for #{user.display_name} to #{user.role_label}."
      else
        puts "Usage: user add | user switch ID | user role ID ROLE"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def whoami
      if @current_user
        puts "Current user: ##{@current_user.id} #{@current_user.display_name} (role: #{@current_user.role_label})"
        puts "Notification prefs: #{@current_user.notification_preferences_label}"
        puts "Suppression rules: #{@current_user.notification_suppression_rules_label}"
        puts "Saved searches: #{@current_user.saved_searches_label}"
        puts "Favorite filters: #{@current_user.favorite_filters_label}"
      else
        puts "No current user."
      end
    end

    def manage_notifications(args)
      action = args[0]
      case action
      when "show"
        show_notification_preferences
      when "set"
        key = args[1]
        value = args[2]
        return puts "Usage: notify set KEY VALUE" if key.to_s.strip.empty? || value.to_s.strip.empty?

        update_notification_preferences(key, value)
      when "suppress"
        manage_notification_suppression(args.drop(1))
      when "email"
        return unless require_permission!(:ticket_write)

        id = required_id(args.drop(1))
        ticket = @store.find(id)
        return puts "Ticket not found." unless ticket

        body = args.drop(2).join(" ")
        body = "Ticket ##{ticket.id}: #{ticket.title}" if body.strip.empty?
        send_email_notifications(ticket, subject: "Ticket ##{ticket.id}", body: body, event: "manual")
      else
        puts "Usage: notify show | notify set KEY VALUE | notify suppress show|add|remove ... | notify email ID [BODY]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def current_user_name
      @current_user ? @current_user.name : "agent"
    end

    def show_notification_preferences
      prefs = @current_user.notification_preferences || {}
      if prefs.empty?
        puts "No notification preferences."
        return
      end

      prefs.each do |key, value|
        puts "#{key}: #{value}"
      end
    end

    def manage_notification_suppression(args)
      action = args[0]
      case action
      when "show"
        show_notification_suppression_rules
      when "add"
        rule = args[1]
        return puts "Usage: notify suppress add RULE" if rule.to_s.strip.empty?

        update_notification_suppression_rules(:add, rule)
      when "remove"
        rule = args[1]
        return puts "Usage: notify suppress remove RULE" if rule.to_s.strip.empty?

        update_notification_suppression_rules(:remove, rule)
      else
        puts "Usage: notify suppress show | notify suppress add RULE | notify suppress remove RULE"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def show_notification_suppression_rules
      rules = @current_user.notification_suppression_rules || []
      if rules.empty?
        puts "No suppression rules."
        return
      end

      rules.each { |rule| puts rule }
    end

    def update_notification_suppression_rules(action, rule)
      rules = (@current_user.notification_suppression_rules || []).dup
      rule = rule.to_s.strip.downcase
      return puts "Rule cannot be empty." if rule.empty?

      case action
      when :add
        rules << rule unless rules.include?(rule)
      when :remove
        rules.delete(rule)
      end

      updated_user = @users.update(@current_user.id, notification_suppression_rules: rules)
      if updated_user
        @current_user = updated_user
      else
        @current_user.notification_suppression_rules = rules
        @users.save_user(@current_user)
      end
      log_action("user.notification_suppression_rules", "user ##{@current_user.id}", notification_suppression_rules: rules)
      puts "Updated suppression rules: #{rules.empty? ? 'none' : rules.join(', ')}"
    end

    def update_notification_preferences(key, value)
      prefs = (@current_user.notification_preferences || {}).dup
      prefs[key.to_s] = parse_boolean(value)
      updated_user = @users.update(@current_user.id, notification_preferences: prefs)
      if updated_user
        @current_user = updated_user
      else
        @current_user.notification_preferences = prefs
        @users.save_user(@current_user)
      end
      log_action("user.notification_preferences", "user ##{@current_user.id}", notification_preferences: prefs)
      puts "Updated notification preference #{key} to #{prefs[key.to_s]}."
    end

    def send_email_notifications(ticket, subject:, body:, event:)
      recipients = email_notifier.deliver(ticket, subject: subject, body: body, event: event)
      return if recipients.empty?

      log_action("notification.email", "ticket ##{ticket.id}", recipients: recipients.map(&:display_name), subject: subject)
    end

    def parse_boolean(value)
      case value.to_s.strip.downcase
      when "true", "yes", "on", "1" then true
      when "false", "no", "off", "0" then false
      else
        raise ArgumentError, "invalid boolean value: #{value}"
      end
    end
  end
end
