module Admin
  class TransfersController < BaseController
    def index
      transfers =
        Transfer.all.by_status(params[:status]).order(created_at: :desc)
      @pagy, @transfers = pagy(transfers)
    end

    def show
      @transfer = Transfer.find(params[:id])
      @outbox_events =
        OutboxEvent.where(
          aggregate_type: "Transfer",
          aggregate_id: @transfer.id_for_payload
        ).order(created_at: :desc)
    end
  end
end
