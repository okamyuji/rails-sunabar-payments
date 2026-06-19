# config/initializers/lograge.rb
Rails.application.configure do
  config.lograge.enabled = !Rails.env.test?
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.custom_options =
    lambda do |event|
      {
        request_id: event.payload[:request_id],
        remote_ip: event.payload[:remote_ip]
      }
    end
end
