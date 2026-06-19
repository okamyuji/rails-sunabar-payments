require "application_system_test_case"

class AdminDashboardTest < ApplicationSystemTestCase
  test "ダッシュボードに振込件数と消込状況が表示される" do
    visit_admin admin_path
    assert_text "ダッシュボード"
    assert_text "Outbox未処理"
    assert_text "Outbox失敗"
  end

  test "振込一覧で状態フィルタが動作する" do
    visit_admin admin_transfers_path
    assert_text "振込一覧"
    click_link "pending"
    assert_current_path admin_transfers_path(status: "pending")
  end

  test "Outboxモニタが表示される" do
    visit_admin admin_outbox_events_path
    assert_text "Outboxモニタ"
  end
end
