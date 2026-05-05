require "test_helper"

class ApiTokenStoreTest < Minitest::Test
  def test_creates_normalized_tokens_and_enforces_rate_window
    with_tmpdir do |dir|
      store = Helpdesk::ApiTokenStore.new(path: File.join(dir, "tokens.json"))
      token = store.create(name: "cli", user_id: 12, scopes: ["tickets, users", "tickets"])

      assert_equal "cli", token["name"]
      assert_equal 12, token["user_id"]
      assert_equal ["tickets", "users"], token["scopes"]
      assert_equal true, token["enabled"]

      first = store.consume!(token["token"], limit: 1, window_seconds: 60)
      second = store.consume!(token["token"], limit: 1, window_seconds: 60)

      assert_equal true, first[:allowed]
      assert_equal 0, first[:remaining]
      assert_equal false, second[:allowed]
      assert_equal 0, second[:remaining]
    end
  end

  def test_revokes_tokens_through_record_contract
    with_tmpdir do |dir|
      store = Helpdesk::ApiTokenStore.new(path: File.join(dir, "tokens.json"))
      token = store.create(name: "cli", user_id: 12)

      revoked = store.revoke(token["id"])

      assert_equal false, revoked["enabled"]
      refute_nil revoked["updated_at"]
    end
  end
end
