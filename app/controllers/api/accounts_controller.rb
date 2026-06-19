module Api
  class AccountsController < BaseController
    def index
      render json: paginate(Account.order(created_at: :desc))
    end

    def show
      account = Account.find(params[:id])
      balance = account.fetch_balance
      render json: account.as_json.merge(balance: balance)
    end

    def sync
      Account.sync!
      render json: { message: "同期完了" }, status: :ok
    end
  end
end
