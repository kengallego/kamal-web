# Lets CI or a git host trigger a deploy:
#   curl -X POST https://kamal-ui.example.com/hooks/deploy/TOKEN?destination=production
# GitHub/GitLab push payloads are accepted; pushes to other branches are ignored.
class DeployHooksController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection
  rate_limit to: 30, within: 1.minute

  def create
    project = Project.find_by(deploy_webhook_token: params[:token].to_s)
    return head :not_found unless project && params[:token].to_s.length >= 24

    if (ref = params[:ref].presence) && ref != "refs/heads/#{project.branch}" && ref != project.branch
      return render json: { status: "ignored", reason: "ref #{ref} is not #{project.branch}" }, status: :accepted
    end

    run = project.command_runs.new(kind: "deploy", destination: params[:destination], trigger: "webhook")

    if run.save
      render json: { status: "queued", run_id: run.id }, status: :created
    else
      render json: { status: "rejected", errors: run.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
