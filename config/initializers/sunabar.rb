Rails.application.config.after_initialize do
  if Rails.env.production? || ENV["SUNABAR_PERSONAL_TOKEN"].present?
    SunabarClient.setup!
  end
end
