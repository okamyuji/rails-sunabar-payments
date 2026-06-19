require "test_helper"

class Api::AccountsControllerTest < ActionDispatch::IntegrationTest
  # --- GET /api/accounts ---

  test "GET /api/accountsはページネーション付きリストを返す" do
    # Arrange
    accounts(:sunabar_main) # fixture読み込み

    # Act
    get api_accounts_path, as: :json

    # Assert
    assert_response :ok
    body = JSON.parse(response.body)
    assert body.key?("data")
    assert body.key?("pagination")
    assert body["pagination"]["total_count"] >= 1
  end

  # --- GET /api/accounts/:id ---

  test "GET /api/accounts/:idはアカウント情報と残高を返す" do
    # Arrange
    account = accounts(:sunabar_main)
    setup_sunabar_client!
    stub_request(:get, %r{/personal/v1/accounts/balances}).to_return(
      status: 200,
      body: { balance: 100_000 }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )

    # Act
    get api_account_path(account), as: :json

    # Assert
    assert_response :ok
    body = JSON.parse(response.body)
    assert body.key?("balance")
  end

  test "GET /api/accounts/:idは存在しないIDで404を返す" do
    # Arrange
    bad_id = SecureRandom.uuid

    # Act
    get api_account_path(id: bad_id), as: :json

    # Assert
    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "not_found", body.dig("error", "code")
  end

  # --- POST /api/accounts/sync ---

  test "POST /api/accounts/syncはアカウント同期を実行する" do
    # Arrange
    setup_sunabar_client!
    stub_list_accounts

    # Act
    post api_accounts_sync_path, as: :json

    # Assert
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "同期完了", body["message"]
  end
end
