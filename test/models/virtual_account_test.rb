require "test_helper"

class VirtualAccountTest < ActiveSupport::TestCase
  # --- issue! ---

  test "issue!はSunabarAPIで仮想口座を発行し保存する" do
    # Arrange
    account = accounts(:sunabar_main)
    client = Object.new
    client.define_singleton_method(
      :issue_virtual_account
    ) { |account_id:, va_name:| { vaId: "VA-NEW-001", vaNumber: "5555555" } }

    # Act
    va =
      VirtualAccount.issue!(account: account, va_name: "新規VA", client: client)

    # Assert
    assert va.persisted?
    assert_equal "VA-NEW-001", va.sunabar_va_id
    assert_equal "5555555", va.va_number
    assert_equal "新規VA", va.va_name
    assert_equal account.id, va.account_id
  end

  # --- バリデーション ---

  test "sunabar_va_idが空の場合はバリデーションエラーになる" do
    # Arrange
    va =
      VirtualAccount.new(
        account: accounts(:sunabar_main),
        sunabar_va_id: nil,
        va_number: "1234567"
      )

    # Act & Assert
    assert_not va.valid?
    assert va.errors[:sunabar_va_id].present?
  end

  test "va_numberが空の場合はバリデーションエラーになる" do
    # Arrange
    va =
      VirtualAccount.new(
        account: accounts(:sunabar_main),
        sunabar_va_id: "VA-NEW",
        va_number: nil
      )

    # Act & Assert
    assert_not va.valid?
    assert va.errors[:va_number].present?
  end

  test "sunabar_va_idの重複はバリデーションエラーになる" do
    # Arrange
    existing = virtual_accounts(:test_va)
    va =
      VirtualAccount.new(
        account: accounts(:sunabar_main),
        sunabar_va_id: existing.sunabar_va_id,
        va_number: "9999999"
      )

    # Act & Assert
    assert_not va.valid?
    assert va.errors[:sunabar_va_id].present?
  end

  # --- アソシエーション ---

  test "仮想口座はアカウントに属する" do
    # Arrange
    va = virtual_accounts(:test_va)

    # Act & Assert
    assert_equal accounts(:sunabar_main), va.account
  end
end
