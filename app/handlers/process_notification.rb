module Handlers
  class ProcessNotification
    def initialize(sender: NotificationSender.new)
      @sender = sender
    end

    def call(event)
      inserted =
        EventProcessed.mark_processed!(
          outbox_event_id: event.id,
          consumer: "notification"
        )
      return :success unless inserted

      @sender.send_notification(
        event_type: event.event_type,
        payload: event.payload
      )
      :success
    end
  end
end
