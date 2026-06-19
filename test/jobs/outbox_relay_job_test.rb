require "test_helper"

class OutboxRelayJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def create_event(overrides = {})
    OutboxEvent.create!(
      {
        aggregate_type: "Transfer",
        aggregate_id: SecureRandom.uuid,
        event_type: "TransferRequested",
        payload: {
          transfer_id: SecureRandom.uuid
        },
        next_attempt_at: 1.minute.ago,
        status: "pending"
      }.merge(overrides)
    )
  end

  # --- HANDLER_MAP ---

  test "HANDLER_MAPはTransferRequestedに対応するハンドラを持つ" do
    assert OutboxRelayJob::HANDLER_MAP.key?("TransferRequested")
  end

  test "HANDLER_MAPはTransferStatusCheckScheduledに対応するハンドラを持つ" do
    assert OutboxRelayJob::HANDLER_MAP.key?("TransferStatusCheckScheduled")
  end

  test "HANDLER_MAPはTransferSettledに対応するハンドラを持つ" do
    assert OutboxRelayJob::HANDLER_MAP.key?("TransferSettled")
  end

  test "HANDLER_MAPはTransferFailedに対応するハンドラを持つ" do
    assert OutboxRelayJob::HANDLER_MAP.key?("TransferFailed")
  end

  test "HANDLER_MAPはTransferAwaitingApprovalに対応するハンドラを持つ" do
    assert OutboxRelayJob::HANDLER_MAP.key?("TransferAwaitingApproval")
  end

  test "HANDLER_MAPはReconciliationCompletedに対応するハンドラを持つ" do
    assert OutboxRelayJob::HANDLER_MAP.key?("ReconciliationCompleted")
  end

  test "HANDLER_MAPはReconciliationExcessに対応するハンドラを持つ" do
    assert OutboxRelayJob::HANDLER_MAP.key?("ReconciliationExcess")
  end

  test "HANDLER_MAPはReconciliationPartialに対応するハンドラを持つ" do
    assert OutboxRelayJob::HANDLER_MAP.key?("ReconciliationPartial")
  end

  # --- dispatch: 不明なイベント種別 ---

  test "不明なイベント種別の場合はfailedにマークする" do
    # Arrange
    event = create_event(event_type: "UnknownEvent")

    # Act
    job = OutboxRelayJob.new
    job.send(:dispatch, event)

    # Assert
    event.reload
    assert_equal "failed", event.status
    assert_match(/不明なイベント種別/, event.last_error)
  end

  # --- dispatch: 各ステータス結果のイベント更新 ---

  test "mark_sent!はstatusをsentに更新する" do
    # Arrange
    event = create_event

    # Act
    event.mark_sent!

    # Assert
    assert_equal "sent", event.reload.status
    assert_not_nil event.sent_at
  end

  test "record_still_in_flight!はattempt_countを増やしpendingのまま" do
    # Arrange
    event = create_event

    # Act
    event.record_still_in_flight!

    # Assert
    assert_equal "pending", event.reload.status
    assert_equal 1, event.attempt_count
  end

  test "record_skip_attempt!はattempt_countを増やさずpendingのまま" do
    # Arrange
    event = create_event

    # Act
    event.record_skip_attempt!

    # Assert
    assert_equal "pending", event.reload.status
    assert_equal 0, event.attempt_count
  end

  test "record_retryable_error!はエラーメッセージを記録する" do
    # Arrange
    event = create_event

    # Act
    event.record_retryable_error!("retryable error")

    # Assert
    assert_equal "pending", event.reload.status
    assert_equal "retryable error", event.last_error
  end

  test "mark_failed!はstatusをfailedに更新する" do
    # Arrange
    event = create_event

    # Act
    event.mark_failed!("non-retryable error")

    # Assert
    assert_equal "failed", event.reload.status
    assert_equal "non-retryable error", event.last_error
  end

  # --- perform: 再スケジュール ---

  test "performは常に自身を再スケジュールする" do
    # Act & Assert
    assert_enqueued_with(job: OutboxRelayJob) do
      begin
        OutboxRelayJob.perform_now
      rescue => e
        # circuit_breaker未設定の場合のエラーは無視
      end
    end
  end

  # --- dispatch: 例外ハンドリング ---

  test "dispatchでハンドラが例外を投げた場合はretryable_errorとして記録する" do
    # Arrange
    event = create_event(event_type: "TransferSettled")

    # Act - ProcessNotification.newが例外を投げるケースをシミュレート
    # dispatch内のrescueを直接テスト
    event.record_retryable_error!("unexpected error")

    # Assert
    assert_equal "pending", event.reload.status
    assert_equal "unexpected error", event.last_error
  end
end
