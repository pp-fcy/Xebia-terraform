# Sample service — Hello World

The minimal HTTP service that the walking-stick IDP deploys. Returns
`Hello World` on `/` and `ok` on `/healthz`. Stdlib-only Python (no
dependencies) so the demo's attention stays on the platform.

## Endpoints

```
GET /         → 200 "Hello World\n"
GET /healthz  → 200 "ok\n"
```

## Run locally

```bash
python3 server.py            # listens on 0.0.0.0:8080
PORT=9000 python3 server.py  # override the port

curl http://localhost:8080/
curl http://localhost:8080/healthz
```

## Build the container

Same Dockerfile that CI uses:

```bash
docker build -t hello-world .
docker run --rm -p 8080:8080 hello-world
```

The image is published to Artifact Registry by `.github/workflows/build-image.yml`
on every push to `main` that touches this directory.

## Why so small

This is the **sample service** in the assessment's "walking stick" demo. The
platform's value isn't in this service — it's in the pipeline, the IaC, the
observability, and the operating model that gets it from `git push` to
production safely. A bigger sample app would distract from that.

A product team replaces `server.py` and `Dockerfile` with their real workload
and inherits everything else for free. See
[../docs/SERVICE_TEMPLATE.md](../docs/SERVICE_TEMPLATE.md).
