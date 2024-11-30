Rails.application.config.after_initialize do
  Rails::HTML5::SafeListSanitizer.allowed_tags.merge(%w[ table tr td th thead tbody details summary ])
end
