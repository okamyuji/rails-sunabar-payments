require "test_helper"
require_relative "../../app/handlers/send_to_sunabar"

class SendToSunabarTest < ActiveSupport::TestCase
  def setup
    @circuit_breaker = CircuitBreaker.new
    @account = accounts(:sunabar_main)
    @transfer =
      Transfer.create_with_outbox!(
        account_id: @account.id,
        app_request_id: "REQ-#{SecureRandom.hex(8)}",
        amount: 5000,
        destination_bank_code: "0310",
        destination_branch_code: "101",
        destination_account_number: "9876543",
        destination_account_type: "ordinary",
        destination_account_name: "テスト受取人"
      )
    @event = OutboxEvent.last
  end

  def build_handler(circuit_breaker: @circuit_breaker)
    Handlers::SendToSunabar.new(
      circuit_breaker: circuit_breaker,
      client: sunabar_client
    )
  end

  def sunabar_client
    @sunabar_client ||=
      begin
        ENV["SUNABAR_PERSONAL_TOKEN"] ||= "test-token"
        ENV["SUNABAR_CORPORATE_TOKEN"] ||= "test-token"
        SunabarClient.new
      end
  end

  # --- successful send ---

  test "成功時にtransferをrequestedに遷移しTransferStatusCheckScheduledイベントを作成する" do
    # Arrange
    stub_request_transfer(apply_no: "APL-200")
    handler = build_handler

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :success, result
    @transfer.reload
    assert_equal "requested", @transfer.status
    assert_equal "APL-200", @transfer.sunabar_apply_no

    scheduled_event =
      OutboxEvent.find_by(event_type: "TransferStatusCheckScheduled")
    assert_not_nil scheduled_event
  end

  # --- 4xx error ---

  test "4xxエラー時にtransferをfailedに遷移しnon_retryableを返す" do
    # Arrange
    stub_request(:post, %r{/personal/v1/transfer/request}).to_return(
      status: 400,
      body: { error: "bad request" }.to_json
    )
    handler = build_handler

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :non_retryable, result
    assert_equal "failed", @transfer.reload.status
  end

  # --- 5xx error ---

  test "5xxエラー時にretryableとメッセージを返しCB失敗を記録する" do
    # Arrange
    stub_request(:post, %r{/personal/v1/transfer/request}).to_return(
      status: 500,
      body: { error: "internal" }.to_json
    )
    handler = build_handler

    # Act
    result = handler.call(@event)

    # Assert
    assert_instance_of Array, result
    assert_equal :retryable, result[0]
    assert_not_nil result[1]
    assert_equal CircuitBreaker::CLOSED, @circuit_breaker.state
  end

  # --- Circuit Breaker OPEN ---

  test "CB OPEN時にAPIを呼ばずskip_attemptを返す" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 1)
    cb.record_failure(Time.current)
    handler = build_handler(circuit_breaker: cb)

    # Act
    result = handler.call(@event)

    # Assert
    assert_equal :skip_attempt, result
    assert_equal "pending", @transfer.reload.status
  end
end
