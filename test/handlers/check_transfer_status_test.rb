require "test_helper"
require_relative "../../app/handlers/check_transfer_status"

class CheckTransferStatusTest < ActiveSupport::TestCase
  def setup
    @circuit_breaker = CircuitBreaker.new
    @transfer = transfers(:pending_transfer)
    @transfer.update!(sunabar_apply_no: "APL-001", status: "requested")
    @event =
      OutboxEvent.create!(
        aggregate_type: "Transfer",
        aggregate_id: @transfer.id_for_payload,
        event_type: "TransferStatusCheckScheduled",
        payload: {
          "transfer_id" => @transfer.id_for_payload
        },
        next_attempt_at: Time.current
      )
  end

  # スタブクライアント: 指定ステータスを返す
  def stub_client(status)
    client = Object.new
    client.define_singleton_method(:get_transfer_status) do |apply_no:|
      { status: status }
    end
    client
  end

  def build_handler(client: nil)
    client ||= stub_client("Settled")
    Handlers::CheckTransferStatus.new(
      circuit_breaker: @circuit_breaker,
      client: client
    )
  end

  # --- 正常系: 終端ステータス(settled) ---

  test "Settledの場合はtransferをsettledに遷移し:successを返す" do
    # Arrange
    handler = build_handler(client: stub_client("Settled"))

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :success, result
    assert_equal "settled", @transfer.reload.status
  end

  test "Settledの場合はTransferSettledイベントを発行する" do
    # Arrange
    handler = build_handler(client: stub_client("Settled"))
    event_count_before = OutboxEvent.count

    # Act
    handler.call(@event)

    # Assert
    assert_equal 1, OutboxEvent.count - event_count_before
    latest = OutboxEvent.order(created_at: :desc).first
    assert_equal "TransferSettled", latest.event_type
  end

  # --- 正常系: 終端ステータス(failed) ---

  test "Failedの場合はtransferをfailedに遷移し:successを返す" do
    # Arrange
    handler = build_handler(client: stub_client("Failed"))

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :success, result
    assert_equal "failed", @transfer.reload.status
  end

  test "Failedの場合はTransferFailedイベントを発行する" do
    # Arrange
    handler = build_handler(client: stub_client("Failed"))

    # Act
    handler.call(@event)

    # Assert
    latest = OutboxEvent.order(created_at: :desc).first
    assert_equal "TransferFailed", latest.event_type
  end

  test "Rejectedの場合もfailedに遷移する" do
    # Arrange
    handler = build_handler(client: stub_client("Rejected"))

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :success, result
    assert_equal "failed", @transfer.reload.status
  end

  # --- 正常系: 非終端ステータス(awaiting_approval) ---

  test "AwaitingApprovalの場合はステータスを更新し:still_in_flightを返す" do
    # Arrange
    handler = build_handler(client: stub_client("AwaitingApproval"))

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :still_in_flight, result
    assert_equal "awaiting_approval", @transfer.reload.status
  end

  test "AwaitingApprovalの場合はTransferAwaitingApprovalイベントを発行する" do
    # Arrange
    handler = build_handler(client: stub_client("AwaitingApproval"))

    # Act
    handler.call(@event)

    # Assert
    latest = OutboxEvent.order(created_at: :desc).first
    assert_equal "TransferAwaitingApproval", latest.event_type
  end

  # --- 正常系: 非終端ステータス(approved) ---

  test "Approvedの場合はステータスを更新し:still_in_flightを返す" do
    # Arrange
    handler = build_handler(client: stub_client("Approved"))

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :still_in_flight, result
    assert_equal "approved", @transfer.reload.status
  end

  # --- ステータス変更なし ---

  test "同じ非終端ステータスの場合はステータスを更新せず:still_in_flightを返す" do
    # Arrange
    @transfer.update!(status: "awaiting_approval")
    handler = build_handler(client: stub_client("AwaitingApproval"))
    event_count_before = OutboxEvent.count

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :still_in_flight, result
    # イベントは発行されない
    assert_equal 0, OutboxEvent.count - event_count_before
  end

  # --- 既に終端ステータスの場合 ---

  test "transferが既にsettledの場合は:successを返す" do
    # Arrange
    @transfer.update_columns(status: "settled")
    handler = build_handler

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :success, result
  end

  test "transferが既にfailedの場合は:successを返す" do
    # Arrange
    @transfer.update_columns(status: "failed")
    handler = build_handler

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :success, result
  end

  # --- CircuitBreaker OPEN ---

  test "CircuitBreakerがOPENの場合は:skip_attemptを返す" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 1)
    cb.record_failure
    handler =
      Handlers::CheckTransferStatus.new(
        circuit_breaker: cb,
        client: stub_client("Settled")
      )

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :skip_attempt, result
  end

  # --- 不明なsunabarステータス ---

  test "不明なsunabarステータスの場合は:non_retryableを返す" do
    # Arrange
    handler = build_handler(client: stub_client("UnknownStatus"))

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :non_retryable, result
    assert_match(/不明なsunabarステータス/, @transfer.reload.last_error)
  end

  # --- リトライ可能なエラー ---

  test "RateLimitErrorの場合は:retryableを返しCircuitBreakerに記録する" do
    # Arrange
    client = Object.new
    client.define_singleton_method(:get_transfer_status) do |apply_no:|
      raise SunabarErrors::RateLimitError, "429 rate limited"
    end
    handler =
      Handlers::CheckTransferStatus.new(
        circuit_breaker: @circuit_breaker,
        client: client
      )

    # Act
    result = handler.call(@event)

    # Assert
    status, message = result
    assert_equal :retryable, status
    assert_match(/429/, message)
    assert_match(/429/, @transfer.reload.last_error)
  end

  test "ServerErrorの場合は:retryableを返す" do
    # Arrange
    client = Object.new
    client.define_singleton_method(:get_transfer_status) do |apply_no:|
      raise SunabarErrors::ServerError, "500 internal"
    end
    handler =
      Handlers::CheckTransferStatus.new(
        circuit_breaker: @circuit_breaker,
        client: client
      )

    # Act
    result = handler.call(@event)

    # Assert
    status, _message = result
    assert_equal :retryable, status
  end

  test "TimeoutErrorの場合は:retryableを返す" do
    # Arrange
    client = Object.new
    client.define_singleton_method(:get_transfer_status) do |apply_no:|
      raise SunabarErrors::TimeoutError, "timeout"
    end
    handler =
      Handlers::CheckTransferStatus.new(
        circuit_breaker: @circuit_breaker,
        client: client
      )

    # Act
    result = handler.call(@event)

    # Assert
    status, _message = result
    assert_equal :retryable, status
  end

  test "ConnectionErrorの場合は:retryableを返す" do
    # Arrange
    client = Object.new
    client.define_singleton_method(:get_transfer_status) do |apply_no:|
      raise SunabarErrors::ConnectionError, "connection refused"
    end
    handler =
      Handlers::CheckTransferStatus.new(
        circuit_breaker: @circuit_breaker,
        client: client
      )

    # Act
    result = handler.call(@event)

    # Assert
    status, _message = result
    assert_equal :retryable, status
  end

  # --- ClientError ---

  test "ClientErrorの場合はtransferをfailedに遷移し:non_retryableを返す" do
    # Arrange
    client = Object.new
    client.define_singleton_method(:get_transfer_status) do |apply_no:|
      raise SunabarErrors::ClientError, "400 bad request"
    end
    handler =
      Handlers::CheckTransferStatus.new(
        circuit_breaker: @circuit_breaker,
        client: client
      )

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :non_retryable, result
    assert_equal "failed", @transfer.reload.status
    assert_match(/400/, @transfer.last_error)
  end

  test "ClientErrorの場合はTransferFailedイベントを発行する" do
    # Arrange
    client = Object.new
    client.define_singleton_method(:get_transfer_status) do |apply_no:|
      raise SunabarErrors::ClientError, "400 bad request"
    end
    handler =
      Handlers::CheckTransferStatus.new(
        circuit_breaker: @circuit_breaker,
        client: client
      )

    # Act
    handler.call(@event)

    # Assert
    latest = OutboxEvent.order(created_at: :desc).first
    assert_equal "TransferFailed", latest.event_type
  end
end
