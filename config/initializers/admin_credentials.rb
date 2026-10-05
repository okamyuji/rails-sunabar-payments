# production は未設定のまま公開しないよう起動時に止める。
# staging などは起動させ、Admin::BaseController#authenticate_admin! で全員を拒否する。
if Rails.env.production?
  %w[ADMIN_USER ADMIN_PASSWORD].each do |key|
    raise "#{key}未設定" if ENV[key].blank?
  end
end
