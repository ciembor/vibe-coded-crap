require "time"

module Helpdesk
  class DebugLogger
    attr_accessor :enabled

    def initialize(enabled: false)
      @enabled = enabled
    end

    def log(message)
      return unless enabled

      puts "[debug] #{Time.now.utc.iso8601} #{message}"
    end
  end
end
