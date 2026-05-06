require "json"

module Helpdesk
  class ApiPresenter
    def self.response(status, data = {}, error = nil, meta = {})
      payload = { status: status }
      payload["error"] = error if error
      payload["data"] = data unless error
      meta.each do |key, value|
        payload[key.to_s] = value
      end
      JSON.pretty_generate(payload)
    end

    def self.ticket(ticket)
      {
        id: ticket.id,
        title: ticket.title,
        description: ticket.description,
        status: ticket.status,
        priority: ticket.priority,
        tags: ticket.tags,
        ticket_type: ticket.ticket_type,
        due_at: ticket.due_at,
        reminder_at: ticket.reminder_at,
        reminder_repeat: ticket.reminder_repeat,
        created_at: ticket.created_at,
        updated_at: ticket.updated_at
      }
    end

    def self.user(user)
      {
        id: user.id,
        name: user.name,
        email: user.email,
        role: user.role_label
      }
    end
  end
end
