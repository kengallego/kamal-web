class Databases::AttachmentsController < ApplicationController
  before_action :set_database

  def create
    # "project id/destination", with nothing after the slash for every destination.
    project_id, destination = attachment_params[:target].to_s.split("/", 2)
    project = Project.find(project_id)
    @attachment = DatabaseAttachment.new(database: @database, project: project, destination: destination, variable: attachment_params[:variable])
    @attachment.variable = @database.default_variable if @attachment.variable.blank?

    if @attachment.attach!
      redirect_to @database, notice: t("flash.databases.attached", project: project.name, variable: @attachment.variable)
    else
      redirect_to @database, alert: @attachment.errors.full_messages.to_sentence
    end
  rescue RemoteShell::Error => error
    redirect_to @database, alert: t("flash.databases.failed", error: error.message)
  end

  def destroy
    @attachment = @database.attachments.find(params[:id])
    @attachment.detach!(delete_data: params[:delete_data] == "1")
    redirect_to @database, notice: t("flash.databases.detached", project: @attachment.project.name), status: :see_other
  rescue RemoteShell::Error => error
    redirect_to @database, alert: t("flash.databases.failed", error: error.message)
  end

  private
    def set_database
      @database = Database.find(params[:database_id])
    end

    def attachment_params
      params.expect(database_attachment: [ :target, :variable ])
    end
end
