require "test_helper"

class Admin::ReconciliationsControllerTest < ActionDispatch::IntegrationTest
  def admin_auth_headers
    {
      "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials(
          "admin",
          "changeme"
        )
    }
  end

  # --- GET /admin/reconciliations ---

  test "GET /admin/reconciliationsは消込一覧を表示する" do
    # Act
    get admin_reconciliations_path, headers: admin_auth_headers

    # Assert
    assert_response :ok
  end

  test "GET /admin/reconciliationsは認証なしで401を返す" do
    # Act
    get admin_reconciliations_path

    # Assert
    assert_response :unauthorized
  end
end
