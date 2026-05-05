require "test_helper"

class IntegrationStoreTest < Minitest::Test
  def test_hook_matching_understands_wildcards_and_enabled_state
    with_tmpdir do |dir|
      store = Helpdesk::HookStore.new(path: File.join(dir, "hooks.json"))
      store.create(name: "ticket hooks", events: ["ticket.*"], command: "echo {{event}}")
      store.create(name: "disabled", events: ["ticket.created"], command: "echo no", enabled: false)

      matches = store.matching("ticket.created")

      assert_equal ["ticket hooks"], matches.map { |hook| hook["name"] }
    end
  end

  def test_webhook_matching_understands_exact_and_wildcard_subscriptions
    with_tmpdir do |dir|
      store = Helpdesk::WebhookStore.new(path: File.join(dir, "webhooks.json"))
      exact = store.create(name: "exact", url: "https://example.test/exact", events: ["ticket.created"])
      wildcard = store.create(name: "all tickets", url: "https://example.test/all", events: ["ticket.*"])

      assert_equal [exact["id"]], store.matching("ticket.created").select { |row| row["name"] == "exact" }.map { |row| row["id"] }
      assert_equal [wildcard["id"]], store.matching("ticket.closed").map { |row| row["id"] }
    end
  end
end
