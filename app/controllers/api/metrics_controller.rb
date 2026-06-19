module Api
  class MetricsController < BaseController
    def show
      render json: {
               outbox_pending_depth: OutboxEvent.where(status: "pending").count,
               outbox_failed_depth: OutboxEvent.where(status: "failed").count,
               transfer_status: Transfer.group(:status).count
             }
    end
  end
end
