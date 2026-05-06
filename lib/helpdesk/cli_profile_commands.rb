module Helpdesk
  module CliProfileCommands
    def list_profiles
      profiles = @profiles.all
      if profiles.empty?
        puts "No profiles."
        return
      end

      profiles.each do |profile|
        marker = @active_profile && profile["name"].to_s == @active_profile["name"].to_s ? " *" : ""
        puts "#{profile["name"]} data_dir=#{profile["data_dir"]}#{marker}"
      end
    end

    def manage_profiles(args)
      action = args[0]
      case action
      when nil, "show"
        name = args[1] || @active_profile&.dig("name")
        profile = @profiles.find(name)
        return puts("Profile not found.") unless profile

        puts "Profile: #{profile["name"]}"
        puts "Data dir: #{profile["data_dir"]}"
        puts "Environment profile: #{ENV.fetch("HELPDESK_PROFILE", "none")}"
        puts "Active: #{@active_profile && profile["name"] == @active_profile["name"] ? 'yes' : 'no'}"
      when "use"
        name = args[1].to_s.strip
        return puts("Usage: profile use NAME") if name.empty?
        unless @profiles.set_active(name)
          puts "Profile not found."
          return
        end

        configure_from_profile!(force_profile_dir: true)
        log_action("profile.use", "profile #{name}")
        puts "Switched to profile #{name}."
      when "set"
        name = args[1].to_s.strip
        key = args[2].to_s.strip
        value = args.drop(3).join(" ")
        if name.empty? || key.empty? || value.empty?
          puts "Usage: profile set NAME data_dir PATH"
          return
        end

        unless key == "data_dir"
          puts "Only data_dir can be configured for profiles."
          return
        end

        profile = @profiles.upsert(name, "data_dir" => value)
        log_action("profile.set", "profile #{name}", data_dir: profile["data_dir"])
        puts "Updated profile #{name}."
      when "delete"
        name = args[1].to_s.strip
        return puts("Usage: profile delete NAME") if name.empty?
        unless @profiles.delete(name)
          puts "Profile not found."
          return
        end

        puts "Deleted profile #{name}."
      else
        puts "Usage: profile show [NAME] | profile use NAME | profile set NAME data_dir PATH | profile delete NAME"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_session(args)
      action = args[0]
      case action
      when nil, "show"
        if @current_user
          puts "Current session user: ##{@current_user.id} #{@current_user.display_name} (role: #{@current_user.role_label})"
          puts "Session file: #{@session.path}"
        else
          puts "No current session user."
        end
      when "clear"
        @session.clear!
        @current_user = @users.all.first
        persist_current_user_session!
        puts "Cleared session user."
      else
        puts "Usage: session show | session clear"
      end
    end

    def manage_debug(args)
      action = args[0]
      case action
      when nil, "show"
        puts "Debug logging: #{@debug_enabled ? 'on' : 'off'}"
        puts "Session file: #{@session.path}"
      when "on"
        @debug_enabled = true
        persist_debug_setting!
        debug_log("debug mode enabled")
        puts "Debug logging enabled."
      when "off"
        @debug_enabled = false
        persist_debug_setting!
        puts "Debug logging disabled."
      else
        puts "Usage: debug on | debug off | debug show"
      end
    end
  end
end
