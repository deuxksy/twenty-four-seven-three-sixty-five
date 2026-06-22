# Monitoring Dashboard Copy Design

## Goal

Copy the Homepage and Gatus configuration from `~/git/homelab/heritage` into
this repository and deploy new Homepage, Gatus, and Beszel instances on `brla`.
The existing Heritage instances and configuration remain unchanged.

## Scope

- Copy the existing Homepage YAML configuration into a new Ansible role.
- Copy the existing Gatus endpoint configuration into a new Ansible role.
- Deploy a new Beszel hub without importing Heritage data or accounts.
- Start Gatus with a new empty SQLite database.
- Keep existing Heritage links for Transmission, Jellyfin, and Aria2.
- Point the new Homepage links for Homepage-adjacent monitoring services to
  `brla.bun-bull.ts.net`.
- Do not modify files under `~/git/homelab`.

## Architecture

Three focused Ansible roles deploy the services under `/data` on `brla`:

- `/data/homepage`: generated Docker Compose file and copied configuration.
- `/data/gatus`: generated Docker Compose file, copied `config.yaml`, and a new
  persistent `data` directory.
- `/data/beszel`: generated Docker Compose file and new persistent `data` and
  `socket` directories.

Each role owns its service directories, configuration, image pull, and
`docker compose up -d` operation. `playbook-brla.yml` invokes the roles after
Docker is installed.

## Homepage Configuration

The copied configuration preserves the Heritage dashboard content. Monitoring
links are adjusted for the new deployment:

- Beszel link: `https://brla.bun-bull.ts.net:8090`
- Gatus link: `https://brla.bun-bull.ts.net:8088`
- Transmission, Jellyfin, and Aria2 continue to reference Heritage.

Homepage widget credentials and provider values are injected from controller
environment variables through the generated Docker Compose file. No secret
values are committed.

## Gatus Configuration And Data

The copied Gatus configuration continues monitoring the Heritage services while
the Homepage and Beszel checks target the local new instances. Gatus uses
`/data/gatus/data/gatus.db`; Ansible creates the directory but does not copy an
existing database.

## Beszel Data

Beszel starts with empty `/data/beszel/data` and `/data/beszel/socket`
directories. No database, account, system registration, or socket data is
copied from Heritage.

## Routing

Tailscale Serve keeps the existing root route to code-server unchanged. The
new services use Tailscale DNS with dedicated ports to avoid sub-path
compatibility issues:

- Homepage: `https://brla.bun-bull.ts.net:3000`
- Gatus: `https://brla.bun-bull.ts.net:8088`
- Beszel: `https://brla.bun-bull.ts.net:8090`

## Operations

`playbook-ops.yml` includes the three images and Compose projects in the
`docker-update` workflow. README and CLAUDE guidance document deployment,
URLs, and health-check commands.

## Verification

- Run `ansible-playbook --syntax-check` for the brla and operations playbooks.
- Render or inspect all Compose templates for valid service definitions.
- Confirm the repository contains no copied Gatus/Beszel runtime database.
- Confirm no files under `~/git/homelab` are modified.
- After deployment, verify Homepage, Gatus, and Beszel HTTP endpoints.
