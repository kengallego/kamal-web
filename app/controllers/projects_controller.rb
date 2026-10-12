class ProjectsController < ApplicationController
  before_action :set_project, only: %i[ show edit update destroy sync ]

  def index
    redirect_to root_path
  end

  def show
    @destination = selected_destination
    @config = @project.config_for(@destination)
    @recent_runs = @project.command_runs.where(destination: @destination).latest_first.limit(10)
    @latest_metrics = @project.server_metrics.where(id: @project.server_metrics.recent.group(:host).select("MAX(id)")).index_by(&:host)
    @checks = ProjectChecks.new(@project, @destination, @latest_metrics).all
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)

    if @project.save
      sync_after_save
      redirect_to @project, notice: sync_notice(t("flash.projects.created"))
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attributes = project_params
    # Leaving a secret field empty keeps the stored value.
    %i[ ssh_private_key git_ssh_private_key git_access_token ].each { |key| attributes.delete(key) if attributes[key].blank? }

    if @project.update(attributes)
      sync_after_save
      redirect_to @project, notice: sync_notice(t("flash.projects.updated"))
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy!
    redirect_to root_path, notice: t("flash.projects.deleted"), status: :see_other
  end

  def sync
    ProjectWorkspace.new(@project).sync!
    redirect_back fallback_location: @project, notice: t("flash.projects.synced")
  rescue ProjectWorkspace::Error, SshAgent::Error => error
    redirect_back fallback_location: @project, alert: t("flash.projects.sync_failed", error: error.message.truncate(500))
  end

  private
    def set_project
      @project = Project.find(params[:id])
    end

    def selected_destination
      requested = params[:destination].presence
      @project.destinations.include?(requested) ? requested : @project.destinations.first
    end

    def project_params
      params.expect(project: [ :name, :source_kind, :repository_url, :branch, :local_path, :config_file,
        :ssh_private_key, :git_ssh_private_key, :git_access_token, :notification_webhook_url,
        :notification_format, :monitoring_enabled, protected_destinations: [] ])
    end

    def sync_after_save
      ProjectWorkspace.new(@project).sync!
    rescue ProjectWorkspace::Error, SshAgent::Error
      # The error is stored on the project and shown on its page.
    end

    def sync_notice(message)
      @project.sync_error.present? ? t("flash.projects.first_sync_failed", message: message) : message
    end
end
