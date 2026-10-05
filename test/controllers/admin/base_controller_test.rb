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

  def with_admin_env(rails_env, user = nil, password = nil)
    original_env = Rails.env
    original_user = ENV["ADMIN_USER"]
    original_password = ENV["ADMIN_PASSWORD"]
    Rails.env = rails_env
    ENV["ADMIN_USER"] = user
    ENV["ADMIN_PASSWORD"] = password
    yield
  ensure
    Rails.env = original_env
    ENV["ADMIN_USER"] = original_user
    ENV["ADMIN_PASSWORD"] = original_password
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
end
