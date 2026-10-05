module Admin
  class BaseController < ActionController::Base
    include Pagy::Method
    layout "admin"

    before_action :authenticate_admin!

    private

    # 既定の資格情報は development/test だけで使う。staging なども含め、それ以外で未設定なら全員を拒否する。
    def authenticate_admin!
      name, password = admin_credentials
      return request_http_basic_authentication if name.blank? || password.blank?

      http_basic_authenticate_or_request_with(name:, password:)
    end

    def admin_credentials
      if Rails.env.local?
        [
          ENV.fetch("ADMIN_USER", "admin"),
          ENV.fetch("ADMIN_PASSWORD", "changeme")
        ]
      else
        [ENV["ADMIN_USER"], ENV["ADMIN_PASSWORD"]]
      end
    end
  end
end
