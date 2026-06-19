require "test_helper"

class OutboxEventTest < ActiveSupport::TestCase
  def create_event(overrides = {})
    OutboxEvent.create!(
      {
        aggregate_type: "Transfer",
        aggregate_id: SecureRandom.uuid,
        event_type: "TransferRequested",
        payload: {
          transfer_id: SecureRandom.uuid
        },
        next_attempt_at: Time.current,
        status: "pending"
      }.merge(overrides)
    )
  end

  # --- mark_sent! ---

  test "mark_sent!はstatusをsentに更新しsent_atを設定する" do
    # Arrange
    event = create_event

    # Act
    event.mark_sent!

    # Assert
    assert_equal "sent", event.status
    assert_not_nil event.sent_at
  end

  # --- record_retryable_error! ---

  test "record_retryable_error!はattempt_countをインクリメントしnext_attempt_atをバックオフ付きで設定する" do
    # Arrange
    event = create_event
    before_time = Time.current

    # Act
    event.record_retryable_error!("server error")

    # Assert
    assert_equal 1, event.attempt_count
    assert_equal "pending", event.status
    assert_equal "server error", event.last_error
    assert event.next_attempt_at > before_time
  end

  test "record_retryable_error!はmax_attempts到達時にfailedに遷移する" do
    # Arrange
    event = create_event(attempt_count: 9, max_attempts: 10)

    # Act
    event.record_retryable_error!("final failure")

    # Assert
    assert_equal "failed", event.status
    assert_equal 10, event.attempt_count
    assert_equal "final failure", event.last_error
  end

  # --- record_still_in_flight! ---

  test "record_still_in_flight!はattempt_countをインクリメントする" do
    # Arrange
    event = create_event

    # Act
    event.record_still_in_flight!

    # Assert
    assert_equal 1, event.attempt_count
    assert_equal "pending", event.status
  end

  # --- record_skip_attempt! ---

  test "record_skip_attempt!はattempt_countをインクリメントせずnext_attempt_atを5秒後に設定する" do
    # Arrange
    event = create_event(attempt_count: 3)
    before_time = Time.current

    # Act
    event.record_skip_attempt!

    # Assert
    assert_equal 3, event.attempt_count
    assert_in_delta before_time + 5, event.next_attempt_at, 2
  end

  # --- pending_dispatchable scope ---

  test "pending_dispatchableはpendingかつnext_attempt_atが現在以前のイベントを返す" do
    # Arrange
    dispatchable = create_event(next_attempt_at: 1.minute.ago)
    _future = create_event(next_attempt_at: 1.hour.from_now)
    _sent = create_event(status: "sent", next_attempt_at: 1.minute.ago)

    # Act
    results = OutboxEvent.pending_dispatchable

    # Assert
    assert_includes results, dispatchable
    assert_not results.any? { |e| e.status == "sent" }
    assert_not results.any? { |e| e.next_attempt_at > Time.current }
  end

  # --- backoff cap ---

  test "バックオフは600秒でキャップされる" do
    # Arrange
    event = create_event(attempt_count: 19, max_attempts: 30)
    before_time = Time.current

    # Act
    event.record_retryable_error!("error")

    # Assert
    max_expected = before_time + OutboxEvent::BACKOFF_CAP + 2
    assert event.next_attempt_at <= max_expected,
           "next_attempt_atがバックオフキャップ(#{OutboxEvent::BACKOFF_CAP}秒)を超えている"
  end
end
