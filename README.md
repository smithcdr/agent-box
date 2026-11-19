# agent-box

Your personal cloud coding agent, always on, reachable from your phone.

A single small VPS runs an always-on [OpenCode](https://opencode.ai) server. Every repo you own is cloned
side-by-side on the box. Pair your phone once (QR / URL + password) and the OpenCode app is a native-feeling chat
where you say *"work on chitty-chat, fix X"* — the agent edits, runs tests, pushes, and deploys (`wrangler`, etc.)
exactly like it does on your desk. Your existing OpenRouter key is reused for models; no new accounts needed.

```
phone (OpenCode app)
   │  HTTPS over private tunnel (Tailscale / Cloudflare)
   ▼
VPS ── opencode serve (127.0.0.1:4096, systemd, always on)
   │  └─ /home/agent/repos/<repo>/   ← every repo, cloned and kept fresh
   └─ /etc/opencode/secrets.env      ← OPENROUTER_API_KEY, CLOUDFLARE_API_TOKEN, ...
```

## Buy the box

The agent is a light always-on process, so a 2–4 GB box is plenty; the cheapest tiers that were
the old default (Hetzner CX/CAX) have been out of stock since mid-2026, so here are the dev/nerd favourites
you can actually order (prices checked Nov 2026 — verify live before paying):

| Provider | Plan | Specs | Price | Notes |
|---|---|---|---|---|
| **Netcup** | VPS 500 (or 500 ARM) | 2 vCPU / 4 GB / 64 GB | ~€7–8/mo (12-mo term; Lite 1 is ~€5) | Closest to Hetzner in feel; German, homelab favourite. Term contracts, ticket-only support. |
| **OVHcloud** | VPS-1 | 2 vCPU / 4 GB / 40 GB NVMe | from ~€4–7/mo | No contract, plenty of regions, egress unmetered at 500 Mbps. |
| **Contabo** | Cloud VPS 4 | 4 vCPU / 8 GB / 100 GB SSD | ~€4.40–5.50/mo | Most RAM per euro; CPU is oversubscribed and support is slow — fine for a chat agent, not for latency-sensitive prod. |
| **Vultr** | Cloud Compute | 2 vCPU / 4 GB | ~$20/mo (entry tiers smaller) | Hourly, no commitment, 30+ regions, new-account credit. More expensive at 4 GB. |
| **Oracle Cloud** | Always Free ARM | 4 ARM cores / 24 GB | **free** | Free forever, but signup friction, idle instances get reclaimed, and accounts can be shut down without warning. |

Any Ubuntu 24.04 box works — the scripts don't care who hosts it. Create it with your SSH key and note the IP;
everything below is one-time ~10 minutes.

Everything below is a one-time ~10 minutes.

## One-time setup

```bash
ssh root@<your-ip>
git clone https://github.com/smithcdr/agent-box.git
cd agent-box
sudo bash setup.sh                     # installs Node, GitHub CLI, OpenCode; starts the agent server
```

Then, in a second SSH session (you're now 2 windows):

```bash
sudo bash -c 'vim /etc/opencode/secrets.env'   # fill in OPENROUTER_API_KEY (required) + the others
sudo systemctl restart opencode-agent
sudo -iu agent gh auth login                   # once: lets the box clone your private repos
gh auth setup-git
exit
sudo bash /home/agent/... /scripts/repos.sh    # clone every repo + generate per-app .dev.vars
```

(`secrets.env` placeholders are also explained inline in the file. Re-running `setup.sh` is safe.)

## Make it reachable from your phone — pick one

**A. Tailscale (recommended — private, zero public ports, free):**

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up                             # prints an auth URL; approve in the app
sudo tailscale serve 4096                     # exposes local :4096 as https://<box>.<tailnet>.ts.net
```

Install the Tailscale app on your phone and sign in to the same account.

**B. Cloudflare Tunnel + Access** (if you'd rather keep it in your existing Cloudflare stack):

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
cloudflared tunnel login
cloudflared tunnel create agent-box
sudo cloudflared service install --token ...
# add a public hostname pointing at http://localhost:4096, and put it behind a Cloudflare Access app
```

## Phone

1. Install the **OpenCode** app (Google Play / iOS TestFlight).
2. Add a connection: server URL `https://<box>.<tailnet>.ts.net` (Tailscale) — or your Access-protected URL —
   username `opencode`, password = your `OPENCODE_PASSWORD`.
3. Pick the model you use locally once (the app's AI settings, or `/models`) — defaults to
   `openrouter/deepseek/deepseek-v4-flash-latest`.
4. Message it. The box is awake 24/7, so it answers whenever.

## Later: private local models (Mac mini, or any home box)

The agent doesn't care where the model runs — OpenCode treats providers as config, and it has native
Ollama support with automatic model discovery. So when you want privacy/cost on the model side, a
32 GB Mac mini (or any 16+ GB machine) becomes a private model server and the VPS agent keeps on working:

1. On the home box: install [Ollama](https://ollama.com), run it, and `ollama pull` a coder model
   (`qwen2.5-coder:14b`, `llama3.1`, etc.).
2. Join the home box to the same tailnet as the VPS (it's the same private network the phone already uses).
3. Point the agent at it by adding one block to `/home/agent/.config/opencode/opencode.json`:

   ```jsonc
   {
     "providers": {
       "ollama": {
         "settings": { "baseURL": "http://<mini-tailnet-ip>:11434/v1" }
       }
     }
   }
   ```

   Pick the model in the phone app (`/models`) — it lists the models Ollama exposes automatically.
   Keep OpenRouter configured, so the agent can fall back to the cloud for harder requests. That's it.

Two ways to run it, depending on what you care about most:

- **Availability-first (recommended):** keep the agent on the VPS, point it at home models. Best on-the-go reliability,
  near-zero marginal LLM cost, everything stays under your control.
- **Privacy-first:** host the agent *and* the models on the home box (OpenCode runs fine on macOS/Linux) and drop the
  VPS. Sessions never leave your house. The trade-off is the agent goes dark when your home power/internet does.

### Could a Raspberry Pi run this?

As the **agent box**, yes: a Pi 5 (8 GB) runs OpenCode + your clones fine and sips power — the setup scripts target
Debian-family Linux, so they mostly work on Raspberry Pi OS. As a **model host**, no: 8 GB total RAM and no GPU means
models of any consequence won't run. Pi = cheap agent; Mac/PC with 16+ GB = models.

## Day-to-day

| Task | Command (on the box) |
|---|---|
| Follow the server log | `sudo journalctl -u opencode-agent -f` |
| Restart the server | `sudo systemctl restart opencode-agent` |
| Update OpenCode | `sudo -iu agent bash -c 'curl -fsSL https://opencode.ai/v2/install \| bash'` |
| Add a repo the agent should see | `sudo -iu agent gh repo clone <owner>/<name> ~/repos/<name>` (or re-run `repos.sh`) |
| Refresh all clones | `sudo bash scripts/repos.sh` |

## Security

- The OpenCode server binds only to `127.0.0.1`; nothing is reachable from the public internet except SSH.
  All phone access goes through the private tunnel, which is authenticated and, with Tailscale, encrypted end-to-end.
- The web UI/app additionally requires your `OPENCODE_PASSWORD` (server password). Never expose the raw port publicly.
- `/etc/opencode/secrets.env` is `chmod 600` and holds your tokens. It is **not** in this repo.
- The agent user has push access to everything in your GitHub account — that's the point, and also the risk surface:
  keep your GitHub account 2FA on and choose a strong `OPENCODE_PASSWORD`.

## Cost & limits

- ~4 €/mo for the box; model tokens billed through your normal OpenRouter key. No compute-by-the-hour surprises.
- Chat/session history lives on the box disk (`/home/agent/.local/share/opencode`). Back it up if you care about it.
