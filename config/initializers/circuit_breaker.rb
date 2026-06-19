Rails.application.config.after_initialize do
  Rails.application.config.circuit_breaker = CircuitBreaker.new
end
