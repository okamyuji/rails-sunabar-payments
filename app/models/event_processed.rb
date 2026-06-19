class EventProcessed < ApplicationRecord
  self.table_name = "event_processed"
  self.primary_key = %i[outbox_event_id consumer]

  def self.already_processed?(outbox_event_id:, consumer:)
    exists?(outbox_event_id: outbox_event_id, consumer: consumer)
  end

  # insert-first方式。新規挿入ならtrue、重複ならfalse
  def self.mark_processed!(outbox_event_id:, consumer:)
    connection.execute(
      sanitize_sql_array(
        [
          "INSERT IGNORE INTO event_processed (outbox_event_id, consumer, processed_at) VALUES (?, ?, ?)",
          outbox_event_id,
          consumer,
          Time.current
        ]
      )
    )
    connection.raw_connection.affected_rows > 0
  end
end
