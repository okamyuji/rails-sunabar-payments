module Admin
  class ReconciliationsController < BaseController
    def index
      @pagy, @virtual_accounts =
        pagy(
          VirtualAccount.includes(:invoices, :incoming_transactions).order(
            created_at: :desc
          )
        )
    end
  end
end
