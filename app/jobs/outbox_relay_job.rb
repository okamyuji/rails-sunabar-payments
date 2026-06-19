class OutboxRelayJob < ApplicationJob
  queue_as :outbox
  limits_concurrency key: "outbox_relay", to: 1

  HANDLER_MAP = {
    "TransferRequested" => ->(cb) do
      Handlers::SendToSunabar.new(circuit_breaker: cb)
    end,
    "TransferStatusCheckScheduled" => ->(cb) do
      Handlers::CheckTransferStatus.new(circuit_breaker: cb)
    end,
    "TransferAwaitingApproval" => ->(_) { Handlers::ProcessNotification.new },
    "TransferSettled" => ->(_) { Handlers::ProcessNotification.new },
    "TransferFailed" => ->(_) { Handlers::ProcessNotification.new },
    "ReconciliationCompleted" => ->(_) { Handlers::ProcessNotification.new },
    "ReconciliationExcess" => ->(_) { Handlers::ProcessNotification.new },
    "ReconciliationPartial" => ->(_) { Handlers::ProcessNotification.new }
  }.freeze

  MAX_CONSECUTIVE_ERRORS = 10

  def perform
    event_ids = fetch_pending_event_ids
    event_ids.each { |eid| process_event(eid) }
    @consecutive_errors = 0
    reschedule!
  rescue => e
    @consecutive_errors = (@consecutive_errors || 0) + 1
    Rails.logger.error(
      {
        event: "outbox_relay_error",
        error: e.message,
        consecutive: @consecutive_errors
      }.to_json
    )
    reschedule! if @consecutive_errors < MAX_CONSECUTIVE_ERRORS
  end

  private

  def fetch_pending_event_ids
    OutboxEvent.transaction(isolation: :read_committed) do
      OutboxEvent.pending_dispatchable.pluck(:id)
    end
  end

  def process_event(event_id)
    OutboxEvent.transaction(isolation: :read_committed) do
      event =
        OutboxEvent.where(id: event_id).lock("FOR UPDATE SKIP LOCKED").first
      return unless event && event.status == "pending"

      dispatch(event)
    end
  end

  def dispatch(event)
    handler_factory = HANDLER_MAP[event.event_type]
    unless handler_factory
      event.mark_failed!("不明なイベント種別: #{event.event_type}")
      return
    end

    handler = handler_factory.call(circuit_breaker)
    result = handler.call(event)

    # ハンドラは:symbolまたは[:symbol, "error message"]を返す
    status, error_msg = Array(result)

    case status
    when :success
      event.mark_sent!
    when :still_in_flight
      event.record_still_in_flight!
    when :skip_attempt
      event.record_skip_attempt!
    when :retryable
      event.record_retryable_error!(error_msg || "retryable error")
    when :non_retryable
      event.mark_failed!(error_msg || "non-retryable error")
    end
  rescue => e
    event.record_retryable_error!(e.message)
  end

  def reschedule!
    self.class.set(wait: 5.seconds).perform_later
  end

  def circuit_breaker
    @circuit_breaker ||= Rails.application.config.circuit_breaker
  end
end
