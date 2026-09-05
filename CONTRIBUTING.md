# Contributing

## Branching strategy (Git Flow)

- **`main`** is reserved for releases and hotfixes only. Do not branch features from it or push directly to it.
- **`develop`** is the default branch and integration branch for ongoing work.
- Feature branches are cut from `develop` and named `feature/TRAIN-<id>-<short-description>`.
- Hotfixes are cut from `main` and named `hotfix/TRAIN-<id>-<short-description>`; they merge back into both `main` and `develop`.
- Releases are cut from `develop` and named `release/<version>`; they merge into `main` (and back into `develop`).

Pull requests are validated automatically:
- PRs into `main` are only accepted from `release/*` or `hotfix/*` branches.
- PRs into `develop` are accepted from anything except `main`.
- PRs may only target `main` or `develop`.

See `.github/workflows/enforce-merge-policy.yml` for the enforcement logic and `.github/workflows/swift.yml` for CI (build + test on every push/PR to `main` and `develop`).
