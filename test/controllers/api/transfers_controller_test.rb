require "test_helper"

class Api::TransfersControllerTest < ActionDispatch::IntegrationTest
  def valid_transfer_params
    {
      transfer: {
        app_request_id: "REQ-#{SecureRandom.hex(8)}",
        account_id: accounts(:sunabar_main).id,
        destination_bank_code: "0310",
        destination_branch_code: "101",
        destination_account_number: "9876543",
        destination_account_type: "ordinary",
        destination_account_name: "テスト受取人",
        amount: 5000
      }
    }
  end

  # --- POST /api/transfers ---

  test "POST /api/transfersは有効なパラメータで201を返す" do
    # Arrange
    params = valid_transfer_params

    # Act
    post api_transfers_path, params: params, as: :json

    # Assert
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "pending", body["status"]
    assert_equal 5000, body["amount"]
  end

  test "POST /api/transfersは同じapp_request_idで200を返す(冪等)" do
    # Arrange
    params = valid_transfer_params

    # Act
    post api_transfers_path, params: params, as: :json
    assert_response :created

    post api_transfers_path, params: params, as: :json

    # Assert
    assert_response :ok
  end

  # --- GET /api/transfers ---

  test "GET /api/transfersはページネーション付きリストを返す" do
    # Arrange
    transfers(:pending_transfer) # fixture loads

    # Act
    get api_transfers_path, as: :json

    # Assert
    assert_response :ok
    body = JSON.parse(response.body)
    assert body.key?("data")
    assert body.key?("pagination")
    assert body["pagination"]["total_count"] >= 1
  end

  # --- GET /api/transfers/:id ---

  test "GET /api/transfers/:idはtransferを返す" do
    # Arrange
    transfer = transfers(:pending_transfer)

    # Act
    get api_transfer_path(transfer), as: :json

    # Assert
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "pending", body["status"]
  end

  test "GET /api/transfers/:idは存在しないIDで404を返す" do
    # Arrange
    bad_id = SecureRandom.uuid

    # Act
    get api_transfer_path(id: bad_id), as: :json

    # Assert
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body.dig("error", "code")
  end
end
