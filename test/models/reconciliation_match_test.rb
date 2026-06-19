require "test_helper"

class ReconciliationMatchTest < ActiveSupport::TestCase
  # --- バリデーション ---

  test "applied_amountが0以下の場合はバリデーションエラーになる" do
    # Arrange
    match = ReconciliationMatch.new(applied_amount: 0)

    # Act & Assert
    assert_not match.valid?
    assert match.errors[:applied_amount].present?
  end

  test "applied_amountが負の場合はバリデーションエラーになる" do
    # Arrange
    match = ReconciliationMatch.new(applied_amount: -100)

    # Act & Assert
    assert_not match.valid?
    assert match.errors[:applied_amount].present?
  end

  test "applied_amountが正の場合はバリデーション通過する" do
    # Arrange
    match = ReconciliationMatch.new(applied_amount: 1000)

    # Act
    match.valid?

    # Assert
    assert_not match.errors[:applied_amount].present?
  end
end
