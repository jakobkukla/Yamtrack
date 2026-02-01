#
### Build stage
#
FROM python:3.12-alpine3.21 AS builder
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Omit development dependencies
ENV UV_NO_DEV=1
# Compile source files to bytecode
ENV UV_COMPILE_BYTECODE=1
# Don't use the cache
ENV UV_NO_CACHE=1

WORKDIR /yamtrack

COPY ./pyproject.toml ./uv.lock /yamtrack
RUN uv sync --locked --no-install-project --no-editable

COPY ./src /yamtrack/src
RUN .venv/bin/python ./src/manage.py collectstatic --noinput

#
### Final image
#
FROM python:3.12-alpine3.21

# https://stackoverflow.com/questions/58701233/docker-logs-erroneously-appears-empty-until-container-stops
ENV PYTHONUNBUFFERED=1

# Define build argument with default value
ARG VERSION=dev
# Set it as an environment variable
ENV VERSION=$VERSION

COPY ./entrypoint.sh /entrypoint.sh
COPY ./supervisord.conf /etc/supervisord.conf
COPY ./nginx.conf /etc/nginx/nginx.conf

WORKDIR /yamtrack

RUN apk add --no-cache nginx shadow supervisor \
    && chmod +x /entrypoint.sh \
    # create user abc for later PUID/PGID mapping
    && useradd -U -M -s /bin/sh abc \
    # Create required nginx directories and set permissions
    && mkdir -p /var/log/nginx \
    && mkdir -p /var/lib/nginx/body

# Copy from build stage and put executables in PATH
COPY --from=builder --chown=abc:abc /yamtrack/src /yamtrack
COPY --from=builder --chown=abc:abc /yamtrack/.venv /yamtrack/.venv
ENV PATH="/yamtrack/.venv/bin:$PATH"

EXPOSE 8000

CMD ["/entrypoint.sh"]

HEALTHCHECK --interval=45s --timeout=15s --start-period=30s --retries=5 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:8000/health/ || exit 1
