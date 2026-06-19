source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "propshaft"
gem "mysql2", "~> 0.5"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "tailwindcss-rails"
gem "solid_cache"
gem "solid_queue"
gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false

# HTTP client
gem "faraday"

# Pagination
gem "pagy"

# Structured logging
gem "lograge"

# Timezone
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "minitest"
  gem "webmock"
  gem "simplecov", require: false
  gem "capybara"
  gem "selenium-webdriver"
  gem "sorbet"
  gem "tapioca", require: false
end

group :development do
  gem "web-console"
  gem "lefthook", require: false
  gem "syntax_tree", require: false
  gem "sorbet-runtime"
end

group :test do
  gem "rails-controller-testing"
end
