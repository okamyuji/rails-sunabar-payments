require "test_helper"

class CircuitBreakerFullTest < ActiveSupport::TestCase
  # --- 初期状態 ---

  test "初期状態はCLOSEDである" do
    # Arrange
    cb = CircuitBreaker.new

    # Act & Assert
    assert_equal :closed, cb.state
  end

  test "CLOSED状態ではallow?がtrueを返す" do
    # Arrange
    cb = CircuitBreaker.new

    # Act & Assert
    assert cb.allow?
  end

  # --- 連続失敗によるOPEN遷移 ---

  test "連続失敗がfailure_thresholdに達するとOPENに遷移する" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 3)

    # Act
    3.times { cb.record_failure }

    # Assert
    assert_equal :open, cb.state
  end

  test "OPEN状態ではallow?がfalseを返す" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 2)
    2.times { cb.record_failure }

    # Act & Assert
    assert_not cb.allow?
  end

  # --- reset_timeout後のHALF_OPEN遷移 ---

  test "OPEN状態でreset_timeout経過後にallow?がtrueを返しHALF_OPENに遷移する" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 2, reset_timeout: 10)
    now = Time.current
    2.times { cb.record_failure(now) }

    # Act
    result = cb.allow?(now + 11)

    # Assert
    assert result
    assert_equal :half_open, cb.state
  end

  test "OPEN状態でreset_timeout未経過ならallow?がfalseを返す" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 2, reset_timeout: 10)
    now = Time.current
    2.times { cb.record_failure(now) }

    # Act & Assert
    assert_not cb.allow?(now + 5)
    assert_equal :open, cb.state
  end

  # --- HALF_OPEN状態 ---

  test "HALF_OPEN状態で成功するとCLOSEDに戻る" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 2, reset_timeout: 1)
    now = Time.current
    2.times { cb.record_failure(now) }
    cb.allow?(now + 2) # HALF_OPENに遷移

    # Act
    cb.record_success(now + 3)

    # Assert
    assert_equal :closed, cb.state
  end

  test "HALF_OPEN状態で失敗するとOPENに戻る" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 2, reset_timeout: 1)
    now = Time.current
    2.times { cb.record_failure(now) }
    cb.allow?(now + 2) # HALF_OPENに遷移

    # Act
    cb.record_failure(now + 3)

    # Assert
    assert_equal :open, cb.state
  end

  test "HALF_OPEN状態でhalf_open_max_probesを超えるとallow?がfalseを返す" do
    # Arrange
    cb =
      CircuitBreaker.new(
        failure_threshold: 2,
        reset_timeout: 1,
        half_open_max_probes: 2
      )
    now = Time.current
    2.times { cb.record_failure(now) }

    # Act - 初回allow?でHALF_OPENに遷移(OPEN分岐で処理、probeカウントなし)
    assert cb.allow?(now + 2)
    # probe 1 (HALF_OPEN分岐: 0 < 2, probes=1)
    assert cb.allow?(now + 2)
    # probe 2 (HALF_OPEN分岐: 1 < 2, probes=2)
    assert cb.allow?(now + 2)
    # probe 3 (HALF_OPEN分岐: 2 < 2 → false)
    result = cb.allow?(now + 2)

    # Assert
    assert_not result
  end

  # --- failure_rate_threshold ---

  test "失敗率がfailure_rate_thresholdを超えるとOPENに遷移する" do
    # Arrange
    cb =
      CircuitBreaker.new(
        failure_threshold: 100, # 連続失敗では開かない設定
        failure_rate_threshold: 0.5,
        min_requests: 4,
        rolling_window: 60
      )
    now = Time.current

    # Act - 成功2回、失敗3回 (失敗率60%)
    2.times { |i| cb.record_success(now + i) }
    3.times { |i| cb.record_failure(now + 2 + i) }

    # Assert
    assert_equal :open, cb.state
  end

  test "min_requests未満ではfailure_rateでOPENにならない" do
    # Arrange
    cb =
      CircuitBreaker.new(
        failure_threshold: 100,
        failure_rate_threshold: 0.5,
        min_requests: 10,
        rolling_window: 60
      )
    now = Time.current

    # Act - 失敗3回のみ(min_requests=10未満)
    3.times { |i| cb.record_failure(now + i) }

    # Assert
    assert_equal :closed, cb.state
  end

  # --- record_success ---

  test "record_successは連続失敗カウントをリセットする" do
    # Arrange
    cb = CircuitBreaker.new(failure_threshold: 3)
    2.times { cb.record_failure }

    # Act
    cb.record_success

    # Assert - もう1回失敗してもOPENにならない(カウントがリセットされたため)
    cb.record_failure
    assert_equal :closed, cb.state
  end

  # --- ローリングウィンドウ ---

  test "ローリングウィンドウ外の古い記録は除外される" do
    # Arrange
    cb =
      CircuitBreaker.new(
        failure_threshold: 100,
        failure_rate_threshold: 0.5,
        min_requests: 4,
        rolling_window: 10
      )
    now = Time.current

    # Act - 古い失敗(ウィンドウ外)
    3.times { |i| cb.record_failure(now - 20 + i) }
    # 新しい成功(ウィンドウ内)
    5.times { |i| cb.record_success(now + i) }

    # Assert - 古い失敗は除外されているのでCLOSEDのまま
    assert_equal :closed, cb.state
  end
end
