# production は管理画面の資格情報や API トークンが未設定のまま公開しないよう起動時に止める。
# Kamal は未設定の $VAR を空文字で渡してデプロイを進めるので、空文字も未設定として扱う。
# staging などは起動させ、Admin::BaseController#authenticate_admin! で全員を拒否する。
# Dockerfile の assets:precompile は本番の秘密を渡さずに production で起動するので、そこでだけ止めない。
# SECRET_KEY_BASE_DUMMY で判定すると、実行時に残ったときも黙って検査が外れるため、実行中の rake タスク名で判定する。
precompiling_assets =
  defined?(Rake.application) &&
    Rake.application.top_level_tasks.include?("assets:precompile")

if Rails.env.production? && !precompiling_assets
  %w[ADMIN_USER ADMIN_PASSWORD API_TOKEN].each do |key|
    raise "#{key}未設定" if ENV[key].blank?
  end
end
