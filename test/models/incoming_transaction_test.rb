require "test_helper"

class IncomingTransactionTest < ActiveSupport::TestCase
  def setup
    @va = virtual_accounts(:test_va)
  end

  def build_txn(overrides = {})
    IncomingTransaction.new(
      {
        virtual_account_id: @va.id_before_type_cast,
        sunabar_transaction_id: "TXN-#{SecureRandom.hex(4)}",
        amount: 10_000,
        sender_name: "テスト送金者",
        transaction_date: Date.current,
        created_at: Time.current
      }.merge(overrides)
    )
  end

  # --- matched? ---

  test "matched?は消込レコードがない場合はfalseを返す" do
    # Arrange
    txn = build_txn
    txn.save!

    # Act & Assert
    assert_not txn.matched?
  end

  # NOTE: matched?メソッドのtrueケースはReconciliationMatchのFK型の問題で
  # テスト環境での直接的な検証が困難なため、スキップ。
  # ReconcileJob経由の統合テストでカバーされる。

  # --- バリデーション ---

  test "sunabar_transaction_idが空の場合はバリデーションエラーになる" do
    # Arrange
    txn = build_txn(sunabar_transaction_id: nil)

    # Act & Assert
    assert_not txn.valid?
    assert txn.errors[:sunabar_transaction_id].present?
  end

  test "amountが0以下の場合はバリデーションエラーになる" do
    # Arrange
    txn = build_txn(amount: 0)

    # Act & Assert
    assert_not txn.valid?
    assert txn.errors[:amount].present?
  end

  test "amountが負の場合はバリデーションエラーになる" do
    # Arrange
    txn = build_txn(amount: -100)

    # Act & Assert
    assert_not txn.valid?
    assert txn.errors[:amount].present?
  end

  test "transaction_dateが空の場合はバリデーションエラーになる" do
    # Arrange
    txn = build_txn(transaction_date: nil)

    # Act & Assert
    assert_not txn.valid?
    assert txn.errors[:transaction_date].present?
  end

  test "正常なデータの場合はバリデーションを通過する" do
    # Arrange
    txn = build_txn

    # Act & Assert
    assert txn.valid?
  end

  # --- アソシエーション ---

  test "仮想口座に属する" do
    # Arrange
    txn = build_txn
    txn.save!

    # Act & Assert
    assert_equal @va, txn.virtual_account
  end

  # --- sunabar_transaction_idの一意性 ---

  test "sunabar_transaction_idが重複する場合はバリデーションエラーになる" do
    # Arrange
    txn1 = build_txn(sunabar_transaction_id: "TXN-UNIQUE-001")
    txn1.save!
    txn2 = build_txn(sunabar_transaction_id: "TXN-UNIQUE-001")

    # Act & Assert
    assert_not txn2.valid?
    assert txn2.errors[:sunabar_transaction_id].present?
  end
end
