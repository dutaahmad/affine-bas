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

- [x] Human enables MagicDNS and HTTPS certificates.
- [x] Human confirms `affine` is an unused hostname.
- [x] Human creates an allowed reusable or tagged auth key.
- [x] Human confirms ACL access for intended tailnet members. (Default allow-all ACLs.)

Stop until the human confirms these prerequisites.

## Task 2: Server Preparation

**Files:** Server filesystem outside Git

- [x] Human or operator creates the dedicated rootless `affine` user. (Superseded: human chose the existing rootless `bas-server` user.)
- [x] Create `/opt/affine` and grant ownership to `affine`. (Superseded: deployment runs from `/home/bas-server/code/affine-bas` owned by `bas-server`.)
- [x] Install Podman and one Compose provider. (Podman 4.9.3 present; provider selected: Compose V2 at `/usr/libexec/docker/cli-plugins/docker-compose` via the rootless `podman.socket`.)
- [x] Validate rootless Podman and the provider's support for healthcheck dependency conditions. (Empirical test 2026-09-06: podman-compose 1.0.6 REJECTED — starts dependents before `service_completed_successfully` completes; Compose V2 v5.3.1 + `systemctl --user` podman socket PASSES both `service_healthy` and `service_completed_successfully`.)
- [x] Enable user lingering only if boot-time persistence is later required. (Linger already enabled for `bas-server`; `podman.socket` user service enabled and active.)

## HUMAN GATE 2: Server Access

- [x] Human confirms SSH or physical-console recovery access.
- [x] Human confirms `sudo` is available for initial setup.
- [x] Human approves proceeding with server-side directory and permission changes.

## Task 3: Server-Only Configuration

**Files:** Server-only `/opt/affine/.env` and `/opt/affine/config/config.json`

- [x] Copy `.env.example` to `.env` and set `TS_FQDN`, `TS_AUTHKEY`, and the reviewed `AFFINE_IMAGE` tag. (`affine.taila4cbae.ts.net`, stable image.)
- [x] Set `.env` permissions to `0600`.
- [x] Copy `config/config.json.example` to `config/config.json`.
- [x] Set `server.externalUrl` to exactly the same HTTPS URL as `TS_FQDN`.

## HUMAN GATE 3: Secret and Hostname Review

- [x] Human verifies the auth key is not committed or exposed in shell history. (Written via file tool; only `.env` contains the key; gitignored.)
- [x] Human verifies the hostname matches in `.env` and `config.json`.
- [x] Human verifies the Tailscale hostname is not already registered.

## Task 4: Compose Validation and Start

- [x] Run `podman compose config`. (Via Compose V2 `docker-compose` binary against the rootless `podman.socket`.)
- [x] Confirm the rendered configuration has no host port for AFFiNE.
- [x] Run `podman compose up -d`.
- [x] Run `podman compose ps`.
- [x] Inspect `podman compose logs --tail=200 affine affine_migration`.
- [x] Confirm the migration job completes and AFFiNE, PostgreSQL, Redis, and Caddy remain running. (Migration exit 0, "Done 10 migrations"; all services running, 0 restarts.)

If the selected provider does not honor `depends_on` conditions, stop and use a provider that does or document a deliberate staged start before continuing.

## HUMAN GATE 4: Tailscale Node Approval

- [x] Human confirms the new `affine` node appears in the expected tailnet.
- [x] Human confirms its hostname, tags, and ACL permissions.
- [x] Human stops the deployment if Tailscale registered a suffixed or unexpected hostname. (Not needed; exact hostname `affine` registered.)

## Task 5: HTTPS and Application Validation

- [x] Validate Caddy with `podman exec affine_bas_caddy caddy validate --config /etc/caddy/Caddyfile`. ("Valid configuration".)
- [x] From a tailnet-connected device, open `https://<TS_FQDN>`. (Host is a tailnet member; HTTPS live, 200 on `/admin/setup`.)
- [x] Verify the certificate is valid and no port suffix is required. (Let's Encrypt cert, CN=affine.taila4cbae.ts.net, Tailscale-provisioned; port 443.)
- [x] Verify login, workspace creation, document editing, uploads, and synchronization. (Human-verified from tailnet device.)
- [x] Verify the endpoint is unavailable from a client disconnected from Tailscale. (Human-verified unreachable.)

## HUMAN GATE 5: First Administrator

- [x] Human creates and stores the first AFFiNE administrator credentials. (Created via `/admin/setup`; email shows unconfirmed — SMTP not configured, optional for private use.)
- [x] Human confirms the application is usable before inviting other users.

## Task 6: Documentation and Backup Handoff

- [x] Keep `README.md` aligned with the actual hostname, provider, data paths, and commands without adding secrets. (Rewritten for `affine.taila4cbae.ts.net`, `bas-server`, Compose V2 provider warning, real paths and volume names.)
- [x] Document `podman compose up -d`, logs, status, and safe shutdown commands. (Documented via the `$DC` Compose V2 form actually used.)
- [x] Document upgrade review and rollback precautions.
- [x] Document that backups are mandatory immediately after the first deployment.

## HUMAN GATE 6: Backup Readiness

- [ ] Human chooses separate-disk, NAS, or encrypted off-host backup storage. (Considering Google Drive via rclone.)
- [x] Back up PostgreSQL, uploaded files, configuration, Compose files, and required Caddy state. (Initial backup at `/home/bas-server/affine-backups/2026-09-06-initial` with SHA256SUMS: pg dump, config, storage, compose.yml, .env, image tag, caddy volume exports.)
- [x] Human performs a restore test and records the result. (2026-09-06: dump restored into disposable pgvector container — exit 0, 0 errors, 91 tables, 1 user, extensions plpgsql/pgcrypto/vector OK.)

The deployment is not production-ready until this gate is complete.
