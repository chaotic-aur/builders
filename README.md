# GitHub Actions Builders

Free builders that run on `ubuntu-latest`. They tunnel to Redis and build packages.

## What it does

- It creates builders on free public runners.
- It opens a tunnel to Redis with `autossh`.
- It runs the builder for `340m`. Then it checks the queue.
- If the queue has jobs, it starts new builders. If the queue is empty, it stops.

## How it works

1. Each runner starts a builder. The builder name is `gh-1`, `gh-2`, and more.
2. The builder opens a tunnel: `autossh -L 6380:127.0.0.1:6379`.
3. The builder runs `node /app/index.mjs builder` for `340m`.
4. After `340m` the builder stops. The last step checks `https://builds.garudalinux.org/api/queue/stats`.
5. If jobs remain, it starts new builders with the same inputs.

## Use

### Option A — Call the workflow

Add this file to your repo:

```yaml
name: Chaotic Builder
on:
  workflow_dispatch:
  schedule: [{ cron: "30 */3 * * *" }]
jobs:
  call-builder:
    uses: chaotic-aur/builders/.github/workflows/builder.yml@main
    with:
      builders: 4
      runtime: "340m"
      manager_url: https://builds.garudalinux.org
      builder_class: "4"
    secrets:
      REDIS_PASSWORD: ${{ secrets.REDIS_PASSWORD }}
      DEPLOY_KEY: ${{ secrets.DEPLOY_KEY }}
      REDIS_SSH_HOST: ${{ secrets.REDIS_SSH_HOST }}
      REDIS_SSH_PORT: ${{ secrets.REDIS_SSH_PORT }}
      REDIS_SSH_USER: ${{ secrets.REDIS_SSH_USER }}
      DATABASE_HOST: ${{ secrets.DATABASE_HOST }}
```

### Option B — Copy the file

Copy `.github/workflows/builder.yml` to your repo. Set the same secrets.

## Secrets

| Name             | Required | Default                          |
| ---------------- | -------- | -------------------------------- |
| `REDIS_PASSWORD` | yes      | -                                |
| `DEPLOY_KEY`     | yes      | SSH key for tunnel and upload    |
| `REDIS_SSH_HOST` | yes      | `aerialis.garudalinux.org`       |
| `REDIS_SSH_PORT` | no       | `270`                            |
| `REDIS_SSH_USER` | no       | `package-deployer`               |
| `REDIS_PORT`     | no       | `6379`                           |
| `DATABASE_HOST`  | no       | `builds.garudalinux.org:210`     |
| `MANAGER_URL`    | no       | `https://builds.garudalinux.org` |

Do not set `REDIS_HOST`. The tunnel sets it to `127.0.0.1`.

## Settings

- `builders: 4` starts 4 runners (`gh-1` to `gh-4`). Maximum is `20`.
- `runtime: 340m` leaves time for the queue check.
- `builder_class: "4"` builds packages with `build_class` `4` or less.

The workflow allows only one run at a time for `chaotic-builder`. New runs wait.

## Schedule

The workflow runs at `30 */3 * * *` (every 3 hours at `:30`). If builds are still running, the new run waits.
