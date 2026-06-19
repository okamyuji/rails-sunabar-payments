require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  def admin_auth_headers
    {
      "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials(
          "admin",
          "changeme"
        )
    }
  end

  # --- GET /admin ---

  test "GET /adminは認証成功時にダッシュボードを表示する" do
    # Act
    get admin_path, headers: admin_auth_headers

    # Assert
    assert_response :ok
  end

  test "GET /adminは認証なしで401を返す" do
    # Act
    get admin_path

    # Assert
    assert_response :unauthorized
  end

  test "GET /adminは不正な認証情報で401を返す" do
    # Arrange
    bad_headers = {
      "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials(
          "wrong",
          "wrong"
        )
    }

    # Act
    get admin_path, headers: bad_headers

    # Assert
    assert_response :unauthorized
  end
end
