Rails.application.config.after_initialize do
  Flightwatch::WorkspaceListener.start unless Rails.env.test?
end
