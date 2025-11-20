# Repository Guidelines

## Project Structure & Module Organization
- `cmd/poller/` Go SNMP poller; `cmd/alerter/` notification daemon.
- `webui/` Express API plus static dashboard (`index.html`, `target.html`).
- Config lives in `config/auspex.conf.template`; copy to `config/auspex.conf` (server defaults to `/opt/auspex/config/auspex.conf`).
- Database assets: `db-init-new.sql` and `setup-database.sh`; helper scripts `add-target.sh`, `install-systemd-services.sh`.
- Reference docs sit at repo root and `/docs` (e.g., `GETTING-STARTED.md`, `PRODUCTION-READY.md`).

## Build, Test, and Development Commands
```bash
npm install              # Install API/UI deps from root
npm start                # Run Express API + static UI (AUSPEX_API_PORT default 8080)
export $(grep -v '^#' config/auspex.conf | xargs)
go run cmd/poller/main.go   # Start SNMP poller
go run cmd/alerter/main.go  # Start alerting engine
./setup-database.sh         # Initialize PostgreSQL schema locally
```
- Use `./add-target.sh` or `curl` POSTs to seed devices during local testing.

## Coding Style & Naming Conventions
- Go: keep code `gofmt`-clean; prefer clear, exported identifiers for API-facing structs; use table-driven tests when added.
- JavaScript: match existing `webui/server.js` style (4-space indent, semicolons, double quotes); keep route handlers small and async/await-based.
- Config/env vars stay uppercase with `AUSPEX_` prefix; avoid committing secrets (`config/` is untracked except templates).

## Testing Guidelines
- Current suite is minimal; add `_test.go` files alongside Go sources and run `go test ./...` (should still pass quickly when no tests are present).
- For API changes, add integration tests (e.g., supertest) or manual smoke checks: `curl http://localhost:8080/api/targets` after seeding sample data.
- Document any new migrations or required fixtures in PR descriptions.

## Commit & Pull Request Guidelines
- Commit messages: short, imperative, and specific (e.g., "Add production deployment tools").
- PRs should describe scope, how to run/verify (commands or cURL), and note DB schema changes or config keys.
- Include before/after screenshots for UI changes and sample responses for new endpoints.
- Update relevant docs (`README.md`, `GETTING-STARTED.md`, alerting/database guides) when behavior or setup steps change.

## Security & Configuration Tips
- Keep `config/auspex.conf` permissions tight (`chmod 600`) and never commit real credentials.
- Use the least-privileged DB user created by `setup-database.sh`; keep queries parameterized as in existing handlers.
- When adding endpoints, validate input and sanitize SQL parameters to preserve API safety.
