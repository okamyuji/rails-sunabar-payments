require "test_helper"

class AccountTest < ActiveSupport::TestCase
  # --- sync! ---

  test "sync!はSunabarAPIからアカウントを同期する" do
    # Arrange
    stub_list_accounts
    setup_sunabar_client!

    # Act
    Account.sync!(client: SunabarClient.instance)

    # Assert
    account = Account.find_by(sunabar_account_id: "ACC-1")
    assert_not_nil account
    assert_equal "1234567", account.account_number
    assert_equal "101", account.branch_code
    assert_equal "テスト", account.account_name
    assert_not_nil account.synced_at
  end

  test "sync!は既存アカウントを更新する" do
    # Arrange
    existing = accounts(:sunabar_main)
    client = Object.new
    client.define_singleton_method(:list_accounts) do
      {
        accounts: [
          {
            accountId: existing.sunabar_account_id,
            accountNumber: "9999999",
            branchCode: "202",
            accountName: "更新テスト口座"
          }
        ]
      }
    end

    # Act
    Account.sync!(client: client)

    # Assert
    existing.reload
    assert_equal "9999999", existing.account_number
    assert_equal "202", existing.branch_code
    assert_equal "更新テスト口座", existing.account_name
  end

  # --- fetch_balance ---

  test "fetch_balanceはSunabarAPIから残高を取得する" do
    # Arrange
    account = accounts(:sunabar_main)
    client = Object.new
    expected_account_id = account.sunabar_account_id
    client.define_singleton_method(:get_balance) do |account_id:|
      { balance: 100_000 }
    end

    # Act
    result = account.fetch_balance(client: client)

    # Assert
    assert_equal({ balance: 100_000 }, result)
  end

  # --- バリデーション ---

  test "sunabar_account_idが空の場合はバリデーションエラーになる" do
    # Arrange
    account =
      Account.new(
        sunabar_account_id: nil,
        account_number: "1234567",
        branch_code: "101"
      )

    # Act & Assert
    assert_not account.valid?
    assert account.errors[:sunabar_account_id].present?
  end

  test "account_numberが空の場合はバリデーションエラーになる" do
    # Arrange
    account =
      Account.new(
        sunabar_account_id: "ACC-NEW",
        account_number: nil,
        branch_code: "101"
      )

    # Act & Assert
    assert_not account.valid?
    assert account.errors[:account_number].present?
  end

  test "branch_codeが空の場合はバリデーションエラーになる" do
    # Arrange
    account =
      Account.new(
        sunabar_account_id: "ACC-NEW",
        account_number: "1234567",
        branch_code: nil
      )

    # Act & Assert
    assert_not account.valid?
    assert account.errors[:branch_code].present?
  end

  test "sunabar_account_idの重複はバリデーションエラーになる" do
    # Arrange
    existing = accounts(:sunabar_main)
    account =
      Account.new(
        sunabar_account_id: existing.sunabar_account_id,
        account_number: "1234567",
        branch_code: "101"
      )

    # Act & Assert
    assert_not account.valid?
    assert account.errors[:sunabar_account_id].present?
  end
end
