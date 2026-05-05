require "test_helper"

class TicketTest < Minitest::Test
  def setup
    reset_ticket_rules!
  end

  def test_normalizes_ticket_fields_and_nested_records
    ticket = Helpdesk::Ticket.new(
      title: "Printer broken",
      priority: "",
      tags: ["hardware", " hardware ", ""],
      comments: [{ body: "First note", author: "" }],
      attachments: [{ name: "photo.png", size: "42" }],
      custom_fields: { " floor " => 3, "" => "ignored" },
      due_at: "2026-05-05"
    ).normalize!

    assert_equal "general", ticket.ticket_type
    assert_equal "open", ticket.status
    assert_equal "medium", ticket.priority
    assert_equal ["hardware"], ticket.tags
    assert_equal "First note", ticket.comments.first["body"]
    assert_equal "photo.png", ticket.attachments.first["name"]
    assert_equal 42, ticket.attachments.first["size"]
    assert_equal({ "floor" => "3" }, ticket.custom_fields)
    assert_equal "2026-05-05", ticket.due_at
  end

  def test_enforces_type_specific_validation_and_recurring_reminders
    ticket = Helpdesk::Ticket.new(
      title: "Checkout fails",
      ticket_type: "bug",
      reminder_at: "2026-05-05 10:00 UTC",
      reminder_repeat: "weekly"
    ).normalize!

    assert_equal ["bug tickets require a severity field"], ticket.validation_errors

    ticket.advance_reminder!
    assert_equal "2026-05-12T10:00:00Z", ticket.reminder_at
  end
end
