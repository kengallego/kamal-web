# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_22_090000) do
  create_table "alerts", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "kind", null: false
    t.string "subject", default: "", null: false
    t.text "message"
    t.datetime "opened_at", null: false
    t.datetime "resolved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "kind", "subject"], name: "index_alerts_open", unique: true, where: "resolved_at IS NULL"
    t.index ["project_id"], name: "index_alerts_on_project_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.integer "user_id"
    t.string "actor", null: false
    t.string "action", null: false
    t.integer "project_id"
    t.string "subject_type"
    t.integer "subject_id"
    t.json "details", default: {}, null: false
    t.string "ip_address"
    t.datetime "created_at", null: false
    t.index ["created_at"], name: "index_audit_events_on_created_at"
    t.index ["project_id"], name: "index_audit_events_on_project_id"
    t.index ["user_id"], name: "index_audit_events_on_user_id"
  end

  create_table "command_runs", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "destination"
    t.string "kind", null: false
    t.json "options", default: {}, null: false
    t.string "status", default: "queued", null: false
    t.string "trigger", default: "manual", null: false
    t.integer "exit_code"
    t.integer "pid"
    t.text "output", default: "", null: false
    t.string "git_revision"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["project_id", "created_at"], name: "index_command_runs_on_project_id_and_created_at"
    t.index ["project_id"], name: "index_command_runs_on_project_id"
    t.index ["status"], name: "index_command_runs_on_status"
    t.index ["user_id"], name: "index_command_runs_on_user_id"
  end

  create_table "console_sessions", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "destination"
    t.string "kind", null: false
    t.string "host"
    t.datetime "started_at"
    t.datetime "ended_at"
    t.integer "exit_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["project_id"], name: "index_console_sessions_on_project_id"
    t.index ["user_id"], name: "index_console_sessions_on_user_id"
  end

  create_table "database_attachments", force: :cascade do |t|
    t.integer "database_id", null: false
    t.integer "project_id", null: false
    t.integer "environment_variable_id"
    t.string "destination"
    t.string "variable", null: false
    t.string "database_name"
    t.string "username"
    t.text "password"
    t.integer "redis_index"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["database_id", "database_name"], name: "index_database_attachments_on_database_id_and_database_name", unique: true, where: "database_name IS NOT NULL"
    t.index ["database_id"], name: "index_database_attachments_on_database_id"
    t.index ["environment_variable_id"], name: "index_database_attachments_on_environment_variable_id"
    t.index ["project_id", "destination", "variable"], name: "idx_on_project_id_destination_variable_9a42ab6bff", unique: true
    t.index ["project_id"], name: "index_database_attachments_on_project_id"
  end

  create_table "databases", force: :cascade do |t|
    t.string "name", null: false
    t.string "engine", null: false
    t.string "source", null: false
    t.integer "server_id"
    t.string "container_name"
    t.string "image"
    t.string "admin_user"
    t.text "password"
    t.text "url"
    t.integer "public_port"
    t.string "status", default: "unknown", null: false
    t.text "status_message"
    t.datetime "checked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_databases_on_name", unique: true
    t.index ["server_id", "container_name"], name: "index_databases_on_server_id_and_container_name", unique: true, where: "container_name IS NOT NULL"
    t.index ["server_id"], name: "index_databases_on_server_id"
  end

  create_table "environment_variables", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "key", null: false
    t.text "value"
    t.string "destination"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "destination", "key"], name: "idx_on_project_id_destination_key_aac1f2e10f", unique: true
    t.index ["project_id"], name: "index_environment_variables_on_project_id"
  end

  create_table "health_checks", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "url", null: false
    t.integer "status_code"
    t.float "duration_ms"
    t.text "error"
    t.datetime "certificate_expires_at"
    t.datetime "checked_at", null: false
    t.index ["project_id", "url", "checked_at"], name: "index_health_checks_on_project_id_and_url_and_checked_at"
    t.index ["project_id"], name: "index_health_checks_on_project_id"
  end

  create_table "hourly_metrics", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "host", null: false
    t.datetime "hour", null: false
    t.float "cpu_percent"
    t.float "load_percent"
    t.float "memory_percent"
    t.float "disk_percent"
    t.integer "samples", default: 0, null: false
    t.float "app_cpu_percent"
    t.float "app_memory_percent"
    t.float "app_disk_percent"
    t.index ["project_id", "host", "hour"], name: "index_hourly_metrics_on_project_id_and_host_and_hour", unique: true
    t.index ["project_id"], name: "index_hourly_metrics_on_project_id"
  end

  create_table "project_files", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "path", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "path"], name: "index_project_files_on_project_id_and_path", unique: true
    t.index ["project_id"], name: "index_project_files_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "name", null: false
    t.string "source_kind", default: "git", null: false
    t.string "repository_url"
    t.string "branch", default: "main", null: false
    t.string "local_path"
    t.string "config_file", default: "config/deploy.yml", null: false
    t.text "ssh_private_key"
    t.text "git_ssh_private_key"
    t.text "git_access_token"
    t.string "deploy_webhook_token", null: false
    t.string "notification_webhook_url"
    t.string "notification_format", default: "generic", null: false
    t.boolean "monitoring_enabled", default: true, null: false
    t.json "config_snapshots", default: {}, null: false
    t.string "git_revision"
    t.datetime "synced_at"
    t.text "sync_error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "discovered_service"
    t.text "discovered_files"
    t.json "discovered_versions", default: {}, null: false
    t.json "protected_destinations", default: [], null: false
    t.string "deploy_webhook_secret"
    t.index ["deploy_webhook_token"], name: "index_projects_on_deploy_webhook_token", unique: true
    t.index ["discovered_service"], name: "index_projects_on_discovered_service", unique: true, where: "discovered_service IS NOT NULL"
    t.index ["name"], name: "index_projects_on_name", unique: true
  end

  create_table "server_metrics", force: :cascade do |t|
    t.integer "project_id", null: false
    t.string "host", null: false
    t.float "cpu_percent"
    t.float "load_1"
    t.float "load_5"
    t.float "load_15"
    t.integer "cpu_count"
    t.bigint "memory_total"
    t.bigint "memory_used"
    t.bigint "disk_total"
    t.bigint "disk_used"
    t.json "containers", default: [], null: false
    t.text "error"
    t.datetime "collected_at", null: false
    t.float "app_cpu_percent"
    t.bigint "app_memory_used"
    t.bigint "app_disk_used"
    t.index ["project_id", "host", "collected_at"], name: "index_server_metrics_on_project_id_and_host_and_collected_at"
    t.index ["project_id"], name: "index_server_metrics_on_project_id"
  end

  create_table "servers", force: :cascade do |t|
    t.string "host", null: false
    t.string "name"
    t.string "ssh_user"
    t.integer "ssh_port"
    t.text "notes"
    t.datetime "checked_at"
    t.text "check_error"
    t.string "system_info"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["host"], name: "index_servers_on_host", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.boolean "status_board_enabled", default: false, null: false
    t.string "status_board_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "ssh_private_key"
    t.text "ssh_public_key"
    t.json "ignored_services", default: [], null: false
    t.string "latest_version"
    t.string "latest_version_url"
    t.datetime "update_checked_at"
    t.integer "alert_disk_percent", default: 90, null: false
    t.integer "alert_memory_percent", default: 90, null: false
    t.boolean "scheduled_backups_enabled", default: false, null: false
    t.integer "scheduled_backups_keep", default: 7, null: false
    t.boolean "auto_update_enabled", default: false, null: false
    t.string "auto_update_version"
    t.string "auto_update_status"
    t.datetime "auto_update_started_at"
    t.datetime "auto_update_finished_at"
    t.text "auto_update_output"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.text "otp_secret"
    t.datetime "last_signed_in_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "alerts", "projects"
  add_foreign_key "audit_events", "projects", on_delete: :nullify
  add_foreign_key "audit_events", "users", on_delete: :nullify
  add_foreign_key "command_runs", "projects"
  add_foreign_key "command_runs", "users", on_delete: :nullify
  add_foreign_key "console_sessions", "projects"
  add_foreign_key "console_sessions", "users", on_delete: :nullify
  add_foreign_key "database_attachments", "databases"
  add_foreign_key "database_attachments", "environment_variables", on_delete: :nullify
  add_foreign_key "database_attachments", "projects"
  add_foreign_key "databases", "servers"
  add_foreign_key "environment_variables", "projects"
  add_foreign_key "health_checks", "projects"
  add_foreign_key "hourly_metrics", "projects"
  add_foreign_key "project_files", "projects"
  add_foreign_key "server_metrics", "projects"
  add_foreign_key "sessions", "users"
end
