require "test_helper"

class EventProcessedTest < ActiveSupport::TestCase
  def create_outbox_event
    OutboxEvent.create!(
      aggregate_type: "Transfer",
      aggregate_id: SecureRandom.uuid,
      event_type: "TransferRequested",
      payload: {
        transfer_id: SecureRandom.uuid
      },
      next_attempt_at: Time.current
    )
  end

  # --- already_processed? ---

  test "already_processed?は未処理のときfalseを返し処理後にtrueを返す" do
    # Arrange
    event = create_outbox_event
    consumer = "test_consumer"

    # Act & Assert
    assert_not EventProcessed.already_processed?(
                 outbox_event_id: event.id,
                 consumer: consumer
               )

    EventProcessed.mark_processed!(
      outbox_event_id: event.id,
      consumer: consumer
    )

    assert EventProcessed.already_processed?(
             outbox_event_id: event.id,
             consumer: consumer
           )
  end

  # --- mark_processed! idempotency ---

  test "mark_processed!は重複呼び出しでもエラーにならない" do
    # Arrange
    event = create_outbox_event
    consumer = "test_consumer"

    # Act & Assert - no error raised
    EventProcessed.mark_processed!(
      outbox_event_id: event.id,
      consumer: consumer
    )

    assert_nothing_raised do
      EventProcessed.mark_processed!(
        outbox_event_id: event.id,
        consumer: consumer
      )
    end
  end
end
