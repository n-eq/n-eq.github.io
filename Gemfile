source "https://rubygems.org"
group :jekyll_plugins do
  gem "jekyll-feed"
  gem "jekyll-seo-tag"
  gem "jekyll-last-modified-at"
  gem "jekyll-toc"
  # Lock `http_parser.rb` gem to `v0.6.x` on JRuby builds since newer versions of the gem
  # do not have a Java counterpart.
  gem "http_parser.rb", "~> 0.6.0", :platforms => [:jruby]

  gem "jekyll-theme-midnight", "~> 0.0.4"
  gem "kramdown-parser-gfm"
  gem "webrick"
end

# Windows and JRuby does not include zoneinfo files, so bundle the tzinfo-data gem
# and associated library.
platforms :mingw, :x64_mingw, :mswin, :jruby do
  gem "tzinfo", ">= 1", "< 3"
  gem "tzinfo-data"
end
