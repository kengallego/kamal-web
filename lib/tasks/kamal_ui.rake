namespace :kamal_ui do
  desc "Create the first admin, close commands interrupted by a restart and detect Kamal apps on this server"
  task bootstrap: :environment do
    AdminBootstrap.new.call
    CommandRun.interrupt_stale!
    ConsoleSession.close_stale!

    if Setting.instance.ensure_ssh_key!
      puts <<~TEXT
        ===================================================================
          Kamal UI SSH key created. To let Kamal UI manage the Kamal apps on
          this server, run this next to compose.yml, as the user Kamal
          deploys with (usually root):

          #{Setting::AUTHORIZE_THIS_SERVER}
        ===================================================================
      TEXT
    end

    Rake::Task["kamal_ui:discover"].invoke
  end

  desc "Detect the Kamal apps running on this server and add them as projects"
  task discover: :environment do
    result = KamalDiscovery.new.call
    if result.error
      puts "Kamal app detection skipped: #{result.error}"
    else
      puts "Detected #{result.apps.size} Kamal app(s) on this server#{", added #{result.created.map(&:name).join(", ")}" if result.created.any?}."
    end
  rescue StandardError => error
    # Detection must never keep Kamal UI from booting.
    puts "Kamal app detection failed: #{error.class}: #{error.message}"
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
