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

  test "GET /adminは振込と請求書の状態別件数を別々の行に表示する" do
    # Act
    get admin_path, headers: admin_auth_headers

    # Assert
    rows = css_select("div.grid.md\\:grid-cols-4")
    assert_equal 2, rows.size
    cards = rows.map { |row| row.css("div.shadow").map { |c| c.text.squish } }
    assert_equal [["振込 / pending 1"], ["請求書 / open 1"]], cards
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
