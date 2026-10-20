# Lets CI or a git host trigger a deploy:
#   curl -X POST -H "Authorization: Bearer SECRET" https://kamal-web.example.com/hooks/deploy/TOKEN?destination=production
# The URL's token finds the project; the secret proves who is calling, as a
# bearer token, GitLab's X-Gitlab-Token or the HMAC GitHub signs its payload
# with (X-Hub-Signature-256). Projects created before secrets existed accept
# the URL alone until one is generated in their settings.
# GitHub/GitLab push payloads are accepted; pushes to other branches are ignored.
class DeployHooksController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_allowed_ip
  skip_forgery_protection
  rate_limit to: 30, within: 1.minute

  def create
    project = Project.find_by(deploy_webhook_token: params[:token].to_s)
    return head :not_found unless project && params[:token].to_s.length >= 24
    return head :unauthorized unless authentic?(project)
    return render json: { status: "ignored", reason: "delivery already received" }, status: :accepted if redelivered?

    if (ref = params[:ref].presence) && ref != "refs/heads/#{project.branch}" && ref != project.branch
      return render json: { status: "ignored", reason: "ref #{ref} is not #{project.branch}" }, status: :accepted
    end

    run = project.command_runs.new(kind: "deploy", destination: params[:destination], trigger: "webhook")

    if run.save
      AuditEvent.record("deploy_hooks#create", actor: I18n.t("command_runs.triggers.webhook"), user: nil, project: project, subject: run,
        signed: project.deploy_webhook_secret.present?, ref: params[:ref].presence, delivery: request.headers["X-GitHub-Delivery"].presence)
      render json: { status: "queued", run_id: run.id }, status: :created
    else
      render json: { status: "rejected", errors: run.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private
    def authentic?(project)
      secret = project.deploy_webhook_secret
      return true if secret.blank?

      if (signature = request.headers["X-Hub-Signature-256"].presence)
        expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)
        ActiveSupport::SecurityUtils.secure_compare(signature, expected)
      else
        given = request.headers["X-Gitlab-Token"].presence || request.authorization.to_s[/\ABearer (.+)\z/, 1]
        given.present? && ActiveSupport::SecurityUtils.secure_compare(given, secret)
      end
    end

    # GitHub retries and "Redeliver" resend the same delivery id; a signed
    # payload can't be changed, but it could be replayed.
    def redelivered?
      delivery = request.headers["X-GitHub-Delivery"].presence
      delivery && !Rails.cache.write("deploy-hook-delivery:#{delivery.truncate(100)}", true, unless_exist: true, expires_in: 1.week)
    end
end
