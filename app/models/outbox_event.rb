class OutboxEvent < ApplicationRecord
  STATUSES = %w[pending sent failed].freeze
  BACKOFF_CAP = 600

  validates :aggregate_type, presence: true
  validates :event_type, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending_dispatchable,
        -> do
          where(status: "pending")
            .where("next_attempt_at <= ?", Time.current)
            .order(:created_at)
            .limit(10)
            .lock("FOR UPDATE SKIP LOCKED")
        end

  def mark_sent!
    update!(status: "sent", sent_at: Time.current)
  end

  def mark_failed!(error_message)
    update!(status: "failed", last_error: error_message)
  end

  # attempt_countインクリメント+次回試行日時を単一updateで原子的に更新
  def record_retryable_error!(error_message)
    new_count = attempt_count + 1
    if new_count >= max_attempts
      update!(
        status: "failed",
        attempt_count: new_count,
        last_error: error_message
      )
    else
      update!(
        attempt_count: new_count,
        next_attempt_at: Time.current + backoff_seconds(new_count),
        last_error: error_message
      )
    end
  end

  # still_in_flight: API成功だが非終端状態。attempt_countインクリメントあり
  def record_still_in_flight!
    new_count = attempt_count + 1
    if new_count >= max_attempts
      update!(
        status: "failed",
        attempt_count: new_count,
        last_error: "max attempts reached while still in flight"
      )
    else
      update!(
        attempt_count: new_count,
        next_attempt_at: Time.current + backoff_seconds(new_count)
      )
    end
  end

  # skip_attempt: CB OPEN。attempt_countインクリメントなし
  def record_skip_attempt!
    update!(next_attempt_at: Time.current + 5)
  end

  private

  def backoff_seconds(count)
    [2**count, BACKOFF_CAP].min
  end
end
