# AFFiNE Tailscale Podman Design

## Goal

Deploy AFFiNE on the physical Linux homelab server using rootless Podman so
that `podman compose up -d` starts the complete stack and authorized tailnet
members reach it at an HTTPS MagicDNS hostname without a port suffix.

## Architecture

The repository provides one Compose application containing AFFiNE, its
PostgreSQL and Redis dependencies, the migration job, and a Caddy sidecar. The
Caddy image is the Tailscale Caddy build; it registers a separate tsnet node
named `affine`, binds HTTPS to that node, obtains a Tailscale-issued
certificate, and reverse proxies to AFFiNE over the internal Compose network.

AFFiNE publishes no host port. The internal network alias `affine-upstream`
points to port `3010` in the AFFiNE container. Persistent data is stored in
`data/postgres`, `data/storage`, and `config`. Caddy state is stored in a named
volume so re-authentication is not required for ordinary restarts.

## Access and security

- Tailnet access is controlled by Tailscale ACLs.
- MagicDNS and Tailscale HTTPS certificates must be enabled by a human in the
  Tailscale admin console.
- `TS_AUTHKEY` is supplied through a gitignored `.env` file and never committed.
- No public DNS, router port forwarding, Tailscale Funnel, or host application
  port is required.
- The server-side Podman stack runs rootless under a dedicated user.
- The auth key and first AFFiNE administrator credentials are human-managed.

## Configuration contract

Required server-only environment variables:

- `TS_FQDN`: full HTTPS MagicDNS hostname, for example
  `affine.<tailnet>.ts.net`.
- `TS_AUTHKEY`: reusable or tagged auth key permitted by the tailnet ACL.
- `AFFINE_IMAGE`: reviewed AFFiNE image tag; defaults to the official stable
  image for initial setup.

`config/config.json` must set `server.externalUrl` to the same HTTPS URL as
`TS_FQDN`.

## Operational model

Deployment is intentionally manual and Compose-driven. The normal lifecycle is:

```bash
podman compose up -d
podman compose ps
podman compose logs --tail=200 affine affine_migration
```

No systemd unit or host-level `tailscale serve` configuration is part of the
initial deployment. Caddy's persistent tsnet state provides the HTTPS endpoint
when the Compose stack is started.

## Human gates

1. Tailscale admin enables MagicDNS and HTTPS certificates, creates the auth
   key, and confirms ACL permissions.
2. Human confirms server access and recovery before any permission or firewall
   change.
3. Human reviews `.env`, hostname consistency, and secret handling before the
   first start.
4. Human approves the newly registered `affine` Tailscale node.
5. Human creates the first AFFiNE administrator and verifies application use.
6. Human configures and tests backups immediately after deployment.

## Acceptance criteria

- `podman compose up -d` starts all required services.
- The migration job completes successfully.
- AFFiNE is reachable at `https://affine.<tailnet>.ts.net`.
- The URL has a valid Tailscale-issued certificate and no port suffix.
- AFFiNE's port `3010` is not published on the host.
- Non-tailnet clients cannot access the service.
- Persistent data survives container recreation.
- Caddy's node identity survives ordinary stop/start cycles.
- Backup requirements and restore validation are documented in `README.md`.
