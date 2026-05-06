module Helpdesk
  class EmailNotifier
    def initialize(users:)
      @users = users
    end

    def deliver(ticket, subject:, body:, event:)
      recipients = recipients_for(ticket)
      if recipients.empty?
        puts "No email recipients for ticket ##{ticket.id}."
        return []
      end

      recipients.each do |user|
        next if suppressed?(user, ticket, event)

        puts "[email mock] To: #{user.display_name}"
        puts "[email mock] Subject: #{subject}"
        puts "[email mock] Body: #{body}"
      end
      recipients
    end

    private

    def recipients_for(ticket)
      watcher_ids = ticket.watchers || []
      users = watcher_ids.map { |watcher_id| @users.find(watcher_id) }.compact
      users.select do |user|
        user.email.to_s.strip != "" &&
          user.email_notifications_enabled? &&
          user.preference_enabled?("watchers")
      end
    end

    def suppressed?(user, ticket, event)
      rules = user.notification_suppression_rules || []
      rules.include?("all") ||
        (event == "comments" && rules.include?("comments")) ||
        (event == "reminders" && rules.include?("reminders")) ||
        (event == "manual" && rules.include?("manual")) ||
        rules.include?("watchers") ||
        (ticket.closed? && rules.include?("closed_tickets"))
    end
  end
end
