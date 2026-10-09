# Kamal UI

A self-hosted web dashboard for [Kamal](https://kamal-deploy.org). Point it at the repositories you deploy with Kamal and you can deploy, roll back, read logs, inspect kamal-proxy and watch server health from the browser, together with your team.

It runs as one Docker container on any server. It has no external dependencies and nothing to pay for.

## Features

- **Projects from git or a mounted folder.** Kamal UI clones your repository (over SSH deploy keys or HTTPS tokens), pulls before every command and detects destinations such as `config/deploy.staging.yml` automatically.
- **Deploy, redeploy, rollback.** Output streams live, past versions are offered for rollback, and runs can be canceled. Only one server-changing command runs per project at a time.
- **Every everyday Kamal command:** app boot/start/stop/details/logs/exec, maintenance and live mode, accessories, proxy, deploy lock, prune, registry login, server bootstrap, setup and audit.
- **Rails runner.** Evaluates Ruby inside the running app container.
- **Monitoring.** CPU, memory, disk and load for every host, sampled each minute over SSH and kept for 24 hours, plus the running containers.
- **Proxy view.** kamal-proxy routes, TLS state and recent requests with status filters, median and p95 latency.
- **Secrets.** Encrypted environment variables (per destination) for `.kamal/secrets`, and secret files such as `config/master.key`. SSH keys are encrypted and only loaded into a temporary ssh-agent while a command runs.
- **Team access.** Users with viewer, deployer and admin roles.
- **Notifications.** Slack, Discord or JSON webhooks when an operation finishes, plus browser notifications.
- **Deploy webhook.** Trigger deploys from CI or a GitHub/GitLab push.
- **Status board.** A read-only page for a TV or for stakeholders, behind a secret URL.

## Quick start

On a server with Docker:

```sh
mkdir kamal-ui && cd kamal-ui
curl -O https://raw.githubusercontent.com/kengallego/kamal-ui/main/compose.yml
docker compose up -d
docker compose logs kamal-ui
```

On first boot the logs show the admin account:

```
===================================================================
  Kamal UI admin account created
    Email:    admin@example.com
    Password: 8nW2…
    This password is shown only once. Change it after signing in.
===================================================================
```

Open `http://<server>:3000` and sign in. To choose the credentials yourself, set `ADMIN_EMAIL` and `ADMIN_PASSWORD` before the first start (see `.env.example`). They are only used while the instance has no users.

### Adding a project

1. **New project.** Enter the repository URL and branch. Private repositories need either an HTTPS token or a deploy key.
2. **SSH private key.** This is the key Kamal uses to reach your servers. Without a passphrase.
3. **Settings → Environment variables.** Add whatever your `.kamal/secrets` reads, such as `KAMAL_REGISTRY_PASSWORD` or `RAILS_MASTER_KEY`. Use secret files for `config/master.key`.
4. Press **Sync**, then **Deploy**.

## Configuration

All settings are environment variables in `compose.yml`:

| Variable | Default | |
|---|---|---|
| `ADMIN_EMAIL` | `admin@example.com` | First admin, only created when there are no users |
| `ADMIN_PASSWORD` | random | Printed once to the logs when empty |
| `KAMAL_UI_PORT` | `3000` | Host port |
| `KAMAL_UI_URL` | | Public URL, used in notification links and emails |
| `ASSUME_SSL` / `FORCE_SSL` | `false` | Set to `true` behind an HTTPS proxy |
| `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `MAILER_FROM` | | Enables password reset emails |
| `SECRET_KEY_BASE` | generated | Generated and stored in the volume when unset |

### HTTPS

Put Kamal UI behind any reverse proxy (Caddy, Traefik, nginx or kamal-proxy) and set `ASSUME_SSL=true`, `FORCE_SSL=true` and `KAMAL_UI_URL`. Live output uses WebSockets, so the proxy must allow upgrades on `/cable`.

### Building images

Kamal builds images with Docker. The default `compose.yml` mounts the host's Docker socket for this. **Anything that can use that socket controls the host, so only give Kamal UI accounts to people you trust with the server.** If all your projects use a [remote builder](https://kamal-deploy.org/docs/configuration/builder/) you can remove the socket mount.

### Mounted projects

If your projects already live on the server, mount them and add them as **Mounted folder**:

```yaml
volumes:
  - /srv/projects:/projects
```

### Backups

Everything is in the `kamal_ui_storage` volume: SQLite databases, the generated `secret_key_base` that encrypts keys and variables, and git clones. Back up the whole volume. Without `secret_key_base` the stored secrets can't be decrypted.

### Lost password

```sh
docker compose exec kamal-ui bin/rails "kamal_ui:reset_password[admin@example.com]"
```

## Security model

- Secrets (SSH keys, tokens, variables, files, webhook URLs) are encrypted with Active Record encryption and never rendered back into forms.
- Commands come from a fixed catalog and run without a shell. Options are validated, and each command needs a minimum role.
- Child processes get an allowlisted environment, so the instance's own secrets never reach your project's hooks.
- Deploy webhook and status board URLs use long random tokens and can be regenerated.

## Development

```sh
bin/setup
bin/dev            # http://localhost:3000
bundle exec rspec
```

The admin account for development is created with `bin/rails kamal_ui:bootstrap` and printed to the terminal.

Built with Rails 8, Hotwire, Tailwind, SQLite and Solid Queue/Cable/Cache. Kamal runs as a subprocess, using the version pinned in this app's `Gemfile.lock`.

## License

MIT
