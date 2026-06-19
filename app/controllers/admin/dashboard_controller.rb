module Admin
  class DashboardController < BaseController
    def show
      @transfer_counts = Transfer.group(:status).count
      @invoice_counts = Invoice.group(:status).count
      @outbox_pending = OutboxEvent.where(status: "pending").count
      @outbox_failed = OutboxEvent.where(status: "failed").count
    end
  end
end
