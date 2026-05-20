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
UUID_FILE="${CONFIG_DIR}/client_id"
if [ -n "${TWC_CLIENT_ID:-}" ]; then
    printf '%s\n' "$TWC_CLIENT_ID" > "$UUID_FILE"
    UUID="$TWC_CLIENT_ID"
    echo "info: using client UUID from TWC_CLIENT_ID env var"
elif [ ! -f "$UUID_FILE" ]; then
    uuid=$(cat /proc/sys/kernel/random/uuid)
    printf '%s\n' "$uuid" > "$UUID_FILE"
    echo "info: first run — generated new client UUID"
    UUID="$uuid"
else
    UUID=$(cat "$UUID_FILE")
fi
echo "================================================================"
echo " Taskwarrior client UUID: ${UUID}"
echo " To share tasks across devices, all devices must use this UUID."
echo "================================================================"

# --- taskrc: container-managed block + user settings in one file -------------
# Taskwarrior 3.x does not honour settings from include'd files — data.location
# and sync.* are silently ignored when set via include. Everything must live in
# the primary taskrc.
#
# We protect the container-managed portion with sentinel comments so we can
# regenerate exactly that block on each start without touching user settings
# below the end marker.
TASKRC="${CONFIG_DIR}/taskrc"

# Build the container-managed block
TMP_BLOCK=$(mktemp)
cat > "$TMP_BLOCK" <<EOF
# --- container-managed: do not edit between these markers ---
data.location=${CONFIG_DIR}/task
EOF

if [ -n "${TWC_SERVER_URL:-}" ]; then
    if [ -z "${TWC_PASSPHRASE:-}" ]; then
        echo "warning: TWC_SERVER_URL is set but TWC_PASSPHRASE is empty — sync will fail"
    fi
    cat >> "$TMP_BLOCK" <<EOF
sync.type=taskchampion
sync.server.url=${TWC_SERVER_URL}
sync.server.client_id=${UUID}
sync.encryption_secret=${TWC_PASSPHRASE:-}
EOF
    echo "info: sync configured to ${TWC_SERVER_URL} with client_id=${UUID}"
else
    echo "info: no TWC_SERVER_URL set — running local-only (no sync)"
fi
printf '# --- end container-managed ---\n' >> "$TMP_BLOCK"

if [ -f "$TASKRC" ] && grep -q "^# --- container-managed" "$TASKRC" 2>/dev/null; then
    # Markers present: replace the container block, preserve user content after the end marker
    TMP_USER=$(mktemp)
    awk '/^# --- end container-managed ---$/{found=1; next} found{print}' "$TASKRC" > "$TMP_USER"
    cat "$TMP_BLOCK" > "${TASKRC}.new"
    cat "$TMP_USER" >> "${TASKRC}.new"
    mv "${TASKRC}.new" "$TASKRC"
    rm -f "$TMP_USER"
    echo "info: updated container-managed settings in taskrc"
elif [ -f "$TASKRC" ]; then
    # Old install (no markers): migrate — strip known container-managed keys, prepend block
    TMP_USER=$(mktemp)
    grep -vE "^(data\.location|sync\.|include)=" "$TASKRC" > "$TMP_USER" || true
    cat "$TMP_BLOCK" > "${TASKRC}.new"
    printf '\n# Add your own Taskwarrior settings below. This section is never overwritten.\n' >> "${TASKRC}.new"
    cat "$TMP_USER" >> "${TASKRC}.new"
    mv "${TASKRC}.new" "$TASKRC"
    rm -f "$TMP_USER"
    echo "info: migrated taskrc to container-managed markers format"
else
    # New install
    cat "$TMP_BLOCK" > "$TASKRC"
    cat >> "$TASKRC" <<'EOF'

# Add your own Taskwarrior settings below. This section is never overwritten.
# Examples:
#   journal.time=yes
#   uda.estimate.type=duration
#   uda.estimate.label=Estimate
#   context.work.read=+work
EOF
    echo "info: created taskrc — add your customisations below the end marker"
fi
rm -f "$TMP_BLOCK"

# Clean up taskrc.container left over from a previous version of this image
rm -f "${CONFIG_DIR}/taskrc.container"

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
# Optional: absolute path to bugwarrior binary. Empty = auto-detect via PATH
# and common install locations (~/.local/bin, /usr/local/bin, etc.).
export BUGWARRIOR_BIN="${BUGWARRIOR_BIN:-}"

exec gosu "${PUID}:${PGID}" /usr/local/bin/taskwarrior-web-portal
