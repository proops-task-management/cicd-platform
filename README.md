# cicd-platform

Centralized CI/CD platform for the **proops-task-management** org — composite actions
(step-level reuse) and reusable workflows (job-level reuse). Service repos consume these
as **thin callers** pinned to a tag (`@v1`), never `@main`.

## Composite actions (`.github/actions/`)
| Action | Purpose |
|---|---|
| `build-app` | setup-node + npm ci + lint + test + build (Node toolchain) |
| `docker-build-push` | qemu + buildx + login + multi-arch build, push gated by `push` input |

## Reusable workflows (`.github/workflows/`, `on: workflow_call`)
| Workflow | Purpose |
|---|---|
| `reusable-app-ci.yml` | build/test via `build-app` then `docker-build-push` (push if input true) |
| `reusable-iac.yml` | terraform init/validate/plan, apply/destroy gated by `action` input |

## Versioning
Tagged `@v1`. Service callers pin to the tag so platform commits cannot silently break them.
Breaking change → cut `@v2`; each service upgrades deliberately.
