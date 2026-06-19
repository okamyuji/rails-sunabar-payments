module Admin
  class OutboxEventsController < BaseController
    def index
      events = OutboxEvent.all
      events = events.where(status: params[:status]) if params[:status].present?
      @pagy, @outbox_events = pagy(events.order(created_at: :desc))
    end

    def show
      @outbox_event = OutboxEvent.find(params[:id])
    end
  end
end
