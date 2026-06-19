module Handlers
  class CheckTransferStatus
    class SkipAttemptError < StandardError
    end

    def initialize(circuit_breaker:, client: SunabarClient.instance)
      @circuit_breaker = circuit_breaker
      @client = client
    end

    def call(event)
      transfer = Transfer.find_by!(id: event.payload["transfer_id"])
      return :success if transfer.terminal?

      unless @circuit_breaker.allow?
        raise SkipAttemptError, "CircuitBreaker OPEN"
      end

      response =
        @client.get_transfer_status(apply_no: transfer.sunabar_apply_no)
      @circuit_breaker.record_success

      internal_status = SunabarStatusMapper.map(response[:status])

      if SunabarStatusMapper.terminal?(internal_status)
        transfer.transaction do
          transfer.transition_to!(internal_status)
          event_type =
            internal_status == "settled" ? "TransferSettled" : "TransferFailed"
          transfer.publish_outbox_event!(
            event_type: event_type,
            payload: {
              transfer_id: transfer.id_for_payload
            }
          )
        end
        :success
      else
        if transfer.status != internal_status
          transfer.transaction do
            transfer.transition_to!(internal_status)
            if internal_status == "awaiting_approval"
              transfer.publish_outbox_event!(
                event_type: "TransferAwaitingApproval",
                payload: {
                  transfer_id: transfer.id_for_payload
                }
              )
            end
          end
        end
        :still_in_flight
      end
    rescue ArgumentError => e
      transfer&.update!(last_error: "不明なsunabarステータス: #{e.message}")
      :non_retryable
    rescue SunabarErrors::RateLimitError,
           SunabarErrors::ServerError,
           SunabarErrors::TimeoutError,
           SunabarErrors::ConnectionError => e
      @circuit_breaker.record_failure
      transfer&.update!(last_error: e.message)
      [:retryable, e.message]
    rescue SunabarErrors::ClientError => e
      transfer.transaction do
        transfer.update!(last_error: e.message)
        transfer.transition_to!("failed")
        transfer.publish_outbox_event!(
          event_type: "TransferFailed",
          payload: {
            transfer_id: transfer.id_for_payload,
            error: e.message
          }
        )
      end
      :non_retryable
    rescue SkipAttemptError
      :skip_attempt
    end
  end
end
