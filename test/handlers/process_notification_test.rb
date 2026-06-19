require "test_helper"
require_relative "../../app/handlers/process_notification"

class ProcessNotificationTest < ActiveSupport::TestCase
  def create_event(event_type: "TransferSettled")
    OutboxEvent.create!(
      aggregate_type: "Transfer",
      aggregate_id: SecureRandom.uuid,
      event_type: event_type,
      payload: {
        transfer_id: SecureRandom.uuid
      },
      next_attempt_at: Time.current
    )
  end

  # 送信記録を追跡するスタブsender
  class TrackingSender
    attr_reader :calls

    def initialize
      @calls = []
    end

    def send_notification(event_type:, payload:)
      @calls << { event_type: event_type, payload: payload }
    end
  end

  # --- 正常系 ---

  test "新規イベントの場合は通知を送信し:successを返す" do
    # Arrange
    sender = TrackingSender.new
    event = create_event
    handler = Handlers::ProcessNotification.new(sender: sender)

    # Act
    result = handler.call(event)

    # Assert
    assert_equal :success, result
    assert_equal 1, sender.calls.size
    assert_equal "TransferSettled", sender.calls.first[:event_type]
  end

  # --- 冪等性: 重複イベント ---

  test "既に処理済みのイベントの場合は通知を送信せず:successを返す" do
    # Arrange
    event = create_event
    EventProcessed.mark_processed!(
      outbox_event_id: event.id,
      consumer: "notification"
    )

    sender = TrackingSender.new
    handler = Handlers::ProcessNotification.new(sender: sender)

    # Act
    result = handler.call(event)

    # Assert
    assert_equal :success, result
    assert_equal 0, sender.calls.size
  end

  # --- イベントタイプごとの通知 ---

  test "TransferFailedイベントで通知が送信される" do
    # Arrange
    sender = TrackingSender.new
    event = create_event(event_type: "TransferFailed")
    handler = Handlers::ProcessNotification.new(sender: sender)

    # Act
    result = handler.call(event)

    # Assert
    assert_equal :success, result
    assert_equal 1, sender.calls.size
    assert_equal "TransferFailed", sender.calls.first[:event_type]
  end

  test "ReconciliationCompletedイベントで通知が送信される" do
    # Arrange
    sender = TrackingSender.new
    event = create_event(event_type: "ReconciliationCompleted")
    handler = Handlers::ProcessNotification.new(sender: sender)

    # Act
    result = handler.call(event)

    # Assert
    assert_equal :success, result
    assert_equal 1, sender.calls.size
    assert_equal "ReconciliationCompleted", sender.calls.first[:event_type]
  end
end
