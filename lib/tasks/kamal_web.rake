namespace :kamal_web do
  desc "Check the password, close commands interrupted by a restart and detect Kamal apps on this server"
  task bootstrap: :environment do
    if (problem = AccessPassword.problem)
      abort "Kamal Web can't start: #{problem}"
    end

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
