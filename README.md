# AFFiNE BAS

Private AFFiNE self-hosting on the homelab server using rootless Podman and a
Tailscale-enabled Caddy sidecar. The instance is reachable only from the
tailnet at `https://affine.taila4cbae.ts.net` with a valid Tailscale-issued
(Let's Encrypt) certificate and no port suffix. AFFiNE's application port is
never published to the host.

## Deployed state

| Item | Value |
| --- | --- |
| URL | `https://affine.taila4cbae.ts.net` |
| Linux user | `bas-server` (rootless Podman, lingering enabled) |
| Deployment path | `/home/bas-server/code/affine-bas` |
| Compose provider | Docker Compose V2 via the rootless Podman socket |
| App data | `./data/storage`, `./data/postgres`, `./config` |
| Caddy state | Volumes `affine-bas_caddy_ts_state`, `affine-bas_caddy_data` |

Deployment history and human-gate approvals are recorded in
`docs/superpowers/plans/2026-09-05-affine-tailscale-podman.md`.

## Architecture

```text
Tailnet client
    |
    | https://affine.taila4cbae.ts.net
    v
Caddy tsnet node: affine  (Tailscale HTTPS cert, persistent tsnet state)
    |
    | Compose network: affine-upstream:3010
    v
AFFiNE  ->  PostgreSQL (pgvector) + Redis (internal network only)
```

No public DNS, router port forwarding, Tailscale Funnel, or host application
port is involved. Access is controlled by Tailscale ACLs; the URL is
unreachable from devices disconnected from the tailnet (verified).

## Compose provider (important)

This stack relies on `depends_on` conditions (`service_healthy`,
`service_completed_successfully`). On this server those are only honored by
Docker Compose V2 talking to the rootless Podman socket:

```bash
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock
DC=/usr/libexec/docker/cli-plugins/docker-compose
```

All commands below assume both lines are set in the shell.

- Do **not** use `podman-compose` 1.0.6 or the `podman compose` shortcut for
  this stack: it was tested and starts dependent services before their
  conditions complete.
- Do not mix rootless commands with `sudo podman`.
- The socket is enabled with `systemctl --user enable --now podman.socket`;
  `bas-server` has lingering enabled so the stack starts at boot.

## Server-only files (never commit)

- `.env` (mode 600, gitignored): `TS_FQDN=affine.taila4cbae.ts.net`,
  `TS_AUTHKEY`, `AFFINE_IMAGE`.
- `config/config.json` (gitignored): must keep
  `server.externalUrl = https://affine.taila4cbae.ts.net`.
- `config/private.key` (gitignored): runtime-generated instance key.

## Operations

```bash
$DC ps                # status of all services
$DC logs -f affine    # follow application logs
$DC logs -f caddy     # follow proxy logs
$DC up -d             # start stack / apply config changes
$DC restart           # restart all services
$DC down              # stop stack; keeps data and volumes
```

Do not run `$DC down --volumes` unless you deliberately intend to delete the
persistent database and Caddy's Tailscale node identity.

Inspect a single container directly with Podman (no `DOCKER_HOST` needed):

```bash
podman logs affine_bas_migration
podman logs affine_bas_caddy
podman inspect affine_bas_postgres
```

## Upgrades

1. Read the target AFFiNE release notes.
2. Back up PostgreSQL, uploaded files, and configuration.
3. Pin `AFFINE_IMAGE` in `.env` to the reviewed release tag.
4. Review the Compose diff and the upstream
   `.docker/selfhost/compose.yml` reference.
5. `podman pull` / `$DC pull`.
6. `$DC up -d` (the migration job runs automatically and must exit 0).
7. Verify login, workspaces, editing, uploads, and the Caddy endpoint.

Do not upgrade by switching to an unreviewed `latest`/`stable` drift without
backup. Rollback precaution: keep the previous image tag and a database backup
taken immediately before upgrading.

## Backups

Off-host storage is configured: **Google Drive via rclone with client-side
encryption** (`gdrive-crypt:` remote → `gdrive:affine-backups`). The initial
backup was taken on 2026-09-06 and restore-tested (dump restored into a
disposable pgvector container: exit 0, 91 tables, 1 user, extensions intact).

A full backup consists of:

- PostgreSQL dump: `podman exec affine_bas_postgres pg_dump -U affine affine`
- `/home/bas-server/code/affine-bas/data/storage` (uploaded files)
- `/home/bas-server/code/affine-bas/config` (includes `config.json` and
  `private.key`)
- `compose.yml`, `.env`, and the effective `AFFINE_IMAGE` tag
- Caddy state volumes `affine-bas_caddy_ts_state` and `affine-bas_caddy_data`
  (`podman volume export`)

Take and upload a new backup:

```bash
BK=~/affine-backups/$(date +%F)
mkdir -p "$BK"
cd /home/bas-server/code/affine-bas
podman exec affine_bas_postgres pg_dump -U affine affine > "$BK/affine-db.sql"
cp -a config data/storage compose.yml .env "$BK/"
chmod 600 "$BK/env"
podman volume export affine-bas_caddy_ts_state -o "$BK/caddy_ts_state.tar"
podman volume export affine-bas_caddy_data -o "$BK/caddy_data.tar"
cd "$BK" && sha256sum affine-db.sql env compose.yml caddy_*.tar > SHA256SUMS
~/.local/bin/rclone copy "$BK" "gdrive-crypt:$(date +%F)"
```

Recovery notes:

- The rclone crypt keys are in `~/affine-backups/rclone-crypt-recovery.txt`
  and `~/.config/rclone/rclone.conf` (mode 600). **Store the two password
  lines in a password manager** — without them the Drive backups are
  unrecoverable.
- rclone currently uses its shared Google client_id, which is being retired
  during 2026; create a personal client_id and update the `gdrive` remote
  before then (no re-upload needed).
- A database-only backup does not restore uploaded files.

## Deferred: SMTP

No mailer is configured. Email confirmations, user invitations by email, and
password-reset emails are inactive; the instance itself is fully usable. To
enable later, add a `mailer` block to `config/config.json` (SMTP.host,
SMTP.port, SMTP.username, SMTP.password, SMTP.sender) and restart the `affine`
service.

## Troubleshooting

```bash
$DC config                       # validate and render the Compose file
$DC ps -a                        # include the one-shot migration job
podman logs affine_bas_migration # migration output (must end exit 0)
podman logs affine_bas_caddy     # tsnet login and certificate logs
```

- **502 from Caddy**: confirm AFFiNE is running and the network alias
  `affine-upstream` resolves to the AFFiNE container.
- **Certificate problems**: check Caddy logs; the Tailscale-issued Let's
  Encrypt certificate is obtained on demand and cached in `affine-bas_caddy_data`.
- **Hostname collision**: if Caddy ever registers a suffixed hostname (e.g.
  `affine-1`), stop the stack and resolve the Tailscale hostname collision
  before changing `TS_FQDN`.
- **First-run setup page**: `https://affine.taila4cbae.ts.net/admin/setup` is
  only shown until the first administrator exists.
