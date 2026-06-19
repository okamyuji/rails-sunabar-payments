require "test_helper"

class SunabarClientTest < ActiveSupport::TestCase
  def setup
    ENV["SUNABAR_PERSONAL_TOKEN"] ||= "test-token"
    ENV["SUNABAR_CORPORATE_TOKEN"] ||= "test-token"
    @client = SunabarClient.new
  end

  # --- get_transfer_status ---

  test "get_transfer_statusはステータスを返す" do
    # Arrange
    stub_transfer_status(status: "Settled")

    # Act
    result = @client.get_transfer_status(apply_no: "APL-001")

    # Assert
    assert_equal "Settled", result[:status]
  end

  # --- list_accounts ---

  test "list_accountsはアカウントリストを返す" do
    # Arrange
    stub_list_accounts

    # Act
    result = @client.list_accounts

    # Assert
    assert result[:accounts].is_a?(Array)
    assert_equal "ACC-1", result[:accounts].first[:accountId]
  end

  # --- get_balance ---

  test "get_balanceは残高を返す" do
    # Arrange
    stub_request(:get, %r{/personal/v1/accounts/balances}).to_return(
      status: 200,
      body: { balance: 100_000 }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )

    # Act
    result = @client.get_balance(account_id: "ACC-001")

    # Assert
    assert_equal 100_000, result[:balance]
  end

  # --- list_transactions ---

  test "list_transactionsはパースされたトランザクションリストを返す" do
    # Arrange
    stub_list_transactions(
      transactions: [
        {
          transactionId: "TXN-001",
          amount: "10000",
          senderName: "テスト送金者",
          transactionDate: "2026-06-20"
        }
      ]
    )

    # Act
    result = @client.list_transactions(va_id: "VA-001")

    # Assert
    assert_equal 1, result.size
    assert_equal "TXN-001", result.first[:transaction_id]
    assert_equal 10_000, result.first[:amount]
    assert_equal "テスト送金者", result.first[:sender_name]
  end

  test "list_transactionsはトランザクションがない場合は空配列を返す" do
    # Arrange
    stub_list_transactions(transactions: [])

    # Act
    result = @client.list_transactions(va_id: "VA-001")

    # Assert
    assert_equal [], result
  end

  # --- issue_virtual_account ---

  test "issue_virtual_accountはVA情報を返す" do
    # Arrange
    stub_request(:post, %r{/corporation/v1/va/issue}).to_return(
      status: 200,
      body: { vaId: "VA-NEW-001", vaNumber: "5555555" }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )

    # Act
    result =
      @client.issue_virtual_account(account_id: "ACC-001", va_name: "テストVA")

    # Assert
    assert_equal "VA-NEW-001", result[:vaId]
    assert_equal "5555555", result[:vaNumber]
  end

  # --- request_transfer ---

  test "request_transferは申請番号を返す" do
    # Arrange
    stub_request_transfer(apply_no: "APL-002")

    # Act
    result =
      @client.request_transfer(
        idempotency_key: SecureRandom.uuid,
        account_id: "ACC-001",
        destination_bank_code: "0310",
        destination_branch_code: "101",
        destination_account_number: "1234567",
        destination_account_type: "ordinary",
        destination_account_name: "テスト受取人",
        amount: 5000,
        transfer_date: Date.current
      )

    # Assert
    assert_equal "APL-002", result[:applyNo]
  end

  # --- エラーハンドリング ---

  test "429レスポンスの場合はRateLimitErrorを発生させる" do
    # Arrange
    stub_sunabar_error(status: 429)

    # Act & Assert
    assert_raises(SunabarErrors::RateLimitError) { @client.list_accounts }
  end

  test "400レスポンスの場合はClientErrorを発生させる" do
    # Arrange
    stub_sunabar_error(status: 400)

    # Act & Assert
    assert_raises(SunabarErrors::ClientError) { @client.list_accounts }
  end

  test "500レスポンスの場合はServerErrorを発生させる" do
    # Arrange
    stub_sunabar_error(status: 500)

    # Act & Assert
    assert_raises(SunabarErrors::ServerError) { @client.list_accounts }
  end

  test "タイムアウトの場合はTimeoutErrorまたはConnectionErrorを発生させる" do
    # Arrange
    stub_request(:get, %r{/personal/v1/accounts}).to_raise(
      Faraday::TimeoutError.new("execution expired")
    )

    # Act & Assert
    assert_raises(SunabarErrors::TimeoutError) { @client.list_accounts }
  end

  test "接続失敗の場合はConnectionErrorを発生させる" do
    # Arrange
    stub_request(:get, %r{/personal/v1/accounts}).to_raise(
      Faraday::ConnectionFailed.new("connection refused")
    )

    # Act & Assert
    assert_raises(SunabarErrors::ConnectionError) { @client.list_accounts }
  end

  test "予期しないHTTPステータスの場合はErrorを発生させる" do
    # Arrange
    stub_request(:get, %r{/personal/v1/accounts}).to_return(
      status: 302,
      body: "redirect"
    )

    # Act & Assert
    error = assert_raises(SunabarErrors::Error) { @client.list_accounts }
    assert_match(/予期しないHTTPステータス/, error.message)
  end
end
