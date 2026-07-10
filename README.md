# cicd-platform

Centralized CI/CD platform for the **proops-task-management** org — composite actions
(step-level reuse) and reusable workflows (job-level reuse). Service repos consume these
as **thin callers** pinned to a tag (`@v6`), never `@main`. All logic lives here; a breaking
change cuts the next major tag and callers upgrade deliberately (IRD-015).

## Composite actions (`.github/actions/`)
| Action | Purpose |
|---|---|
| `build-app` | Node: setup-node + npm ci + lint + test + build |
| `build-java` | Java: setup-java (Temurin) + Maven cache + `mvn -B verify` (unit + Testcontainers `*IT`) |
| `docker-build-push` | buildx build → GHCR, `:sha` + `:latest`, push gated by `push` input (linux/amd64 — Day-35) |
| `sonar-scan` | SonarCloud analysis with blocking quality gate |
| `trivy-scan` | `fs`\|`image` scan, SARIF → Security tab, gate on fixable HIGH/CRITICAL (IRD-021) |
| `gitleaks-scan` | secret scan via the gitleaks binary (org-safe, no license); pinned to the pre-commit rev |

## Reusable workflows (`.github/workflows/`, `on: workflow_call`)
| Workflow | Purpose |
|---|---|
| `reusable-app-ci.yml` | Node PR gate → `app-ci / ci-success` (build + sonar + image + gitleaks + trivy fs) |
| `reusable-java-ci.yml` | Java PR gate → `app-ci / ci-success` (mvn verify + sonar + gitleaks + trivy fs) |
| `reusable-build.yml` | merge-time build-once (`stack: node\|java`) → GHCR `:sha` + trivy image + GitOps `bump-dev` |
| `reusable-iac.yml` | terraform fmt/validate/plan, apply/destroy gated by `action` input (iac-platform) |
| `reusable-why-failed.yml` | Agent B relay: `/why-failed` PR comment → POST fleet `/ci-failed` (IRD-022) |

## The @v6 delivery contract (CI-agnostic)
`@v6` is a **contract**, not "the GitHub Actions pipeline" (ADR-010). Every engine produces the
same 4 outputs: (1) build-once **linux/amd64** image tagged by full SHA (amd64-only in CI —
Day-35 / ADR-011), (2) push to `ghcr.io/proops-task-management/<svc>:<sha>` (public), (3) gates
pass (tests, Sonar, Trivy, gitleaks), (4) idempotent `bump-dev` commit to the `deploy` repo dev
overlay. **Deploy is not CI's job** — Argo CD pulls from the `deploy` repo (IRD-017).
`reusable-deploy.yml` (push-deploy) was **retired at v6**.

## Thin-caller templates (per service repo)
- Java (`api-gateway`, `user-service`, `task-service`, `notification-service`):
  `pr-opened.yml` → `reusable-java-ci.yml@v6` · `pr-merged.yml` → `reusable-build.yml@v6` (`stack: java`) ·
  `why-failed.yml` → `reusable-why-failed.yml@v6`
- Node (`frontend-service`): same trio with `reusable-app-ci.yml@v6` / `stack: node`.

## Versioning
Tagged `@v6`. Service callers pin to the tag so platform commits cannot silently break them.
Breaking change → cut `@v7`; each service upgrades deliberately. `@v5` retained for rollback.

## Local checks (pre-commit + Taskfile)
`.pre-commit-config.yaml`: gitleaks + yamllint (`.yamllint.yaml`) + actionlint. Install once:
`pre-commit install`. Same gitleaks runs in CI as a backstop (IRD-021).
`Taskfile.yml` (go-task) wraps these locally: `task hooks` (install), `task lint` (run all),
`task actionlint` / `task yamllint` / `task secrets` (individual). CI stays the enforced gate.

## Governing docs
IRD-015 (this contract) · IRD-021 (security gates) · IRD-022 (agent fleet) · IRD-024 (Jenkins
second engine) · ADR-010 (dual-CI decision).
