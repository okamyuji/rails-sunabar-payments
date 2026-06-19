module Admin
  class BaseController < ActionController::Base
    include Pagy::Method
    layout "admin"

    http_basic_authenticate_with(
      name:
        ENV.fetch("ADMIN_USER") do
          Rails.env.production? ? raise("ADMIN_USER未設定") : "admin"
        end,
      password:
        ENV.fetch("ADMIN_PASSWORD") do
          Rails.env.production? ? raise("ADMIN_PASSWORD未設定") : "changeme"
        end
    )
  end
end
