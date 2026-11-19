#!/usr/bin/env bash
# Clone every repo visible to the agent's GitHub account into /home/agent/repos, then
# generate a .dev.vars for each Cloudflare (wrangler) app from /etc/opencode/secrets.env.
# Prereq (once):  sudo -iu agent gh auth login && gh auth setup-git
# Run as root:    sudo bash scripts/repos.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

AGENT_USER="${AGENT_USER:-agent}"
REPOS_DIR="/home/$AGENT_USER/repos"
SECRETS=/etc/opencode/secrets.env

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root:  sudo bash scripts/repos.sh" >&2
  exit 1
fi

echo "==> Cloning repos as $AGENT_USER"
mapfile -t repos < <(su - "$AGENT_USER" -c \
  'gh repo list --limit 500 --json nameWithOwner -q ".[].nameWithOwner"' \
  || { echo "gh not authenticated yet — run: sudo -iu agent gh auth login" >&2; exit 1; })

for full_name in "${repos[@]}"; do
  name="${full_name##*/}"
  if [ ! -d "$REPOS_DIR/$name/.git" ]; then
    # shellcheck disable=SC2016
    if su - "$AGENT_USER" -c "git clone --quiet https://github.com/$full_name.git '$REPOS_DIR/$name'"; then
      echo "  cloned $full_name"
    else
      echo "  FAILED $full_name (check gh auth / repo visibility)"
    fi
  else
    echo "  already present: $full_name"
  fi
done

echo "==> Per-app .dev.vars (from $SECRETS)"
if [ ! -f "$SECRETS" ]; then
  echo "  no $SECRETS — skipping (run setup.sh first)"
  exit 0
fi
set -a; . "$SECRETS"; set +a   # brings in OPENROUTER_API_KEY, ENCRYPTION_KEY, BRAVE_API_KEY
# The real ENCRYPTION_KEY stays off the box: production ciphertext is never read here, and local dev
# merely needs a key self-consistent with itself. So if none is supplied, use one throwaway key for the box.
if [ -n "$ENCRYPTION_KEY" ]; then
  LOCAL_KEY="$ENCRYPTION_KEY"
else
  LOCAL_KEY="$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
  echo "  ENCRYPTION_KEY not set — generated a throwaway key for local dev (never reuse against production data)"
fi
for d in "$REPOS_DIR"/*/; do
  [ -f "$d/wrangler.jsonc" ] || [ -f "$d/wrangler.toml" ] || continue
  [ -e "$d/.dev.vars" ] && { echo "  kept existing $d.dev.vars"; continue; }
  cat > "$d/.dev.vars" <<EOF
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}
ENCRYPTION_KEY=${LOCAL_KEY}
BRAVE_API_KEY=${BRAVE_API_KEY:-}
EOF
  chown "$AGENT_USER:$AGENT_USER" "$d/.dev.vars"
  chmod 600 "$d/.dev.vars"
  echo "  wrote $d.dev.vars"
done

echo "==> Done. The agent's projects live under $REPOS_DIR."
