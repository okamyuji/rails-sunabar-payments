module SunabarErrors
  class Error < StandardError
  end
  class ClientError < Error
  end
  class RateLimitError < Error
  end
  class ServerError < Error
  end
  class TimeoutError < Error
  end
  class ConnectionError < Error
  end
end
