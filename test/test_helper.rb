ENV["RAILS_ENV"] ||= "test"

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    minimum_coverage 80
    # rails testコマンドとruby -Itestの両方で正しくマージされるようcommand_nameを統一
    command_name "Unit Tests"
  end
end

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require_relative "support/mock_sunabar"

module ActiveSupport
  class TestCase
    include MockSunabar

    # カバレッジ計測時は並列実行を完全に無効化(SimpleCovの結果がマージされないため)
    parallelize(workers: :number_of_processors) unless ENV["COVERAGE"]
    fixtures :all
  end
end
