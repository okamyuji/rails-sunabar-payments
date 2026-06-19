require "test_helper"

class TransferTest < ActiveSupport::TestCase
  def valid_params
    {
      account_id: accounts(:sunabar_main).id,
      app_request_id: "REQ-#{SecureRandom.hex(8)}",
      amount: 5000,
      destination_bank_code: "0310",
      destination_branch_code: "101",
      destination_account_number: "9876543",
      destination_account_type: "ordinary",
      destination_account_name: "テスト受取人"
    }
  end

  # --- create_with_outbox! ---

  test "create_with_outbox!はTransferとOutboxEventを同一トランザクションで作成する" do
    # Arrange
    params = valid_params
    event_count_before = OutboxEvent.count

    # Act
    transfer = Transfer.create_with_outbox!(params)

    # Assert
    assert transfer.persisted?
    assert_equal "pending", transfer.status
    assert_equal 1, OutboxEvent.count - event_count_before

    event = OutboxEvent.last
    assert_equal "TransferRequested", event.event_type
    assert_equal "Transfer", event.aggregate_type
  end

  # --- find_or_create_idempotent! ---

  test "find_or_create_idempotent!はDB制約違反時に既存レコードを返す(RecordNotUnique)" do
    # Arrange
    params = valid_params
    original = Transfer.find_or_create_idempotent!(params)

    # Act - RecordNotUniqueを直接raiseしてDB制約違反をシミュレーション
    original_method = Transfer.method(:create_with_outbox!)
    call_count = 0
    Transfer.define_singleton_method(:create_with_outbox!) do |p|
      call_count += 1
      raise ActiveRecord::RecordNotUnique.new(
              "Duplicate entry '#{p[:app_request_id]}' for key 'index_transfers_on_app_request_id'"
            )
    end

    begin
      duplicate = Transfer.find_or_create_idempotent!(params)

      # Assert
      assert_equal original.id, duplicate.id
      assert_equal 1, call_count
    ensure
      Transfer.define_singleton_method(:create_with_outbox!, original_method)
    end
  end

  # --- status transitions ---

  test "pendingからrequestedへの遷移は成功する" do
    # Arrange
    transfer = Transfer.create_with_outbox!(valid_params)

    # Act
    transfer.transition_to!("requested")

    # Assert
    assert_equal "requested", transfer.reload.status
  end

  test "requestedからawaiting_approvalへの遷移は成功する" do
    # Arrange
    transfer = Transfer.create_with_outbox!(valid_params)
    transfer.transition_to!("requested")

    # Act
    transfer.transition_to!("awaiting_approval")

    # Assert
    assert_equal "awaiting_approval", transfer.reload.status
  end

  test "awaiting_approvalからapprovedへの遷移は成功する" do
    # Arrange
    transfer = Transfer.create_with_outbox!(valid_params)
    transfer.transition_to!("requested")
    transfer.transition_to!("awaiting_approval")

    # Act
    transfer.transition_to!("approved")

    # Assert
    assert_equal "approved", transfer.reload.status
  end

  test "approvedからsettledへの遷移は成功する" do
    # Arrange
    transfer = Transfer.create_with_outbox!(valid_params)
    transfer.transition_to!("requested")
    transfer.transition_to!("awaiting_approval")
    transfer.transition_to!("approved")

    # Act
    transfer.transition_to!("settled")

    # Assert
    assert_equal "settled", transfer.reload.status
  end

  test "pendingからsettledへの遷移はInvalidTransitionが発生する" do
    # Arrange
    transfer = Transfer.create_with_outbox!(valid_params)

    # Act & Assert
    assert_raises(HasStatusMachine::InvalidTransition) do
      transfer.transition_to!("settled")
    end
  end

  test "pendingからapprovedへの遷移はInvalidTransitionが発生する" do
    # Arrange
    transfer = Transfer.create_with_outbox!(valid_params)

    # Act & Assert
    assert_raises(HasStatusMachine::InvalidTransition) do
      transfer.transition_to!("approved")
    end
  end

  # --- terminal? ---

  test "terminal?はsettledでtrueを返す" do
    # Arrange
    transfer = Transfer.create_with_outbox!(valid_params)
    transfer.transition_to!("requested")
    transfer.transition_to!("settled")

    # Act & Assert
    assert transfer.terminal?
  end

  test "terminal?はfailedでtrueを返す" do
    # Arrange
    transfer = Transfer.create_with_outbox!(valid_params)
    transfer.transition_to!("failed")

    # Act & Assert
    assert transfer.terminal?
  end

  test "terminal?はpendingでfalseを返す" do
    # Arrange
    transfer = Transfer.create_with_outbox!(valid_params)

    # Act & Assert
    assert_not transfer.terminal?
  end

  # --- scopes ---

  test "by_statusはstatusで絞り込む" do
    # Arrange
    Transfer.create_with_outbox!(valid_params)

    # Act
    results = Transfer.by_status("pending")

    # Assert
    assert results.all? { |t| t.status == "pending" }
  end

  test "by_date_rangeは日付範囲で絞り込む" do
    # Arrange
    transfer =
      Transfer.create_with_outbox!(
        valid_params.merge(transfer_date: Date.new(2026, 6, 15))
      )

    # Act
    results =
      Transfer.by_date_range(Date.new(2026, 6, 10), Date.new(2026, 6, 20))

    # Assert
    assert_includes results, transfer
  end

  test "by_date_rangeは範囲外のレコードを除外する" do
    # Arrange
    Transfer.create_with_outbox!(
      valid_params.merge(transfer_date: Date.new(2026, 6, 1))
    )

    # Act
    results =
      Transfer.by_date_range(Date.new(2026, 6, 10), Date.new(2026, 6, 20))

    # Assert
    results.each do |t|
      assert t.transfer_date >= Date.new(2026, 6, 10)
      assert t.transfer_date <= Date.new(2026, 6, 20)
    end
  end

  # --- lock_version (optimistic locking) ---

  test "lock_versionによる楽観ロックでStaleObjectErrorが発生する" do
    # Arrange
    transfer = Transfer.create_with_outbox!(valid_params)
    stale_copy = Transfer.find(transfer.id)

    # Act
    transfer.transition_to!("requested")

    # Assert
    assert_raises(ActiveRecord::StaleObjectError) do
      stale_copy.transition_to!("failed")
    end
  end
end
