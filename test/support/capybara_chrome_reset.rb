require "action_dispatch/system_test_case"

# Capybara 3.40.0 ends ChromeDriver#reset! with Storage.clearDataForOrigin for origin "*", which Chrome 158
# rejects, so every system test errored in teardown (teamcapybara/capybara#2865). This app keeps nothing in
# Web Storage, so clearing every cookie is all that reset! has to do.
# shortcut: assumes the app uses no Web Storage; drop this once a Capybara release fixes reset! for Chrome 158.
module CapybaraChromeReset
  private

  def execute_cdp(cmd, params = {})
    return super unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"

    super("Network.clearBrowserCookies")
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(CapybaraChromeReset)
