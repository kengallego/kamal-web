class Projects::WebhookTokensController < Projects::BaseController
  def create
    @project.regenerate_deploy_webhook_token
    redirect_to project_settings_path(@project), notice: "Deploy webhook URL regenerated. Update it wherever it is used."
  end
end
