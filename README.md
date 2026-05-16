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
      - TWC_CLIENT_ID=         # optional: share with other devices (see Sync setup)
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
| `TWC_CLIENT_ID` | — | Client UUID for sync — set this to share tasks across devices (see below) |
| `TWP_BIND_PORT` | `5050` | Port the web portal binds to inside the container |
| `TWP_DISABLE_HOST_CHECK` | `1` | Set to `0` to enable host/origin allowlist (see Security) |
| `TWP_ALLOWED_HOSTS` | — | Comma-separated allowed hostnames when `TWP_DISABLE_HOST_CHECK=0` |
| `TWP_SECURE_COOKIES` | `0` | Set to `1` when behind a TLS-terminating reverse proxy — adds the `Secure` flag to the CSRF cookie so it is only sent over HTTPS |

## Sync setup

On first start the container generates a client UUID and prints it to the container log:

```
================================================================
 Taskwarrior client UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
 To share tasks across devices, all devices must use this UUID.
================================================================
```

**Important:** in TaskChampion sync, the client UUID is the identifier for your task database on the server. **All devices that should share the same tasks must use the same UUID.** If you add a second device (another container, a desktop install, etc.), set `TWC_CLIENT_ID` on it to match the UUID from your first device.

To find the UUID of an existing install: check the container log, the web portal config page (cog icon), or `cat /config/client_id`.

All task data is encrypted client-side before leaving the container — the sync server never sees plaintext. The `TWC_PASSPHRASE` must also match across all devices.

## Security

This app has no built-in authentication. It is designed for **trusted LAN access only**.

`TWP_DISABLE_HOST_CHECK` is enabled by default (`1`) so the container works out of the box with any hostname or port mapping. Set it to `0` and configure `TWP_ALLOWED_HOSTS` if you want stricter host/origin checking.

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
| `/config/state/` | Sync state |

Back up the entire `/config` mount. The `client_id` file in particular must not be lost if you are using sync — it is the identifier tied to your encrypted data on the server.
