class DatabasesController < ApplicationController
  CREATABLE = {
    "created" => %i[ name server_id image public_port ],
    "existing" => %i[ name server_id container_name admin_user password public_port ],
    "external" => %i[ name url ]
  }.freeze
  # A created container keeps the name and password it was started with.
  EDITABLE = {
    "created" => %i[ name public_port ],
    "existing" => %i[ name container_name admin_user password public_port ],
    "external" => %i[ name url ]
  }.freeze

  before_action :set_database, only: %i[ show edit update destroy check ]

  def index
    @databases = Database.ordered.includes(:server, attachments: :project)
  end

  def show
    @attachments = @database.attachments.includes(:project).order(:created_at)
    @projects = Project.ordered.to_a
  end

  def new
    source = params[:source].presence_in(Database::SOURCES) || "created"
    engine = params[:engine].presence_in(Database::ENGINES) || "postgresql"
    @database = Database.new(source: source, engine: engine, image: Database::IMAGES[engine].first)
  end

  def create
    source = params.dig(:database, :source).presence_in(Database::SOURCES) || "created"
    @database = Database.new(database_params.slice(:engine, :source, *CREATABLE.fetch(source)))

    if @database.save
      if @database.created?
        @database.update!(status: "provisioning")
        ProvisionDatabaseJob.perform_later(@database)
      else
        @database.check!
      end
      redirect_to @database, notice: t("flash.saved", name: @database.name)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attributes = database_params.slice(*EDITABLE.fetch(@database.source))
    attributes.delete(:password) if attributes[:password].blank?
    attributes.delete(:url) if attributes[:url].blank?

    if @database.update(attributes)
      # Publishing another port means running the container again.
      if @database.created? && @database.saved_change_to_public_port?
        @database.update!(status: "provisioning")
        ProvisionDatabaseJob.perform_later(@database)
      end
      redirect_to @database, notice: t("flash.saved", name: @database.name)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @database.attachments.any?
      redirect_to @database, alert: t("flash.databases.in_use")
    else
      @database.remove!(delete_data: params[:delete_data] == "1")
      redirect_to databases_path, notice: t("flash.deleted", name: @database.name), status: :see_other
    end
  rescue RemoteShell::Error => error
    redirect_to @database, alert: t("flash.databases.failed", error: error.message)
  end

  def check
    @database.check!
    if @database.status == "failed"
      redirect_to @database, alert: t("flash.databases.failed", error: @database.status_message)
    else
      redirect_to @database, notice: t("flash.databases.checked", status: t("databases.statuses.#{@database.status}"))
    end
  end

  private
    def set_database
      @database = Database.find(params[:id])
    end

    def database_params
      params.expect(database: [ :name, :engine, :source, :server_id, :image, :container_name, :admin_user, :password, :url, :public_port ])
    end
end
