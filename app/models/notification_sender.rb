class NotificationSender
  def send_notification(event_type:, payload:)
    Rails.logger.info(
      {
        event: "notification_sent",
        event_type: event_type,
        payload: payload
      }.to_json
    )
  end
end
