module Api
  class VirtualAccountsController < BaseController
    def index
      render json: paginate(VirtualAccount.order(created_at: :desc))
    end

    def create
      account = Account.find(params[:account_id])
      va = VirtualAccount.issue!(account: account, va_name: params[:va_name])
      render json: va, status: :created
    end
  end
end
