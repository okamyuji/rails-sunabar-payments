module Outboxable
  extend ActiveSupport::Concern

  # ビジネスデータと同一トランザクション内で呼び出すこと(Outboxパターンの原子性保証)
  def publish_outbox_event!(event_type:, payload: {})
    OutboxEvent.create!(
      aggregate_type: self.class.name,
      aggregate_id: respond_to?(:id_for_payload) ? id_for_payload : id.to_s,
      event_type: event_type,
      payload: payload,
      next_attempt_at: Time.current
    )
  end
end
