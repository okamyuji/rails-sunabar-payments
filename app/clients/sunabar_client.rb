class SunabarClient
  BASE_URL = "https://api.sunabar.gmo-aozora.com".freeze
  TIMEOUT = 5

  class << self
    def instance
      @instance
    end

    def setup!
      @instance = new
    end
  end

  def initialize
    @personal_token = fetch_credential(:sunabar_personal_token)
    @corporate_token = fetch_credential(:sunabar_corporate_token)
    @personal_conn = build_connection(@personal_token)
    @corporate_conn = build_connection(@corporate_token)
  end

  def request_transfer(idempotency_key:, account_id:, **params)
    execute do
      @personal_conn.post("/personal/v1/transfer/request") do |req|
        req.headers["x-idempotency-key"] = idempotency_key
        req.body = build_transfer_body(params)
      end
    end
  end

  def get_transfer_status(apply_no:)
    execute do
      @personal_conn.get("/personal/v1/transfer/status", { applyNo: apply_no })
    end
  end

  def list_accounts
    execute { @personal_conn.get("/personal/v1/accounts") }
  end

  def get_balance(account_id:)
    execute do
      @personal_conn.get(
        "/personal/v1/accounts/balances",
        { accountId: account_id }
      )
    end
  end

  def list_transactions(va_id:)
    result =
      execute do
        @corporate_conn.get("/corporation/v1/va/transactions", { vaId: va_id })
      end
    result[:transactions]&.map { |t| parse_transaction(t) } || []
  end

  def issue_virtual_account(account_id:, va_name:)
    execute do
      @corporate_conn.post("/corporation/v1/va/issue") do |req|
        req.body = { vaTypeCode: "1", vaName: va_name }.to_json
      end
    end
  end

  private

  def execute
    response = yield
    handle_response(response)
  rescue Faraday::TimeoutError => e
    raise SunabarErrors::TimeoutError, e.message
  rescue Faraday::ConnectionFailed => e
    raise SunabarErrors::ConnectionError, e.message
  end

  def build_connection(token)
    Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json
      f.headers["Authorization"] = "Bearer #{token}"
      f.options.timeout = TIMEOUT
      f.options.open_timeout = TIMEOUT
    end
  end

  def handle_response(response)
    case response.status
    when 200..299
      response.body.deep_symbolize_keys
    when 429
      raise SunabarErrors::RateLimitError, "429: #{response.body}"
    when 400..499
      raise SunabarErrors::ClientError, "#{response.status}: #{response.body}"
    when 500..599
      raise SunabarErrors::ServerError, "#{response.status}: #{response.body}"
    else
      raise SunabarErrors::Error, "予期しないHTTPステータス: #{response.status}"
    end
  end

  def build_transfer_body(params)
    {
      accountId: params[:account_id],
      transferDesignatedDate: params[:transfer_date]&.strftime("%Y%m%d"),
      transferDateHolidayCode: "1",
      transfers: [
        {
          itemId: "1",
          transferAmount: params[:amount].to_s,
          beneficiaryBankCode: params[:destination_bank_code],
          beneficiaryBranchCode: params[:destination_branch_code],
          accountTypeCode:
            params[:destination_account_type] == "ordinary" ? "1" : "2",
          accountNumber: params[:destination_account_number],
          beneficiaryName: params[:destination_account_name]
        }
      ]
    }.to_json
  end

  def parse_transaction(t)
    {
      transaction_id: t[:transactionId] || t["transactionId"],
      amount: parse_int(t[:amount] || t["amount"]),
      sender_name: t[:senderName] || t["senderName"],
      transaction_date: t[:transactionDate] || t["transactionDate"]
    }
  end

  def parse_int(val)
    val.is_a?(String) ? val.to_i : val
  end

  def fetch_credential(key)
    ENV[key.to_s.upcase] || Rails.application.credentials.dig(:sunabar, key)
  end
end
