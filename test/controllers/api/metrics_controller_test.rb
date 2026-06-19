require "test_helper"

class Api::MetricsControllerTest < ActionDispatch::IntegrationTest
  # --- GET /api/metrics ---

  test "GET /api/metricsはメトリクスを返す" do
    # Act
    get api_metrics_path, as: :json

    # Assert
    assert_response :ok
    body = JSON.parse(response.body)
    assert body.key?("outbox_pending_depth")
    assert body.key?("outbox_failed_depth")
    assert body.key?("transfer_status")
  end

  test "GET /api/metricsのoutbox_pending_depthはpendingイベント数を返す" do
    # Arrange
    outbox_events(:pending_event) # fixture読み込み

    # Act
    get api_metrics_path, as: :json

    # Assert
    body = JSON.parse(response.body)
    assert body["outbox_pending_depth"] >= 1
  end

  test "GET /api/metricsのtransfer_statusはステータスごとの件数を返す" do
    # Arrange
    transfers(:pending_transfer) # fixture読み込み

    # Act
    get api_metrics_path, as: :json

    # Assert
    body = JSON.parse(response.body)
    assert body["transfer_status"].is_a?(Hash)
    assert body["transfer_status"]["pending"] >= 1
  end
end
