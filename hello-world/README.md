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
