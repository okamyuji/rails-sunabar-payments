require "test_helper"

# CI のテストは rake 経由（bin/rails db:setup test）で動き、rake では config.rake_eager_load が優先されて
# config.eager_load = ENV["CI"].present? が効かない。そのためここで明示的に eager load を検査する。
class ZeitwerkComplianceTest < ActiveSupport::TestCase
  test "eager loads all files without errors" do
    assert_nothing_raised { Rails.application.eager_load! }
  end
end
