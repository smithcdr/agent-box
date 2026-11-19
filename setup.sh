#!/usr/bin/env bash
# agent-box provisioning for a clean Ubuntu 24.04 VPS.
# Idempotent. Run as root from the repo dir:  sudo bash setup.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"   # work relative to this repo

AGENT_USER="${AGENT_USER:-agent}"
REPOS_DIR="/home/$AGENT_USER/repos"
PORT=4096
NODE_MAJOR=22

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root:  sudo bash setup.sh" >&2
  exit 1
fi

echo "==> Base packages"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -yq git curl ca-certificates build-essential

echo "==> Node $NODE_MAJOR (NodeSource)"
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
fi
apt-get install -yq nodejs

echo "==> GitHub CLI"
if ! command -v gh >/dev/null 2>&1; then
  mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /usr/share/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -q
fi
apt-get install -yq gh

echo "==> Service user '$AGENT_USER'"
id "$AGENT_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$AGENT_USER"

echo "==> OpenCode CLI"
if [ ! -x "/home/$AGENT_USER/.opencode/bin/opencode" ]; then
  su - "$AGENT_USER" -c 'curl -fsSL https://opencode.ai/v2/install | bash'
fi

echo "==> OpenCode config"
mkdir -p "/home/$AGENT_USER/.config/opencode"
cp config/opencode.json "/home/$AGENT_USER/.config/opencode/opencode.json"
chown -R "$AGENT_USER:$AGENT_USER" "/home/$AGENT_USER/.config"

echo "==> Secrets template"
mkdir -p /etc/opencode
if [ ! -f /etc/opencode/secrets.env ]; then
  cat > /etc/opencode/secrets.env <<'EOF'
# Fill these in, then: sudo systemctl restart opencode-agent
# OPENROUTER_API_KEY is required (https://openrouter.ai/settings/keys).
# ENCRYPTION_KEY: leave blank. Production data is never read on this box; if an app needs a key for
#   local dev/tests, repos.sh generates a throwaway one automatically. Never put the production key here.
# SERPER_API_KEY: optional, only for exercising image search (google.serper.dev) during dev.
# CLOUDFLARE_API_TOKEN: optional, lets the agent run `wrangler deploy` (or use `wrangler login` instead).
# OPENCODE_PASSWORD: fixed password for the OpenCode web UI / phone app (username is always `opencode`).
OPENROUTER_API_KEY=
ENCRYPTION_KEY=
BRAVE_API_KEY=
CLOUDFLARE_API_TOKEN=
OPENCODE_PASSWORD=
OPENCODE_SERVER_PASSWORD=
EOF
  chmod 600 /etc/opencode/secrets.env
  echo "  (created /etc/opencode/secrets.env — edit it, then restart the service)"
fi

echo "==> Repos dir"
mkdir -p "$REPOS_DIR"
chown "$AGENT_USER:$AGENT_USER" "$REPOS_DIR"

echo "==> systemd unit"
sed -e "s|__AGENT_USER__|$AGENT_USER|g" \
    -e "s|__REPOS_DIR__|$REPOS_DIR|g" \
    -e "s|__PORT__|$PORT|g" \
    systemd/opencode-agent.service > /etc/systemd/system/opencode-agent.service
systemctl daemon-reload
systemctl enable --now opencode-agent
systemctl status --no-pager --lines=0 opencode-agent

echo
echo "Done. Next:"
echo "  1. sudoedit /etc/opencode/secrets.env  (OPENROUTER_API_KEY) && sudo systemctl restart opencode-agent"
echo "  2. sudo -iu $AGENT_USER gh auth login  (once) && gh auth setup-git"
echo "  3. sudo bash scripts/repos.sh           # clone every repo + write per-app .dev.vars"
echo "  4. Make it reachable from your phone — README.md, 'Make it reachable' (Tailscale recommended)."
