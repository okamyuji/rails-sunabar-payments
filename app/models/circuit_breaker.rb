class CircuitBreaker
  class OpenError < StandardError
  end

  CLOSED = :closed
  OPEN = :open
  HALF_OPEN = :half_open

  def initialize(
    failure_threshold: 3,
    failure_rate_threshold: 0.5,
    rolling_window: 30,
    min_requests: 5,
    reset_timeout: 30,
    half_open_max_probes: 2
  )
    @failure_threshold = failure_threshold
    @failure_rate_threshold = failure_rate_threshold
    @rolling_window = rolling_window
    @min_requests = min_requests
    @reset_timeout = reset_timeout
    @half_open_max_probes = half_open_max_probes
    @state = CLOSED
    @failures = []
    @successes = []
    @consecutive_failures = 0
    @last_failure_at = nil
    @half_open_probes = 0
    @monitor = Monitor.new
  end

  def allow?(now = Time.current)
    @monitor.synchronize do
      case @state
      when CLOSED
        true
      when OPEN
        if now - @last_failure_at >= @reset_timeout
          @state = HALF_OPEN
          @half_open_probes = 0
          true
        else
          false
        end
      when HALF_OPEN
        if @half_open_probes < @half_open_max_probes
          @half_open_probes += 1
          true
        else
          false
        end
      end
    end
  end

  def record_success(now = Time.current)
    @monitor.synchronize do
      @successes << now
      @consecutive_failures = 0
      @state = CLOSED if @state == HALF_OPEN
      prune_window(now)
    end
  end

  def record_failure(now = Time.current)
    @monitor.synchronize do
      @failures << now
      @consecutive_failures += 1
      @last_failure_at = now
      prune_window(now)

      if @state == HALF_OPEN
        @state = OPEN
      elsif should_open?
        @state = OPEN
      end
    end
  end

  def state
    @monitor.synchronize { @state }
  end

  private

  def should_open?
    return true if @consecutive_failures >= @failure_threshold

    total = @failures.size + @successes.size
    return false if total < @min_requests

    failure_rate = @failures.size.to_f / total
    failure_rate >= @failure_rate_threshold
  end

  def prune_window(now)
    cutoff = now - @rolling_window
    @failures.reject! { |t| t < cutoff }
    @successes.reject! { |t| t < cutoff }
  end
end
