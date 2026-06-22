# Monitoring Dashboard Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy copied Homepage and Gatus configuration plus a fresh Beszel hub on brla without changing or importing runtime data from Heritage.

**Architecture:** Add focused Ansible roles for Homepage, Gatus, and Beszel, invoke them from the brla playbook, and expose them through Tailscale Serve. Configuration is tracked as role files/templates while runtime data is created only on the target host.

**Tech Stack:** Ansible, Docker Compose, Homepage, Gatus, Beszel, Tailscale Serve

---

### Task 1: Add Homepage Role

**Files:**
- Create: `ansible/roles/homepage/tasks/main.yml`
- Create: `ansible/roles/homepage/templates/docker-compose.yml.j2`
- Create: `ansible/roles/homepage/files/config/bookmarks.yaml`
- Create: `ansible/roles/homepage/files/config/docker.yaml`
- Create: `ansible/roles/homepage/files/config/services.yaml`
- Create: `ansible/roles/homepage/files/config/settings.yaml`
- Create: `ansible/roles/homepage/files/config/widgets.yaml`

- [ ] Copy the Heritage Homepage configuration into role files.
- [ ] Change only the new Beszel and Gatus links to brla URLs.
- [ ] Create the service and config directories with the expected ownership.
- [ ] Copy the configuration and generate Docker Compose with secret values injected from environment variables.
- [ ] Pull the Homepage image and start the Compose project.

### Task 2: Add Gatus Role

**Files:**
- Create: `ansible/roles/gatus/tasks/main.yml`
- Create: `ansible/roles/gatus/files/config.yaml`
- Create: `ansible/roles/gatus/templates/docker-compose.yml.j2`

- [ ] Copy the Heritage Gatus configuration.
- [ ] Point Homepage and Beszel checks to the local new services while retaining Heritage service checks.
- [ ] Create an empty runtime data directory without copying `gatus.db`.
- [ ] Generate Docker Compose, pull the image, and start the project.

### Task 3: Add Beszel Role

**Files:**
- Create: `ansible/roles/beszel/tasks/main.yml`
- Create: `ansible/roles/beszel/templates/docker-compose.yml.j2`

- [ ] Create empty Beszel data and socket directories.
- [ ] Generate Docker Compose for a new Beszel hub.
- [ ] Pull the image and start the project.

### Task 4: Wire Deployment And Operations

**Files:**
- Modify: `ansible/playbook-brla.yml`
- Modify: `ansible/playbook-ops.yml`

- [ ] Add the three roles to the brla playbook after Docker.
- [ ] Preserve the existing code-server Tailscale Serve root route and expose the new services on dedicated ports.
- [ ] Add image pulls and Compose restarts to the Docker update workflow.

### Task 5: Document And Verify

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] Document the copied-versus-fresh data boundary and service URLs.
- [ ] Run Ansible syntax checks.
- [ ] Validate YAML and ensure no Gatus/Beszel databases are tracked.
- [ ] Confirm the source homelab repository remains unchanged.
