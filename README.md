# AFFiNE BAS

Private AFFiNE self-hosting with rootless Podman and a Tailscale-enabled Caddy
sidecar. Users access the instance through HTTPS on the Tailscale MagicDNS
hostname; AFFiNE's application port is never published to the host.

## Architecture

```text
Tailnet client
    |
    | https://affine.<tailnet>.ts.net
    v
Caddy tsnet node: affine
    |
    | Compose network: affine-upstream:3010
    v
AFFiNE
```

The Caddy container registers as a separate Tailscale node named `affine` and
uses Tailscale HTTPS certificates. Its state is stored in the `caddy_ts_state`
volume so normal restarts do not require a new auth key.

## HUMAN GATE 1: Tailscale administration

Before deployment, a human must complete these steps in the Tailscale admin
console:

1. Enable MagicDNS.
2. Enable HTTPS certificates.
3. Confirm that the hostname `affine` is available.
4. Create a reusable or tagged auth key allowed by the tailnet ACL.
5. Confirm that the intended tailnet members may reach the new `affine` node.

Do not commit the auth key.

## HUMAN GATE 2: Server access

Before changing host permissions or firewall rules, confirm that:

- You can administer the Linux server over SSH or its physical console.
- The `affine` Linux user can run rootless Podman.
- You have a recovery path if a firewall change blocks network access.

## One-time server setup

Create a dedicated rootless user and deployment directory. The exact commands
depend on the Linux distribution, but the target layout is:

```text
/opt/affine/
├── compose.yml
├── .env
├── caddy/Caddyfile
├── config/config.json
├── data/postgres/
└── data/storage/
```

Clone this repository into `/opt/affine`, then create the server-only files:

```bash
cp .env.example .env
chmod 600 .env
cp config/config.json.example config/config.json
```

Set `TS_FQDN` and `TS_AUTHKEY` in `.env`. Set `server.externalUrl` in
`config/config.json` to the same `https://` URL as `TS_FQDN`.

## HUMAN GATE 3: Review secrets and hostname

Before starting containers, a human must verify:

- `.env` is not tracked by Git.
- `.env` is readable only by the deployment user.
- The Tailscale hostname is exactly the same in `.env` and `config.json`.
- No existing Tailscale node already uses the hostname `affine`.
- The auth key is not present in shell history, logs, or committed files.

## Start AFFiNE

Use one explicit Compose provider consistently. Do not mix rootless commands
with `sudo podman` commands.

```bash
podman compose config
podman compose up -d
podman compose ps
```

The migration job must complete successfully. Inspect startup problems with:

```bash
podman compose logs --tail=200 affine affine_migration
podman logs affine_bas_caddy
```

The regular restart command is simply:

```bash
podman compose up -d
```

No host-level `tailscale serve` command is needed. Caddy provides the private
HTTPS endpoint inside its own Tailscale node.

## HUMAN GATE 4: Approve the new Tailscale node

After the first `podman compose up -d`, inspect the Tailscale admin console.
Confirm that:

- The `affine` node registered in the expected tailnet.
- Its hostname is correct.
- Its ACL permissions are correct.
- It was not registered under an unexpected suffixed hostname.

Stop if the node identity or hostname is wrong.

## Validate access

From another device connected to the tailnet, open:

```text
https://affine.<your-tailnet>.ts.net
```

Verify:

- The browser shows a valid Tailscale-issued certificate.
- No port is present in the URL.
- AFFiNE login works.
- A workspace and document can be created.
- Uploads and document synchronization work.
- The URL is unavailable when the client is disconnected from Tailscale.

## HUMAN GATE 5: First administrator

A human must create and securely store the first AFFiNE administrator account.
Do not put the credentials in this repository.

## Operations

```bash
podman compose ps
podman compose logs -f affine
podman compose logs -f caddy
podman compose restart
podman compose down
```

Do not use `podman compose down --volumes` unless you deliberately intend to
delete the persistent database and Caddy Tailscale state.

## Upgrades

1. Read the target AFFiNE release notes.
2. Back up PostgreSQL, uploaded files, and configuration.
3. Pin `AFFINE_IMAGE` to the reviewed release tag.
4. Review the Compose diff.
5. Run `podman compose pull`.
6. Run `podman compose up -d`.
7. Verify login, workspaces, editing, uploads, and the Caddy endpoint.

Do not blindly upgrade a production instance by changing to an unreviewed
`latest` image.

## MUST DO IMMEDIATELY: backups

This deployment is not production-ready until backups are configured and a
restore has been tested.

Back up all of the following outside the deployment directory:

- PostgreSQL, using `pg_dump` from `affine_bas_postgres`.
- `/opt/affine/data/storage`.
- `/opt/affine/config`.
- `compose.yml` and the effective image version.
- The server-only `.env`, stored securely and separately from Git.
- The Caddy Tailscale state if preserving the registered node identity matters.

Use a separate disk, NAS, or encrypted off-host storage. A database-only backup
does not restore uploaded files.

## Troubleshooting

```bash
podman compose config
podman compose ps
podman inspect affine_bas_postgres
podman logs affine_bas_migration
podman logs affine_bas_caddy
```

If Caddy registers with a suffixed hostname, stop the stack and resolve the
Tailscale hostname collision before changing `TS_FQDN`.

If Caddy returns `502`, confirm that AFFiNE is running and that the Compose
network alias `affine-upstream` resolves to the AFFiNE container.
