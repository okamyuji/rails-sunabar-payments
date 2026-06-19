require "test_helper"

class CircuitBreakerTest < ActiveSupport::TestCase
  # --- initial state ---

  test "初期状態はCLOSEDである" do
    # Arrange & Act
    cb = CircuitBreaker.new

    # Assert
    assert_equal CircuitBreaker::CLOSED, cb.state
  end

  # --- CLOSED state ---

  test "CLOSED状態で成功記録後もCLOSEDのまま" do
    # Arrange
    cb = CircuitBreaker.new
    now = Time.current

    # Act
    cb.record_success(now)

    # Assert
    assert_equal CircuitBreaker::CLOSED, cb.state
    assert cb.allow?(now)
  end

  # --- transition to OPEN ---

  test "連続失敗がthreshold以上でOPENに遷移する" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 3)
    now = Time.current

    # Act
    3.times { cb.record_failure(now) }

    # Assert
    assert_equal CircuitBreaker::OPEN, cb.state
  end

  # --- OPEN blocks calls ---

  test "OPEN状態ではallow?がfalseを返す" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 3, reset_timeout: 30)
    now = Time.current
    3.times { cb.record_failure(now) }

    # Act & Assert
    assert_not cb.allow?(now + 1)
  end

  # --- OPEN to HALF_OPEN ---

  test "OPEN状態でreset_timeout経過後にHALF_OPENに遷移する" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 3, reset_timeout: 10)
    now = Time.current
    3.times { cb.record_failure(now) }

    # Act
    result = cb.allow?(now + 11)

    # Assert
    assert result
    assert_equal CircuitBreaker::HALF_OPEN, cb.state
  end

  # --- HALF_OPEN limited probes ---

  test "HALF_OPENはhalf_open_max_probes回までallow?がtrueを返す" do
    # Arrange
    cb =
      CircuitBreaker.new(
        failure_threshold: 3,
        reset_timeout: 10,
        half_open_max_probes: 2
      )
    now = Time.current
    3.times { cb.record_failure(now) }
    cb.allow?(now + 11) # triggers transition to HALF_OPEN (probes=0, returns true)

    # Act & Assert
    assert cb.allow?(now + 12) # probes 0->1, true
    assert cb.allow?(now + 13) # probes 1->2, true
    assert_not cb.allow?(now + 14) # probes 2>=2, blocked
  end

  # --- HALF_OPEN increments probe count ---

  test "HALF_OPENではallow?呼び出しごとにプローブカウントがインクリメントされる" do
    # Arrange
    cb =
      CircuitBreaker.new(
        failure_threshold: 3,
        reset_timeout: 10,
        half_open_max_probes: 2
      )
    now = Time.current
    3.times { cb.record_failure(now) }
    cb.allow?(now + 11) # transition to HALF_OPEN (probes=0)

    # Act
    cb.allow?(now + 12) # probes 0->1
    cb.allow?(now + 13) # probes 1->2

    # Assert - probes exhausted
    assert_not cb.allow?(now + 14)
  end

  # --- HALF_OPEN success returns to CLOSED ---

  test "HALF_OPENで成功するとCLOSEDに戻る" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 3, reset_timeout: 10)
    now = Time.current
    3.times { cb.record_failure(now) }
    cb.allow?(now + 11) # transition to HALF_OPEN

    # Act
    cb.record_success(now + 12)

    # Assert
    assert_equal CircuitBreaker::CLOSED, cb.state
  end
end
