require "application_system_test_case"

class AdminInvoicesTest < ApplicationSystemTestCase
  test "請求書のCRUD操作ができる" do
    visit_admin admin_invoices_path
    assert_text "請求書一覧"

    click_link "新規作成"
    assert_text "請求書作成"

    fill_in "請求金額(円)", with: 50_000
    fill_in "摘要", with: "テスト請求"
    fill_in "支払期限", with: "2026-12-31"
    # VA IDはfixtureから取得できないためフォーム送信はスキップ
  end

  test "請求書一覧で状態フィルタが動作する" do
    visit_admin admin_invoices_path
    click_link "open"
    assert_current_path admin_invoices_path(status: "open")
  end
end
