module Helpdesk
  class EventSubscription
    attr_reader :events

    def self.normalize(events)
      Array(events).flat_map { |event| event.to_s.split(",") }.map { |event| event.strip }.reject(&:empty?).uniq.sort
    end

    def initialize(events)
      @events = self.class.normalize(events)
    end

    def include?(event)
      event = event.to_s.strip
      return true if events.empty?
      return true if events.include?("*")
      return true if events.include?(event)

      events.any? do |subscribed|
        subscribed.end_with?("*") && event.start_with?(subscribed.delete_suffix("*"))
      end
    end
  end
end
