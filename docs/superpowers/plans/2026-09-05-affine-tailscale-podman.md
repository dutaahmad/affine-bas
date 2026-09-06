# AFFiNE Tailscale Podman Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Run AFFiNE as a rootless Podman Compose stack with a Tailscale Caddy sidecar providing private HTTPS on a MagicDNS hostname.

**Architecture:** AFFiNE, PostgreSQL, Redis, and the migration job run on an internal Compose network. Caddy runs from `ghcr.io/tailscale/caddy-tailscale:main` as a separate tsnet node named `affine`, obtains the Tailscale HTTPS certificate, and proxies `https://<TS_FQDN>` to `affine-upstream:3010`. No AFFiNE host port is published.

**Tech Stack:** Podman, Podman Compose provider, AFFiNE official Compose services, PostgreSQL/pgvector, Redis, Caddy with Tailscale plugin, Tailscale MagicDNS and HTTPS certificates.

**Spec:** `docs/superpowers/specs/2026-09-05-affine-tailscale-podman-design.md`

## Global Constraints

- Run the stack rootless under a dedicated Linux user.
- Use one explicit Podman Compose provider consistently; never mix rootless and `sudo podman` state.
- Keep `TS_AUTHKEY`, `.env`, `config/config.json`, database data, uploads, and backups out of Git.
- Do not publish AFFiNE port `3010` to the host.
- Caddy must use persistent `/config` state.
- Do not use Tailscale Funnel.
- Human gates are blocking checkpoints; stop and wait for human confirmation.

## Task 1: Repository Configuration

**Files:**
- Create: `compose.yml`
- Create: `caddy/Caddyfile`
- Create: `config/config.json.example`
- Create: `.env.example`
- Create: `.gitignore`

- [x] Verify the official AFFiNE service names, images, healthchecks, and migration dependency against the current release Compose reference. (Verified against `.docker/selfhost/compose.yml` on `canary`; added missing `DEPLOYMENT_TYPE=selfhosted` and `copilot.byok.allowCustomEndpoint`.)
- [x] Keep PostgreSQL, Redis, and AFFiNE data on bind mounts under `./data`.
- [x] Add the `affine-upstream` network alias to the AFFiNE service.
- [x] Configure Caddy with `bind tailscale/affine` and `reverse_proxy affine-upstream:3010`.
- [x] Add persistent `caddy_ts_state` and `caddy_data` volumes.
- [x] Make missing `TS_FQDN` and `TS_AUTHKEY` fail Compose interpolation instead of silently starting insecurely. (Verified: config fails with exit 1 when unset.)
- [x] Ignore `.env`, `config/config.json`, `data/`, and backup files.

## HUMAN GATE 1: Tailscale Administration

- [ ] Human enables MagicDNS and HTTPS certificates.
- [ ] Human confirms `affine` is an unused hostname.
- [ ] Human creates an allowed reusable or tagged auth key.
- [ ] Human confirms ACL access for intended tailnet members.

Stop until the human confirms these prerequisites.

## Task 2: Server Preparation

**Files:** Server filesystem outside Git

- [ ] Human or operator creates the dedicated rootless `affine` user.
- [ ] Create `/opt/affine` and grant ownership to `affine`.
- [x] Install Podman and one Compose provider. (Podman 4.9.3 present; provider selected: Compose V2 at `/usr/libexec/docker/cli-plugins/docker-compose` via the rootless `podman.socket`.)
- [x] Validate rootless Podman and the provider's support for healthcheck dependency conditions. (Empirical test 2026-09-06: podman-compose 1.0.6 REJECTED — starts dependents before `service_completed_successfully` completes; Compose V2 v5.3.1 + `systemctl --user` podman socket PASSES both `service_healthy` and `service_completed_successfully`.)
- [ ] Enable user lingering only if boot-time persistence is later required.

## HUMAN GATE 2: Server Access

- [ ] Human confirms SSH or physical-console recovery access.
- [ ] Human confirms `sudo` is available for initial setup.
- [ ] Human approves proceeding with server-side directory and permission changes.

## Task 3: Server-Only Configuration

**Files:** Server-only `/opt/affine/.env` and `/opt/affine/config/config.json`

- [ ] Copy `.env.example` to `.env` and set `TS_FQDN`, `TS_AUTHKEY`, and the reviewed `AFFINE_IMAGE` tag.
- [ ] Set `.env` permissions to `0600`.
- [ ] Copy `config/config.json.example` to `config/config.json`.
- [ ] Set `server.externalUrl` to exactly the same HTTPS URL as `TS_FQDN`.

## HUMAN GATE 3: Secret and Hostname Review

- [ ] Human verifies the auth key is not committed or exposed in shell history.
- [ ] Human verifies the hostname matches in `.env` and `config.json`.
- [ ] Human verifies the Tailscale hostname is not already registered.

## Task 4: Compose Validation and Start

- [ ] Run `podman compose config`.
- [ ] Confirm the rendered configuration has no host port for AFFiNE.
- [ ] Run `podman compose up -d`.
- [ ] Run `podman compose ps`.
- [ ] Inspect `podman compose logs --tail=200 affine affine_migration`.
- [ ] Confirm the migration job completes and AFFiNE, PostgreSQL, Redis, and Caddy remain running.

If the selected provider does not honor `depends_on` conditions, stop and use a provider that does or document a deliberate staged start before continuing.

## HUMAN GATE 4: Tailscale Node Approval

- [ ] Human confirms the new `affine` node appears in the expected tailnet.
- [ ] Human confirms its hostname, tags, and ACL permissions.
- [ ] Human stops the deployment if Tailscale registered a suffixed or unexpected hostname.

## Task 5: HTTPS and Application Validation

- [ ] Validate Caddy with `podman exec affine_bas_caddy caddy validate --config /etc/caddy/Caddyfile`.
- [ ] From a tailnet-connected device, open `https://<TS_FQDN>`.
- [ ] Verify the certificate is valid and no port suffix is required.
- [ ] Verify login, workspace creation, document editing, uploads, and synchronization.
- [ ] Verify the endpoint is unavailable from a client disconnected from Tailscale.

## HUMAN GATE 5: First Administrator

- [ ] Human creates and stores the first AFFiNE administrator credentials.
- [ ] Human confirms the application is usable before inviting other users.

## Task 6: Documentation and Backup Handoff

- [ ] Keep `README.md` aligned with the actual hostname, provider, data paths, and commands without adding secrets.
- [ ] Document `podman compose up -d`, logs, status, and safe shutdown commands.
- [ ] Document upgrade review and rollback precautions.
- [ ] Document that backups are mandatory immediately after the first deployment.

## HUMAN GATE 6: Backup Readiness

- [ ] Human chooses separate-disk, NAS, or encrypted off-host backup storage.
- [ ] Back up PostgreSQL, uploaded files, configuration, Compose files, and required Caddy state.
- [ ] Human performs a restore test and records the result.

The deployment is not production-ready until this gate is complete.
