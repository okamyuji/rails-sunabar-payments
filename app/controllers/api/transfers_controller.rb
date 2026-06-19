module Api
  class TransfersController < BaseController
    def index
      transfers =
        Transfer
          .all
          .by_status(params[:status])
          .by_date_range(params[:from_date], params[:to_date])
          .order(created_at: :desc)
      render json: paginate(transfers)
    end

    def show
      render json: Transfer.find(params[:id])
    end

    def create
      transfer = Transfer.find_or_create_idempotent!(transfer_params)
      status = transfer.previously_new_record? ? :created : :ok
      render json: transfer, status: status
    end

    private

    def transfer_params
      params.require(:transfer).permit(
        :app_request_id,
        :account_id,
        :destination_bank_code,
        :destination_branch_code,
        :destination_account_number,
        :destination_account_type,
        :destination_account_name,
        :amount,
        :transfer_date,
        :remarks
      )
    end
  end
end
