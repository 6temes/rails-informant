source "https://rubygems.org"

gemspec

# json 3.0 made JSON.parse's options keyword-only, which breaks
# ActiveSupport::JSON.decode (it still passes them positionally). Any model with
# a json column raises ArgumentError on read. Drop the pin once a Rails release
# ships the fix.
gem "json", "< 3"
gem "mocha"
gem "rubocop-rails-omakase", require: false
gem "sqlite3"
