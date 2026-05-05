# Minimal container image for the walking-stick Hello World service.
#
# Single-stage on python:3.12-alpine — the whole image is < 60 MB, builds in
# < 10 seconds, and has no application dependencies (stdlib only). The point
# is to keep the demo focused on the platform: pipeline, IaC, observability.
FROM python:3.12-alpine

# Run as a non-root user. Cloud Run does not enforce this, but it's a baseline
# the platform team should make every golden-path image follow.
RUN addgroup -S app && adduser -S -G app app
USER app

WORKDIR /app
COPY --chown=app:app server.py ./

# Cloud Run injects PORT at runtime; 8080 is the default and what the
# Terraform startup/liveness probes hit.
ENV PORT=8080
EXPOSE 8080

CMD ["python", "-u", "server.py"]
