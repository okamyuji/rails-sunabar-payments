module MockSunabar
  def setup_sunabar_client!
    ENV["SUNABAR_PERSONAL_TOKEN"] ||= "test-token"
    ENV["SUNABAR_CORPORATE_TOKEN"] ||= "test-token"
    SunabarClient.setup!
  end

  def stub_request_transfer(apply_no: "APL-001")
    stub_request(:post, %r{/personal/v1/transfer/request}).to_return(
      status: 200,
      body: { applyNo: apply_no }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )
  end

  def stub_transfer_status(status: "Settled")
    stub_request(:get, %r{/personal/v1/transfer/status}).to_return(
      status: 200,
      body: { status: status }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )
  end

  def stub_list_accounts
    stub_request(:get, %r{/personal/v1/accounts}).to_return(
      status: 200,
      body: {
        accounts: [
          {
            accountId: "ACC-1",
            accountNumber: "1234567",
            branchCode: "101",
            accountName: "テスト"
          }
        ]
      }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )
  end

  def stub_list_transactions(transactions: [])
    stub_request(:get, %r{/corporation/v1/va/transactions}).to_return(
      status: 200,
      body: { transactions: transactions }.to_json,
      headers: {
        "Content-Type" => "application/json"
      }
    )
  end

  def stub_sunabar_error(status:)
    stub_request(:any, /api\.sunabar/).to_return(
      status: status,
      body: { error: "test" }.to_json
    )
  end
end
