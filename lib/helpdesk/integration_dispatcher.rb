require "json"
require "time"
require "helpdesk/shell_command_runner"

module Helpdesk
  class IntegrationDispatcher
    MAX_WEBHOOK_ATTEMPTS = 3

    def initialize(hooks:, webhooks:, audit_log:, shell: ShellCommandRunner.new)
      @hooks = hooks
      @webhooks = webhooks
      @audit_log = audit_log
      @shell = shell
    end

    def dispatch(action, actor, subject, details)
      dispatch_hooks(action, actor, subject, details)
      dispatch_webhooks(action, actor, subject, details)
    end

    def dispatch_hooks(action, actor, subject, details)
      return if @hooks.nil?

      @hooks.matching(action).each do |hook|
        deliver_hook(hook, payload(action, subject, details, actor: actor))
      end
    end

    def dispatch_webhooks(action, actor, subject, details)
      return if @webhooks.nil?

      @webhooks.matching(action).each do |webhook|
        deliver_webhook(webhook, payload(action, subject, details, actor: actor))
      end
    end

    def payload(action, subject, details, actor:)
      {
        "action" => action,
        "subject" => subject,
        "actor" => actor,
        "details" => details,
        "created_at" => Time.now.utc.iso8601
      }
    end

    def deliver_hook(hook, hook_payload)
      command = hook["command"].to_s.strip
      env = {
        "HELPDESK_HOOK_ID" => hook["id"].to_s,
        "HELPDESK_HOOK_NAME" => hook["name"].to_s,
        "HELPDESK_HOOK_EVENT" => hook_payload["action"].to_s,
        "HELPDESK_HOOK_SUBJECT" => hook_payload["subject"].to_s,
        "HELPDESK_HOOK_ACTOR" => hook_payload["actor"].to_s,
        "HELPDESK_HOOK_DETAILS" => JSON.generate(hook_payload["details"] || {}),
        "HELPDESK_HOOK_PAYLOAD" => JSON.generate(hook_payload)
      }

      puts "[hook mock] Running hook ##{hook["id"]} #{hook["name"]}: #{command}"
      result = @shell.run(env, command)
      if result.success
        puts "[hook mock] Completed."
      else
        puts "[hook mock] Failed#{result.exit_status ? " (exit #{result.exit_status})" : ""}."
      end

      @audit_log.append(
        action: "hook.trigger",
        actor: hook_payload["actor"],
        subject: "hook ##{hook["id"]}",
        details: {
          event: hook_payload["action"],
          target: hook_payload["subject"],
          success: result.success
        }
      )
      result.success
    end

    def deliver_webhook(webhook, webhook_payload)
      MAX_WEBHOOK_ATTEMPTS.times do |attempt_index|
        attempt = attempt_index + 1
        puts "[webhook mock] Attempt #{attempt}/#{MAX_WEBHOOK_ATTEMPTS} POST #{webhook["url"]}"
        puts "[webhook mock] Webhook ##{webhook["id"]} #{webhook["name"]}"
        puts "[webhook mock] Event: #{webhook_payload["action"]}"
        puts "[webhook mock] Payload: #{JSON.generate(webhook_payload)}"

        if webhook_delivery_succeeds?(webhook, webhook_payload, attempt)
          puts "[webhook mock] Delivered."
          return true
        end

        if attempt < MAX_WEBHOOK_ATTEMPTS
          puts "[webhook mock] Delivery failed, retrying..."
        else
          puts "[webhook mock] Delivery failed after #{MAX_WEBHOOK_ATTEMPTS} attempts."
        end
      end

      false
    end

    def webhook_delivery_succeeds?(webhook, webhook_payload, attempt)
      url = webhook["url"].to_s
      mode = webhook_payload.dig("details", "mode").to_s

      return false if mode == "fail"
      return attempt >= 3 if mode == "flaky"
      return false if url.include?("fail")
      return attempt >= 3 if url.include?("flaky")

      true
    end
    private :webhook_delivery_succeeds?
  end
end
