require "test_helper"

class Admin::BaseControllerTest < ActionDispatch::IntegrationTest
  def basic_auth(user, password)
    {
      "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials(
          user,
          password
        )
    }
  end

  ENV_KEYS = %w[
    ADMIN_USER
    ADMIN_PASSWORD
    API_TOKEN
    SECRET_KEY_BASE_DUMMY
  ].freeze

  def with_admin_env(
    rails_env,
    user = nil,
    password = nil,
    api_token = nil,
    build_dummy: nil
  )
    original_env = Rails.env
    original_vars = ENV.to_h.slice(*ENV_KEYS)
    Rails.env = rails_env
    ENV["ADMIN_USER"] = user
    ENV["ADMIN_PASSWORD"] = password
    ENV["API_TOKEN"] = api_token
    ENV["SECRET_KEY_BASE_DUMMY"] = build_dummy
    yield
  ensure
    Rails.env = original_env
    ENV_KEYS.each { |key| ENV[key] = original_vars[key] }
  end

  test "developmentで資格情報が未設定なら既定のadmin/changemeで入れる" do
    with_admin_env("development") do
      get admin_path, headers: basic_auth("admin", "changeme")
    end

    assert_response :ok
  end

  test "stagingで資格情報が未設定なら既定のadmin/changemeを拒否する" do
    with_admin_env("staging") do
      get admin_path, headers: basic_auth("admin", "changeme")
    end

    assert_response :unauthorized
  end

  test "productionで資格情報が未設定なら既定のadmin/changemeを拒否する" do
    with_admin_env("production") do
      get admin_path, headers: basic_auth("admin", "changeme")
    end

    assert_response :unauthorized
  end

  test "productionで資格情報が未設定なら空の資格情報も拒否する" do
    with_admin_env("production") { get admin_path, headers: basic_auth("", "") }

    assert_response :unauthorized
  end

  test "productionで設定済みの資格情報が一致すれば入れる" do
    with_admin_env("production", "ops", "s3cret") do
      get admin_path, headers: basic_auth("ops", "s3cret")
    end

    assert_response :ok
  end

  test "productionで設定済みの資格情報と一致しなければ拒否する" do
    with_admin_env("production", "ops", "s3cret") do
      get admin_path, headers: basic_auth("ops", "wrong")
    end

    assert_response :unauthorized
  end

  test "developmentでも設定済みの資格情報があれば既定値では入れない" do
    with_admin_env("development", "ops", "s3cret") do
      get admin_path, headers: basic_auth("admin", "changeme")
    end

    assert_response :unauthorized
  end

  def load_admin_credentials_initializer
    load Rails.root.join("config/initializers/admin_credentials.rb")
  end

  test "productionでADMIN_USERが未設定なら起動時チェックが失敗する" do
    error =
      with_admin_env("production", nil, "s3cret") do
        assert_raises(RuntimeError) { load_admin_credentials_initializer }
      end

    assert_equal "ADMIN_USER未設定", error.message
  end

  test "productionでADMIN_PASSWORDが空なら起動時チェックが失敗する" do
    error =
      with_admin_env("production", "ops", "") do
        assert_raises(RuntimeError) { load_admin_credentials_initializer }
      end

    assert_equal "ADMIN_PASSWORD未設定", error.message
  end

  test "productionで資格情報とAPIトークンがすべて設定済みなら起動時チェックは通る" do
    with_admin_env("production", "ops", "s3cret", SecureRandom.hex(16)) do
      assert_nothing_raised { load_admin_credentials_initializer }
    end
  end

  test "productionでAPI_TOKENが未設定なら起動時チェックが失敗する" do
    error =
      with_admin_env("production", "ops", "s3cret") do
        assert_raises(RuntimeError) { load_admin_credentials_initializer }
      end

    assert_equal "API_TOKEN未設定", error.message
  end

  test "productionでAPI_TOKENが空なら起動時チェックが失敗する" do
    error =
      with_admin_env("production", "ops", "s3cret", "") do
        assert_raises(RuntimeError) { load_admin_credentials_initializer }
      end

    assert_equal "API_TOKEN未設定", error.message
  end

  test "productionでもassets:precompileの実行中はAPI_TOKENの未設定で止めない" do
    with_rake_top_level_tasks(["assets:precompile"]) do
      with_admin_env("production", "ops", "s3cret") do
        assert_nothing_raised { load_admin_credentials_initializer }
      end
    end
  end

  def with_rake_top_level_tasks(tasks)
    require "rake"
    original = Rake.application.top_level_tasks
    Rake.application.instance_variable_set(:@top_level_tasks, tasks)
    yield
  ensure
    Rake.application.instance_variable_set(:@top_level_tasks, original)
  end

  test "productionでもassets:precompileの実行中は起動時チェックを飛ばす" do
    with_rake_top_level_tasks(["assets:precompile"]) do
      with_admin_env("production", build_dummy: "1") do
        assert_nothing_raised { load_admin_credentials_initializer }
      end
    end
  end

  test "productionで実行時にSECRET_KEY_BASE_DUMMYが残っていても起動時チェックは外れない" do
    error =
      with_rake_top_level_tasks([]) do
        with_admin_env("production", build_dummy: "1") do
          assert_raises(RuntimeError) { load_admin_credentials_initializer }
        end
      end

    assert_equal "ADMIN_USER未設定", error.message
  end

  test "stagingとdevelopmentでは未設定でも起動時チェックは通る" do
    %w[staging development].each do |env|
      with_admin_env(env) do
        assert_nothing_raised { load_admin_credentials_initializer }
      end
    end
  end
end
