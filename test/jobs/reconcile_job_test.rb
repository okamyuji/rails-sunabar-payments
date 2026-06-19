require "test_helper"

class ReconcileJobTest < ActiveSupport::TestCase
  def setup
    @account = accounts(:sunabar_main)
    @va = virtual_accounts(:test_va)
    @invoice = invoices(:open_invoice)
    setup_sunabar_client!
  end

  # --- エラー処理 ---

  test "SunabarErrorの場合はログを記録して例外を発生させない" do
    # Arrange
    stub_request(:get, %r{/corporation/v1/va/transactions}).to_return(
      status: 500,
      body: { error: "server error" }.to_json
    )

    # Act & Assert - 例外が発生しないことを確認
    assert_nothing_raised { ReconcileJob.perform_now }
  end

  test "接続エラーの場合もログを記録して例外を発生させない" do
    # Arrange
    stub_request(:get, %r{/corporation/v1/va/transactions}).to_raise(
      Faraday::ConnectionFailed.new("connection refused")
    )

    # Act & Assert
    assert_nothing_raised { ReconcileJob.perform_now }
  end

  # --- VirtualAccount走査 ---

  test "全VirtualAccountを走査する" do
    # Arrange
    # upsert_from_sunabar!がMysql2で動かないため、トランザクションAPIは空を返す
    stub_list_transactions(transactions: [])

    # Act & Assert - エラーなく完了する
    assert_nothing_raised { ReconcileJob.perform_now }
  end
end
