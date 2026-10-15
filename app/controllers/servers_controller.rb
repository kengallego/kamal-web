class ServersController < ApplicationController
  before_action :set_server, only: %i[ show edit update destroy check ]

  def index
    @servers = Server.ordered
    @projects = Project.ordered.to_a
    @latest_metrics = ServerMetric.where(id: ServerMetric.recent.group(:project_id, :host).select("MAX(id)")).group_by(&:host)
  end

  def show
    @projects = @server.projects
    @metrics = @server.latest_metrics
  end

  def new
    @server = Server.new
  end

  def create
    @server = Server.new(server_params)

    if @server.save
      @server.check! if Setting.instance.ssh_private_key.present?
      redirect_to @server, notice: t("flash.saved", name: @server.label)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @server.update(server_params)
      redirect_to @server, notice: t("flash.saved", name: @server.label)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Servers in a project's config would be registered again on the next sync.
  def destroy
    if @server.in_use?
      redirect_to @server, alert: t("flash.servers.in_use")
    else
      @server.destroy!
      redirect_to servers_path, notice: t("flash.deleted", name: @server.label), status: :see_other
    end
  end

  def check
    @server.check!
    if @server.check_error
      redirect_to @server, alert: t("flash.servers.check_failed", error: @server.check_error)
    else
      redirect_to @server, notice: t("flash.servers.check_succeeded")
    end
  end

  private
    def set_server
      @server = Server.find(params[:id])
    end

    def server_params
      params.expect(server: [ :host, :name, :ssh_user, :ssh_port, :notes ])
    end
end
