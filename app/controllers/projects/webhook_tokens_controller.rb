class Projects::WebhookTokensController < Projects::BaseController
  def create
    @project.regenerate_deploy_webhook_token
    @project.regenerate_deploy_webhook_secret
    redirect_to project_settings_path(@project), notice: t("flash.webhook_tokens.regenerated")
  end
end
