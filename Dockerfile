# syntax=docker/dockerfile:1
# check=error=true

# Production image for Kamal Web, deployed with Kamal: see config/deploy.yml.

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.2
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages, plus what Kamal needs at runtime: git, ssh and the
# Docker CLI with buildx to build images through the mounted Docker socket.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y ca-certificates curl git gosu libjemalloc2 libvips openssh-client sqlite3 && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y docker-ce-cli docker-buildx-plugin && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# cosign checks the signature of releases before Update automatically deploys
# them (see app/services/self_update.rb). Pinned by version and checksum.
ARG COSIGN_VERSION=3.1.3
RUN arch=$(dpkg --print-architecture) && \
    case "$arch" in \
      amd64) sum=4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71 ;; \
      arm64) sum=c5d324e091826b0d7a78eb16fef316450b4eb9aaec045611c08ba06f5e73220a ;; \
      *) echo "No cosign checksum for $arch" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o /usr/local/bin/cosign "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${arch}" && \
    echo "$sum  /usr/local/bin/cosign" | sha256sum -c - && \
    chmod 0755 /usr/local/bin/cosign

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    SOLID_QUEUE_IN_PUMA="true" \
    HOME="/rails/storage/home"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# The app runs as the non-root rails user. The entrypoint starts as root only
# to give that user access to the mounted Docker socket and storage volume.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --home-dir /rails/storage/home --no-create-home --shell /bin/bash

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Kamal only deploys images labeled with their service. Kamal adds it to the
# images it builds; this covers the release images Kamal Web updates itself to.
LABEL service="kamal-web"

# Entrypoint prepares the database and creates the first admin.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 CMD curl -fsS http://localhost/up || exit 1

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
