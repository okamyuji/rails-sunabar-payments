require "test_helper"

class Api::ReconciliationsControllerTest < ActionDispatch::IntegrationTest
  # --- POST /api/reconciliations/run ---

  test "POST /api/reconciliations/runは消込ジョブをエンキューする" do
    # Act
    assert_enqueued_with(job: ReconcileJob) do
      post api_reconciliations_run_path, as: :json
    end

    # Assert
    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal "消込ジョブを開始しました", body["message"]
  end
end
