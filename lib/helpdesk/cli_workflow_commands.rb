module Helpdesk
  module CliWorkflowCommands
    def manage_sorting(args)
      action = args[0]
      case action
      when nil, "show"
        show_sort_rules
      when "set"
        return unless require_permission!(:admin)

        fields = args.drop(1)
        return puts "Usage: sort rules set FIELD [FIELD ...]" if fields.empty?

        rule = @sort_rules.set(fields)
        log_action("sort.rules_set", "sort", fields: rule)
        puts "Updated custom sort rule."
      when "reset"
        return unless require_permission!(:admin)

        rule = @sort_rules.reset
        log_action("sort.rules_reset", "sort", fields: rule)
        puts "Reset custom sort rule."
      when "rules"
        manage_sort_rules(args.drop(1))
      else
        puts "Usage: sort rules show | sort rules set FIELD [FIELD ...] | sort rules reset"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_workflows(args)
      action = args[0]
      case action
      when nil, "show"
        show_workflows
      when "set"
        return unless require_permission!(:admin)

        ticket_type = args[1].to_s.strip
        statuses = args.drop(2)
        if ticket_type.empty? || statuses.empty?
          puts "Usage: workflow set TYPE STATUS [STATUS ...]"
          return
        end

        workflow = @workflows.upsert(ticket_type, statuses: statuses)
        reload_ticket_workflows!
        log_action("workflow.set", "workflow #{ticket_type}", workflow: workflow["statuses"])
        puts "Updated workflow #{ticket_type}."
      when "reset"
        return unless require_permission!(:admin)

        target = args[1].to_s.strip
        target = "all" if target.empty?
        @workflows.reset(target)
        reload_ticket_workflows!
        log_action("workflow.reset", "workflow #{target}", workflow: target)
        puts target == "all" ? "Reset all workflows." : "Reset workflow #{target}."
      when "transitions"
        manage_workflow_transitions(args.drop(1))
      when "permissions"
        manage_workflow_permissions(args.drop(1))
      else
        puts "Usage: workflow show | workflow set TYPE STATUS [STATUS ...] | workflow reset [TYPE|all] | workflow transitions show TYPE | workflow transitions set TYPE FROM STATUS [STATUS ...] | workflow transitions reset [TYPE|all] | workflow permissions show TYPE | workflow permissions set TYPE FROM TO ROLE [ROLE ...] | workflow permissions reset [TYPE|all]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_sort_rules(args)
      action = args[0]
      case action
      when nil, "show"
        show_sort_rules
      when "set"
        return unless require_permission!(:admin)

        fields = args.drop(1)
        return puts "Usage: sort rules set FIELD [FIELD ...]" if fields.empty?

        rule = @sort_rules.set(fields)
        log_action("sort.rules_set", "sort", fields: rule)
        puts "Updated custom sort rule."
      when "reset"
        return unless require_permission!(:admin)

        rule = @sort_rules.reset
        log_action("sort.rules_reset", "sort", fields: rule)
        puts "Reset custom sort rule."
      else
        puts "Usage: sort rules show | sort rules set FIELD [FIELD ...] | sort rules reset"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def show_workflows
      workflows = @workflows.all
      if workflows.empty?
        puts "No workflows."
        return
      end

      workflows.each do |workflow|
        transitions = format_workflow_transitions(workflow["transitions"] || {})
        permissions = format_workflow_permissions(workflow["permissions"] || {})
        puts "#{workflow["ticket_type"]}: #{workflow["statuses"].join(", ")} (initial: #{workflow["initial_status"]})"
        puts "  transitions: #{transitions}"
        puts "  permissions: #{permissions}"
      end
    end

    def manage_workflow_transitions(args)
      action = args[0]
      case action
      when "show"
        ticket_type = args[1].to_s.strip
        if ticket_type.empty?
          puts "Usage: workflow transitions show TYPE"
          return
        end

        workflow = @workflows.find(ticket_type)
        return puts "Workflow not found." unless workflow

        puts "#{workflow["ticket_type"]}:"
        puts "  #{format_workflow_transitions(workflow["transitions"] || {})}"
      when "set"
        return unless require_permission!(:admin)

        ticket_type = args[1].to_s.strip
        from_status = args[2].to_s.strip
        next_statuses = args.drop(3)
        if ticket_type.empty? || from_status.empty? || next_statuses.empty?
          puts "Usage: workflow transitions set TYPE FROM STATUS [STATUS ...]"
          return
        end

        workflow = @workflows.set_transition(ticket_type, from_status, next_statuses)
        return puts "Workflow not found." unless workflow

        reload_ticket_workflows!
        log_action("workflow.transitions_set", "workflow #{ticket_type}", from: from_status, to: next_statuses)
        puts "Updated transitions for workflow #{ticket_type}."
      when "reset"
        return unless require_permission!(:admin)

        target = args[1].to_s.strip
        target = "all" if target.empty?
        result = @workflows.reset_transitions(target)
        return puts "Workflow not found." if result.nil? && target != "all"

        reload_ticket_workflows!
        log_action("workflow.transitions_reset", "workflow #{target}", workflow: target)
        puts target == "all" ? "Reset workflow transitions for all workflows." : "Reset workflow transitions for #{target}."
      else
        puts "Usage: workflow transitions show TYPE | workflow transitions set TYPE FROM STATUS [STATUS ...] | workflow transitions reset [TYPE|all]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def manage_workflow_permissions(args)
      action = args[0]
      case action
      when "show"
        ticket_type = args[1].to_s.strip
        if ticket_type.empty?
          puts "Usage: workflow permissions show TYPE"
          return
        end

        workflow = @workflows.find(ticket_type)
        return puts "Workflow not found." unless workflow

        puts "#{workflow["ticket_type"]}:"
        puts "  #{format_workflow_permissions(workflow["permissions"] || {})}"
      when "set"
        return unless require_permission!(:admin)

        ticket_type = args[1].to_s.strip
        from_status = args[2].to_s.strip
        to_status = args[3].to_s.strip
        roles = args.drop(4)
        if ticket_type.empty? || from_status.empty? || to_status.empty? || roles.empty?
          puts "Usage: workflow permissions set TYPE FROM TO ROLE [ROLE ...]"
          return
        end

        workflow = @workflows.set_transition_permission(ticket_type, from_status, to_status, roles)
        return puts "Workflow not found." unless workflow

        reload_ticket_workflows!
        log_action("workflow.permissions_set", "workflow #{ticket_type}", from: from_status, to: to_status, roles: roles)
        puts "Updated transition permissions for workflow #{ticket_type}."
      when "reset"
        return unless require_permission!(:admin)

        target = args[1].to_s.strip
        target = "all" if target.empty?
        result = @workflows.reset_transition_permissions(target)
        return puts "Workflow not found." if result.nil? && target != "all"

        reload_ticket_workflows!
        log_action("workflow.permissions_reset", "workflow #{target}", workflow: target)
        puts target == "all" ? "Reset transition permissions for all workflows." : "Reset transition permissions for #{target}."
      else
        puts "Usage: workflow permissions show TYPE | workflow permissions set TYPE FROM TO ROLE [ROLE ...] | workflow permissions reset [TYPE|all]"
      end
    rescue ArgumentError => e
      puts e.message
    end

    def reload_ticket_workflows!
      Ticket.workflows = @workflows.to_workflow_hash
    end

    def show_workflow_transitions(ticket)
      next_statuses = Ticket.workflow_next_statuses_for(ticket.ticket_type, ticket.status)
      puts "Next statuses: #{next_statuses.empty? ? 'none' : next_statuses.join(', ')}"
      permissions = next_statuses.map do |next_status|
        roles = Ticket.workflow_transition_roles_for(ticket.ticket_type, ticket.status, next_status)
        "#{next_status}=#{roles.join(', ')}"
      end
      puts "Transition roles: #{permissions.empty? ? 'none' : permissions.join(' | ')}"
    end

    def format_workflow_transitions(transitions)
      return "none" if transitions.empty?

      transitions.sort_by { |from_status, _| from_status.to_s }.map do |from_status, next_statuses|
        "#{from_status} -> #{Array(next_statuses).join(', ')}"
      end.join(" | ")
    end

    def format_workflow_permissions(permissions)
      return "none" if permissions.empty?

      permissions.sort_by { |from_status, _| from_status.to_s }.map do |from_status, transitions|
        inner = transitions.sort_by { |to_status, _| to_status.to_s }.map do |to_status, roles|
          "#{to_status}: #{Array(roles).join(', ')}"
        end.join(" | ")
        "#{from_status} => #{inner}"
      end.join(" | ")
    end

    def show_sort_rules
      rule = @sort_rules.current
      puts "Custom sort order: #{rule.join(' > ')}"
      puts "Allowed fields: #{SortRuleStore::ALLOWED_FIELDS.join(', ')}"
    end
  end
end
