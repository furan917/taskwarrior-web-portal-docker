# taskwarrior-web-portal-docker

Docker image pairing [Taskwarrior 3.x](https://taskwarrior.org) with the [taskwarrior-web-portal](https://github.com/furan917/taskwarrior-web-portal) web UI. Available as an Unraid Community Application.

## What's in the image

- **Taskwarrior 3.x** — built from source at image build time
- **taskwarrior-web-portal** — pre-built binary pulled from the latest GitHub release
- Entrypoint that handles PUID/PGID privilege dropping and first-run setup

## Quick start

```yaml
services:
  taskwarrior-web-portal:
    image: ghcr.io/furan917/taskwarrior-web-portal-docker:latest
    container_name: taskwarrior-web-portal
    environment:
      - PUID=1000
      - PGID=1000
      - TWC_SERVER_URL=        # optional: http://192.168.1.10:8007
      - TWC_PASSPHRASE=        # required if TWC_SERVER_URL is set
    volumes:
      - ./data:/config
    ports:
      - "5050:5050"
    restart: unless-stopped
```

Open `http://localhost:5050` after the container starts.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `PUID` | `99` | UID the process runs as |
| `PGID` | `100` | GID the process runs as |
| `TWC_SERVER_URL` | — | TaskChampion sync server URL (optional) |
| `TWC_PASSPHRASE` | — | Encryption passphrase for sync (required with `TWC_SERVER_URL`) |
| `TWP_BIND_PORT` | `5050` | Port the web portal binds to inside the container |

## Sync setup

On first start the container generates a client UUID and prints it to the container log:

```
================================================================
 Taskwarrior client UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
 Add this to your sync server's CLIENT_ID list.
================================================================
```

Add that UUID to your [taskchampion-sync-server](https://github.com/furan917/taskchampion-sync-wrapper) `CLIENT_ID` env var, then set `TWC_SERVER_URL` and `TWC_PASSPHRASE` here and restart. All task data is encrypted client-side — the sync server never sees plaintext.

## Security

This app has no built-in authentication. It is designed for **trusted LAN access only**.

If you expose it outside your local network, place it behind a reverse proxy with authentication — for example:
- **Nginx Proxy Manager** with HTTP Basic Auth
- **Cloudflare Tunnel** with Authelia or Authentik

## Data persistence

Everything lives in `/config`:

| Path | Contents |
|---|---|
| `/config/task/` | Taskwarrior task database |
| `/config/taskrc` | Generated Taskwarrior config (do not hand-edit) |
| `/config/client_id` | Your sync client UUID |
| `/config/state/` | Web portal logs |

Back up the entire `/config` mount. The `client_id` file in particular must not be lost if you are using sync — it is the identifier tied to your encrypted data on the server.
