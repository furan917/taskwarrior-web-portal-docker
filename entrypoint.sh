#!/bin/sh
set -e

PUID="${PUID:-99}"
PGID="${PGID:-100}"
CONFIG_DIR="${CONFIG_DIR:-/config}"

# --- directory setup ---------------------------------------------------------
mkdir -p "${CONFIG_DIR}/task" "${CONFIG_DIR}/state"

# --- UUID: generate once, persist to /config/client_id ----------------------
# The UUID identifies this client to the taskchampion sync server. It is
# generated once and never changes so existing server-side data stays linked.
# Print it clearly so the user can add it to their sync server's CLIENT_ID.
UUID_FILE="${CONFIG_DIR}/client_id"
if [ ! -f "$UUID_FILE" ]; then
    uuid=$(cat /proc/sys/kernel/random/uuid)
    printf '%s\n' "$uuid" > "$UUID_FILE"
    echo "info: first run — generated new client UUID"
fi
UUID=$(cat "$UUID_FILE")
echo "================================================================"
echo " Taskwarrior client UUID: ${UUID}"
echo " Add this to your sync server's CLIENT_ID list."
echo "================================================================"

# --- .taskrc: write from env -------------------------------------------------
# Always overwritten on container start so env changes are picked up.
# Sensitive values (encryption_secret) are masked in logs; we never echo them.
TASKRC="${CONFIG_DIR}/taskrc"
cat > "$TASKRC" <<EOF
data.location=${CONFIG_DIR}/task
EOF

if [ -n "${TWC_SERVER_URL:-}" ]; then
    if [ -z "${TWC_PASSPHRASE:-}" ]; then
        echo "warning: TWC_SERVER_URL is set but TWC_PASSPHRASE is empty — sync will fail"
    fi
    cat >> "$TASKRC" <<EOF
sync.type=taskchampion
sync.server.url=${TWC_SERVER_URL}
sync.server.client_id=${UUID}
sync.encryption_secret=${TWC_PASSPHRASE:-}
EOF
    echo "info: sync configured to ${TWC_SERVER_URL} with client_id=${UUID}"
else
    echo "info: no TWC_SERVER_URL set — running local-only (no sync)"
fi

# --- permissions -------------------------------------------------------------
chown -R "${PUID}:${PGID}" "${CONFIG_DIR}"
chmod 700 "${CONFIG_DIR}/task"
chmod 600 "$TASKRC"

# --- export runtime env for the web portal binary ----------------------------
export TASKRC
export XDG_STATE_HOME="${CONFIG_DIR}/state"
export TWP_BIND_HOST="${TWP_BIND_HOST:-0.0.0.0}"
export TWP_BIND_PORT="${TWP_BIND_PORT:-5050}"
export TWP_DISABLE_HOST_CHECK="${TWP_DISABLE_HOST_CHECK:-1}"

exec gosu "${PUID}:${PGID}" /usr/local/bin/taskwarrior-web-portal
