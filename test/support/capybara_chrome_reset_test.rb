require "test_helper"
require_relative "capybara_chrome_reset"

class CapybaraChromeResetTest < ActiveSupport::TestCase
  # Stands in for the Selenium browser and records the CDP commands the driver sends
  class FakeBrowser
    attr_reader :calls

    def initialize
      @calls = []
    end

    def execute_cdp(cmd, **params)
      @calls << [cmd, params]
    end
  end

  # include, not extend: ChromeDriver.extended reaches into a live Selenium bridge
  class FakeDriver
    include Capybara::Selenium::Driver::ChromeDriver
    attr_reader :browser

    def initialize(browser)
      @browser = browser
    end
  end

  setup do
    @browser = FakeBrowser.new
    @driver = FakeDriver.new(@browser)
  end

  test "the wildcard storage clear that Chrome 158 rejects becomes a clear of every cookie" do
    @driver.send(:execute_cdp, "Storage.clearDataForOrigin", origin: "*", storageTypes: "cookies,local_storage")

    assert_equal [["Network.clearBrowserCookies", {}]], @browser.calls
  end

  test "a storage clear for a real origin is sent unchanged" do
    @driver.send(:execute_cdp, "Storage.clearDataForOrigin", origin: "http://127.0.0.1:3000", storageTypes: "cookies")

    assert_equal [["Storage.clearDataForOrigin", { origin: "http://127.0.0.1:3000", storageTypes: "cookies" }]],
                 @browser.calls
  end

  test "other CDP commands are sent unchanged" do
    @driver.send(:execute_cdp, "Network.clearBrowserCache")

    assert_equal [["Network.clearBrowserCache", {}]], @browser.calls
  end
end
