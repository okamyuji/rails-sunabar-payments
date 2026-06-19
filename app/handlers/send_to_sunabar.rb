module Handlers
  class SendToSunabar
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
        @client.request_transfer(
          idempotency_key: transfer.api_idempotency_key,
          account_id: transfer.account.sunabar_account_id,
          destination_bank_code: transfer.destination_bank_code,
          destination_branch_code: transfer.destination_branch_code,
          destination_account_number: transfer.destination_account_number,
          destination_account_type: transfer.destination_account_type,
          destination_account_name: transfer.destination_account_name,
          amount: transfer.amount,
          transfer_date: transfer.transfer_date,
          remarks: transfer.remarks
        )

      @circuit_breaker.record_success
      transfer.transaction do
        transfer.update!(sunabar_apply_no: response[:applyNo])
        transfer.transition_to!("requested")
        transfer.publish_outbox_event!(
          event_type: "TransferStatusCheckScheduled",
          payload: {
            transfer_id: transfer.id_for_payload
          }
        )
      end
      :success
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
    rescue SunabarErrors::RateLimitError,
           SunabarErrors::ServerError,
           SunabarErrors::TimeoutError,
           SunabarErrors::ConnectionError => e
      @circuit_breaker.record_failure
      transfer.update!(last_error: e.message)
      [:retryable, e.message]
    rescue SkipAttemptError
      :skip_attempt
    end
  end
end
