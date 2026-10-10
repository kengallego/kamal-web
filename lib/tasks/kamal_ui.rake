namespace :kamal_ui do
  desc "Create the first admin if needed and close commands and consoles interrupted by a restart"
  task bootstrap: :environment do
    AdminBootstrap.new.call
    CommandRun.interrupt_stale!
    ConsoleSession.close_stale!
    Setting.instance
  end

  desc "Set a new random password for a user: bin/rails 'kamal_ui:reset_password[admin@example.com]'"
  task :reset_password, [ :email ] => :environment do |_, args|
    user = User.find_by!(email_address: args[:email].to_s.strip.downcase)
    password = SecureRandom.base58(20)
    user.update!(password: password)
    user.sessions.destroy_all
    puts "New password for #{user.email_address}: #{password}"
  end
end
