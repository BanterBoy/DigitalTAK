# DigitalTAK docs – Jekyll local development container
#
# Matches the github-pages gem Ruby requirement (3.1).
# --force_polling is required on Windows: Docker Desktop volumes do not support
# inotify, so native file watching (--watch) never triggers without it.
#
# Build context: docs/ directory
#   docker compose sets context: . so COPY paths resolve from docs/

FROM ruby:3.1-slim

RUN apt-get update && \
    apt-get install -y build-essential git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /srv/jekyll

COPY Gemfile Gemfile.lock* ./
RUN bundle install

CMD ["bundle", "exec", "jekyll", "serve", \
     "--host", "0.0.0.0", \
     "--watch", "--force_polling", "--livereload"]
