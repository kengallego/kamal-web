require "rails_helper"

RSpec.describe "Backups" do
  # SQLite can't VACUUM INTO inside the transaction tests normally run in.
  self.use_transactional_tests = false

  after do
    FileUtils.rm_f(InstanceBackup::STAGED_PATH)
    Project.destroy_all
    [ AuditEvent, Session, User ].each(&:delete_all)
  end

  it "downloads a backup that can be restored on the next boot" do
    sign_in
    create(:project, name: "shop")

    get backup_path
    expect(response.headers["Content-Disposition"]).to include("kamal-web-backup-")
    archive = Tempfile.new([ "backup", ".tar.gz" ]).tap { |file| file.binmode.write(response.body) && file.flush }

    post backup_path, params: { backup: Rack::Test::UploadedFile.new(archive.path, "application/gzip") }
    expect(response).to redirect_to(edit_settings_path)
    expect(flash[:notice]).to include("restarting")
    expect(InstanceBackup::STAGED_PATH).to exist

    Dir.mktmpdir do |storage|
      File.write(File.join(storage, "production.sqlite3"), "old")
      File.write(File.join(storage, "secret_key_base"), "old-key")
      FileUtils.cp(InstanceBackup::STAGED_PATH, File.join(storage, "restore.tar.gz"))

      system({ "KAMAL_WEB_STORAGE_PATH" => storage }, RbConfig.ruby, Rails.root.join("script/apply_restore.rb").to_s, out: File::NULL, exception: true)

      restored = SQLite3::Database.new(File.join(storage, "production.sqlite3"))
      expect(restored.execute("SELECT name FROM projects").flatten).to eq([ "shop" ])
      expect(File.read(File.join(storage, "secret_key_base"))).to eq(Rails.application.secret_key_base)
      expect(File.read(Dir[File.join(storage, "before-restore-*/production.sqlite3")].first)).to eq("old")
      expect(File).not_to exist(File.join(storage, "restore.tar.gz"))
    end
  end

  it "rejects files that aren't Kamal Web backups" do
    sign_in
    file = Tempfile.new([ "evil", ".tar.gz" ]).tap { |f| f.write("not a tarball") && f.flush }

    post backup_path, params: { backup: Rack::Test::UploadedFile.new(file.path, "application/gzip") }

    expect(flash[:alert]).to eq("The file isn't a .tar.gz archive.")
    expect(InstanceBackup::STAGED_PATH).not_to exist
  end

  it "keeps daily backups in the volume when turned on, rotating old ones" do
    Dir.mktmpdir do |dir|
      stub_const("InstanceBackup::DIRECTORY", Pathname.new(dir))
      ScheduledBackupJob.perform_now
      expect(InstanceBackup.stored).to be_empty

      Setting.instance.update!(scheduled_backups_enabled: true, scheduled_backups_keep: 2)
      %w[ 20261001-030000 20261002-030000 ].each { |stamp| File.write(File.join(dir, "kamal-web-backup-#{stamp}.tar.gz"), "old") }
      ScheduledBackupJob.perform_now

      names = InstanceBackup.stored.map { |path| path.basename.to_s }
      expect(names.size).to eq(2)
      expect(names.last).to eq("kamal-web-backup-20261002-030000.tar.gz")

      sign_in
      get stored_backup_path(name: names.first)
      expect(InstanceBackup.read(Tempfile.new.tap { |f| f.binmode.write(response.body) && f.flush }.path).keys).to include("database.sqlite3")

      get stored_backup_path(name: "..%2F..%2Fconfig%2Fmaster.key")
      expect(response).to have_http_status(:not_found)
    end
  ensure
    Setting.instance.update!(scheduled_backups_enabled: false, scheduled_backups_keep: 7)
  end
end
