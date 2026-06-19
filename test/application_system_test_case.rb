require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 900]

  setup { WebMock.allow_net_connect!(allow_localhost: true) }

  teardown { WebMock.disable_net_connect! }

  private

  def admin_basic_auth
    page.driver.browser.manage.add_cookie(name: "test", value: "1")
    encoded = Base64.strict_encode64("admin:changeme")
    page.driver.header("Authorization", "Basic #{encoded}")
  end

  def visit_admin(path)
    visit "http://admin:changeme@#{Capybara.current_session.server.host}:#{Capybara.current_session.server.port}#{path}"
  end
end
