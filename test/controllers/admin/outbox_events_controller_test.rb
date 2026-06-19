require "test_helper"

class Admin::OutboxEventsControllerTest < ActionDispatch::IntegrationTest
  def admin_auth_headers
    {
      "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials(
          "admin",
          "changeme"
        )
    }
  end

  # --- GET /admin/outbox_events ---

  test "GET /admin/outbox_eventsはイベント一覧を表示する" do
    # Arrange
    outbox_events(:pending_event)

    # Act
    get admin_outbox_events_path, headers: admin_auth_headers

    # Assert
    assert_response :ok
  end

  test "GET /admin/outbox_eventsはステータスでフィルタリングできる" do
    # Act
    get admin_outbox_events_path,
        params: {
          status: "pending"
        },
        headers: admin_auth_headers

    # Assert
    assert_response :ok
  end

  test "GET /admin/outbox_eventsは認証なしで401を返す" do
    # Act
    get admin_outbox_events_path

    # Assert
    assert_response :unauthorized
  end

  # --- GET /admin/outbox_events/:id ---

  test "GET /admin/outbox_events/:idはイベント詳細を表示する" do
    # Arrange
    event = outbox_events(:pending_event)

    # Act
    get admin_outbox_event_path(event), headers: admin_auth_headers

    # Assert
    assert_response :ok
  end
end
