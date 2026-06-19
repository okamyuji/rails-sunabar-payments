require "test_helper"

class Api::VirtualAccountsControllerTest < ActionDispatch::IntegrationTest
  # --- GET /api/virtual_accounts ---

  test "GET /api/virtual_accountsはページネーション付きリストを返す" do
    # Arrange
    virtual_accounts(:test_va) # fixture読み込み

    # Act
    get api_virtual_accounts_path, as: :json

    # Assert
    assert_response :ok
    body = JSON.parse(response.body)
    assert body.key?("data")
    assert body.key?("pagination")
    assert body["pagination"]["total_count"] >= 1
  end

  # --- POST /api/virtual_accounts ---

  test "POST /api/virtual_accountsは仮想口座を作成する" do
    # Arrange
    account = accounts(:sunabar_main)
    setup_sunabar_client!
    stub_request(:post, %r{/corporation/v1/va/issue}).to_return(
      status: 200,
      body: { vaId: "VA-NEW-001", vaNumber: "5555555" }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )

    # Act
    post api_virtual_accounts_path,
         params: {
           account_id: account.id,
           va_name: "テストVA"
         },
         as: :json

    # Assert
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal "VA-NEW-001", body["sunabar_va_id"]
  end

  test "POST /api/virtual_accountsは存在しないaccount_idで404を返す" do
    # Arrange
    bad_id = SecureRandom.uuid

    # Act
    post api_virtual_accounts_path,
         params: {
           account_id: bad_id,
           va_name: "テスト"
         },
         as: :json

    # Assert
    assert_response :not_found
  end
end
