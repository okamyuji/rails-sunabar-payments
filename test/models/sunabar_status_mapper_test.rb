require "test_helper"

class SunabarStatusMapperTest < ActiveSupport::TestCase
  # --- map ---

  test "AcceptedToBankをrequestedにマッピングする" do
    assert_equal "requested", SunabarStatusMapper.map("AcceptedToBank")
  end

  test "AwaitingApprovalをawaiting_approvalにマッピングする" do
    assert_equal "awaiting_approval",
                 SunabarStatusMapper.map("AwaitingApproval")
  end

  test "Approvedをapprovedにマッピングする" do
    assert_equal "approved", SunabarStatusMapper.map("Approved")
  end

  test "Settledをsettledにマッピングする" do
    assert_equal "settled", SunabarStatusMapper.map("Settled")
  end

  test "Failedをfailedにマッピングする" do
    assert_equal "failed", SunabarStatusMapper.map("Failed")
  end

  test "Rejectedをfailedにマッピングする" do
    assert_equal "failed", SunabarStatusMapper.map("Rejected")
  end

  test "不明なステータスの場合はArgumentErrorを発生させる" do
    # Act & Assert
    error = assert_raises(ArgumentError) { SunabarStatusMapper.map("Unknown") }
    assert_match(/不明なsunabarステータス/, error.message)
  end

  # --- terminal? ---

  test "settledは終端ステータスである" do
    assert SunabarStatusMapper.terminal?("settled")
  end

  test "failedは終端ステータスである" do
    assert SunabarStatusMapper.terminal?("failed")
  end

  test "requestedは終端ステータスではない" do
    assert_not SunabarStatusMapper.terminal?("requested")
  end

  test "awaiting_approvalは終端ステータスではない" do
    assert_not SunabarStatusMapper.terminal?("awaiting_approval")
  end

  test "approvedは終端ステータスではない" do
    assert_not SunabarStatusMapper.terminal?("approved")
  end
end
