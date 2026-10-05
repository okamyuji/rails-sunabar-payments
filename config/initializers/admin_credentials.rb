# production は未設定のまま公開しないよう起動時に止める。
# staging などは起動させ、Admin::BaseController#authenticate_admin! で全員を拒否する。
# SECRET_KEY_BASE_DUMMY は Dockerfile の assets:precompile のように本番の秘密を渡さないビルド工程の印なので、そこでは止めない。
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  %w[ADMIN_USER ADMIN_PASSWORD].each do |key|
    raise "#{key}未設定" if ENV[key].blank?
  end
end
