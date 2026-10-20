namespace :kamal_web do
  desc "Check the password, close commands interrupted by a restart and detect Kamal apps on this server"
  task bootstrap: :environment do
    if (problem = AccessPassword.problem)
      abort "Kamal Web can't start: #{problem}"
    end

    SshHostKeys.write_config!
    CommandRun.interrupt_stale!
    ConsoleSession.close_stale!

    if Setting.instance.ensure_ssh_key!
      puts <<~TEXT
        ===================================================================
          Kamal Web SSH key created. To let Kamal Web manage the Kamal apps on
          this server, run this from your Kamal Web checkout:

            #{Setting::AUTHORIZE_THIS_SERVER}
        ===================================================================
      TEXT
    end

    CheckForUpdatesJob.perform_later if CheckForUpdatesJob.enabled? && Setting.instance.update_checked_at.nil?
    Rake::Task["kamal_web:discover"].invoke
  end

  desc "Deploy a Kamal Web release over this instance. Run by SelfUpdate, in a helper container"
  task :self_update, [ :tag ] => :environment do |_, args|
    SelfUpdate.new.perform(args.fetch(:tag))
  end

  desc "Add an account, or give an existing one a new password and sign it out everywhere, for when nobody can sign in"
  task :account, %i[ email name ] => :environment do |_, args|
    password = SecureRandom.base58(20)
    user = User.find_or_initialize_by(email_address: args.fetch(:email).strip.downcase)
    user.update!(name: args[:name].presence || user.name.presence || user.email_address, password: password)
    user.sessions.destroy_all
    AuditEvent.record("users#reset", actor: "bin/rails kamal_web:account", user: nil, subject: user)
    puts "#{user.label} can sign in with this password: #{password}"
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
    # Detection must never keep Kamal Web from booting.
    puts "Kamal app detection failed: #{error.class}: #{error.message}"
  end
end
