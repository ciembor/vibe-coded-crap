require "test_helper"

class TicketTest < Minitest::Test
  def setup
    reset_ticket_rules!
  end

  def test_normalizes_core_fields_without_exposing_storage_shape
    ticket = Helpdesk::Ticket.new(
      title: "Printer broken",
      priority: "",
      tags: ["hardware", " hardware ", ""],
      custom_fields: { " floor " => 3, "" => "ignored" },
      due_at: "2026-05-05"
    ).normalize!

    assert_equal "general", ticket.ticket_type
    assert_equal "open", ticket.status
    assert_equal "medium", ticket.priority
    assert_equal ["hardware"], ticket.tags
    assert_equal({ "floor" => "3" }, ticket.custom_fields)
    assert_equal "2026-05-05", ticket.due_at
  end

  def test_adds_ordered_attachments_and_advances_recurring_reminders
    ticket = Helpdesk::Ticket.new(
      title: "Renew certificate",
      reminder_at: "2026-05-05 10:00 UTC",
      reminder_repeat: "weekly"
    ).normalize!

    ticket.add_attachment(name: "cert.txt", size: "42", uploaded_by: "")
    ticket.advance_reminder!

    assert_equal 1, ticket.attachments.length
    assert_equal "cert.txt", ticket.attachments.first["name"]
    assert_equal 42, ticket.attachments.first["size"]
    assert_equal "agent", ticket.attachments.first["uploaded_by"]
    assert_equal "2026-05-12T10:00:00Z", ticket.reminder_at
  end

  def test_rejects_invalid_type_specific_ticket
    ticket = Helpdesk::Ticket.new(
      title: "Checkout fails",
      ticket_type: "bug",
      custom_fields: {}
    ).normalize!

    assert_equal ["bug tickets require a severity field"], ticket.validation_errors
  end
end
