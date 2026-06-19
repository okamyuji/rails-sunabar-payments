require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  def create_account
    Account.create!(
      sunabar_account_id: "ACC-#{SecureRandom.hex(4)}",
      account_number: "1234567",
      branch_code: "101",
      account_name: "テスト口座"
    )
  end

  def create_virtual_account(account: nil)
    account ||= create_account
    VirtualAccount.create!(
      account: account,
      sunabar_va_id: "VA-#{SecureRandom.hex(4)}",
      va_number: "9876543",
      va_name: "テストVA"
    )
  end

  def create_invoice(amount: 10_000, paid_amount: 0, status: "open")
    va = create_virtual_account
    Invoice.create!(
      virtual_account: va,
      amount: amount,
      paid_amount: paid_amount,
      status: status,
      description: "テスト請求書"
    )
  end

  # --- apply_payment ---

  test "apply_paymentはpaid_amountとstatusを原子的に更新する" do
    # Arrange
    invoice = create_invoice(amount: 10_000)

    # Act
    invoice.apply_payment(10_000)

    # Assert
    invoice.reload
    assert_equal 10_000, invoice.paid_amount
    assert_equal "cleared", invoice.status
  end

  # --- determine_status ---

  test "paid_amountが0のときopenになる" do
    # Arrange
    invoice = create_invoice(amount: 10_000)

    # Act & Assert
    assert_equal "open", invoice.status
    assert_equal 0, invoice.paid_amount
  end

  test "paid_amountがamount未満のときpartialになる" do
    # Arrange
    invoice = create_invoice(amount: 10_000)

    # Act
    invoice.apply_payment(3_000)

    # Assert
    assert_equal "partial", invoice.reload.status
  end

  test "paid_amountがamountと等しいときclearedになる" do
    # Arrange
    invoice = create_invoice(amount: 10_000)

    # Act
    invoice.apply_payment(10_000)

    # Assert
    assert_equal "cleared", invoice.reload.status
  end

  test "paid_amountがamountを超えるときexcessになる" do
    # Arrange
    invoice = create_invoice(amount: 10_000)

    # Act
    invoice.apply_payment(15_000)

    # Assert
    assert_equal "excess", invoice.reload.status
  end

  # --- outbox event publishing ---

  test "apply_paymentはopen以外のステータスでOutboxEventを発行する" do
    # Arrange
    invoice = create_invoice(amount: 10_000)
    event_count_before = OutboxEvent.count

    # Act
    invoice.apply_payment(10_000)

    # Assert
    assert_equal 1, OutboxEvent.count - event_count_before
    event = OutboxEvent.last
    assert_equal "ReconciliationCompleted", event.event_type
    assert_equal "Invoice", event.aggregate_type
  end

  test "apply_paymentでpartialのときReconciliationPartialイベントを発行する" do
    # Arrange
    invoice = create_invoice(amount: 10_000)
    event_count_before = OutboxEvent.count

    # Act
    invoice.apply_payment(3_000)

    # Assert
    assert_equal 1, OutboxEvent.count - event_count_before
    event = OutboxEvent.last
    assert_equal "ReconciliationPartial", event.event_type
  end

  test "apply_paymentでexcessのときReconciliationExcessイベントを発行する" do
    # Arrange
    invoice = create_invoice(amount: 10_000)
    event_count_before = OutboxEvent.count

    # Act
    invoice.apply_payment(15_000)

    # Assert
    assert_equal 1, OutboxEvent.count - event_count_before
    event = OutboxEvent.last
    assert_equal "ReconciliationExcess", event.event_type
  end
end
