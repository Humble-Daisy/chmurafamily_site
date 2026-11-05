### Changed

- Template specs no longer open a fork's public pages, and a check keeps it that way. `spec/system/pages/**` and `spec/requests/pages_spec.rb` are fork-owned; `spec/system/static_pages_spec.rb` is split between that folder and `spec/system/app_chrome_spec.rb`.
