require "test_helper"

class Admin::TransfersControllerTest < ActionDispatch::IntegrationTest
  def admin_auth_headers
    {
      "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials(
          "admin",
          "changeme"
        )
    }
  end

  # --- GET /admin/transfers ---

  test "GET /admin/transfersは振込一覧を表示する" do
    # Arrange
    transfers(:pending_transfer)

    # Act
    get admin_transfers_path, headers: admin_auth_headers

    # Assert
    assert_response :ok
  end

  test "GET /admin/transfersはステータスでフィルタリングできる" do
    # Arrange
    transfers(:pending_transfer)

    # Act
    get admin_transfers_path,
        params: {
          status: "pending"
        },
        headers: admin_auth_headers

    # Assert
    assert_response :ok
  end

  test "GET /admin/transfersは認証なしで401を返す" do
    # Act
    get admin_transfers_path

    # Assert
    assert_response :unauthorized
  end

  # --- GET /admin/transfers/:id ---

  test "GET /admin/transfers/:idは振込詳細を表示する" do
    # Arrange
    transfer = transfers(:pending_transfer)

    # Act
    get admin_transfer_path(transfer), headers: admin_auth_headers

    # Assert
    assert_response :ok
  end
end
