module Helpdesk
  class ActivityPresenter
    VISIBLE_PREFIXES = %w[
      ticket.
      reminder.
      notification.
      user.
      hook.
      plugin.
      escalation.
    ].freeze

    def self.visible?(entry)
      action = entry["action"].to_s
      VISIBLE_PREFIXES.any? { |prefix| action.start_with?(prefix) } || action == "tickets.import"
    end

    def self.for_ticket?(entry, ticket_id)
      return false if ticket_id.nil?

      entry["subject"].to_s.match?(/\bticket ##{Regexp.escape(ticket_id.to_s)}\b/)
    end

    def self.line(entry)
      "#{entry["created_at"]} #{entry["actor"]} #{label(entry)}"
    end

    def self.label(entry)
      action = entry["action"].to_s
      subject = entry["subject"].to_s

      case action
      when "ticket.create" then "created #{subject}"
      when "ticket.update" then "updated #{subject}"
      when "ticket.delete" then "deleted #{subject}"
      when "ticket.restore" then "restored #{subject}"
      when "hook.create" then "created #{subject}"
      when "hook.delete" then "removed #{subject}"
      when "hook.trigger" then "triggered #{subject}"
      when "plugin.create" then "created #{subject}"
      when "plugin.delete" then "removed #{subject}"
      when "plugin.run" then "ran #{subject}"
      when "ticket.close" then "closed #{subject}"
      when "ticket.status" then "changed #{subject} to #{entry.dig("details", "status")}"
      when "ticket.comment" then "commented on #{subject}"
      when "ticket.note" then "added an internal note to #{subject}"
      when "ticket.watch_add" then "added watcher to #{subject}"
      when "ticket.watch_remove" then "removed watcher from #{subject}"
      when "ticket.attach_add" then "added attachment to #{subject}"
      when "ticket.attach_remove" then "removed attachment from #{subject}"
      when "ticket.merge" then "merged #{subject}"
      when "ticket.relate" then "related #{subject}"
      when "ticket.unrelate" then "removed relationship for #{subject}"
      when "ticket.parent_set" then "set parent for #{subject}"
      when "ticket.parent_clear" then "cleared parent for #{subject}"
      when "ticket.dependency_add" then "added dependency to #{subject}"
      when "ticket.dependency_remove" then "removed dependency from #{subject}"
      when "ticket.archive" then "archived #{subject}"
      when "ticket.unarchive" then "unarchived #{subject}"
      when "ticket.tag.add" then "added tag to #{subject}"
      when "ticket.tag.remove" then "removed tag from #{subject}"
      when "reminder.set" then "set a reminder on #{subject}"
      when "reminder.clear" then "cleared a reminder on #{subject}"
      when "reminder.repeat_set" then "set a repeating reminder on #{subject}"
      when "reminder.repeat_clear" then "cleared repeating reminder on #{subject}"
      when "notification.email" then "sent email notification for #{subject}"
      when "user.create" then "created #{subject}"
      when "user.switch" then "switched to #{subject}"
      when "user.role" then "changed role for #{subject}"
      when "escalation.record" then "escalated #{subject}"
      when "escalation.rules_set" then "updated escalation rules for #{subject}"
      when "escalation.rules_reset" then "reset escalation rules for #{subject}"
      when "user.notification_preferences" then "updated notification preferences for #{subject}"
      when "user.notification_suppression_rules" then "updated suppression rules for #{subject}"
      when "tickets.import" then "imported tickets"
      else "#{action} #{subject}"
      end
    end
    private_class_method :label
  end
end
