module Api
  class VirtualAccountsController < BaseController
    def index
      render json: paginate(VirtualAccount.order(created_at: :desc))
    end

    def create
      permitted = params.permit(:account_id, :va_name)
      account = Account.find(permitted[:account_id])
      va = VirtualAccount.issue!(account: account, va_name: permitted[:va_name])
      render json: va, status: :created
    end
  end
end
