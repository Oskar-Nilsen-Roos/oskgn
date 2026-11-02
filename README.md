# osk/gn

A macOS menu bar app for the GitHub work waiting on you: pull requests and issues, self-hosted runners, and workflow runs, with notifications when any of them change.

- **Pull requests and issues** where your review is requested, that you opened, are assigned to, or are mentioned in. Group by reason, organization, repository, check status, review state or age.
- **Self-hosted runners** in every repository you administer: online, idle or busy, and the job each one is running. For runners on this Mac, the job's live log, CPU and memory.
- **Workflow runs** for the repositories you work in.
- **Notifications** for review requests, mentions, assignments, watched labels, checks, reviews, runners going on- or offline, and runs passing or failing. Set them globally, per organization or per repository, as a banner, Notification Center only, or off.

## Install

Requires macOS 14 or later and the [GitHub CLI](https://cli.github.com), signed in:

```sh
brew install gh
gh auth login
```

Download `oskgn-<version>.zip` from the [latest release](https://github.com/Oskar-Nilsen-Roos/oskgn/releases/latest), unzip it and move `osk/gn` to Applications. It updates itself; *Check for updates…* is in its settings.

osk/gn reads your token with `gh auth token` and keeps it in memory only. It talks to nothing but `api.github.com`, and GitHub's releases to look for updates.

## Build

```sh
./build.sh          # osk:gn.app, signed ad hoc for this Mac
./build.sh test     # build and run the tests
```

Needs Xcode (not only the Command Line Tools). `build.sh` downloads [Sparkle](https://sparkle-project.org) on first run.

## Release

Push a `v*` tag. The Release workflow runs `release.sh` on the self-hosted runner labelled `oskgn`, which tests, builds, signs with Developer ID, notarizes, and publishes the zip and the Sparkle appcast as a GitHub release.

```sh
git tag v0.1.0 && git push origin v0.1.0
```

One-time setup on the release Mac:

1. A Developer ID Application certificate in the login keychain (Xcode › Settings › Accounts › Manage Certificates). Put its full name in `SIGN_ID` in `release.sh`.
2. Notarization credentials, with an app-specific password from [account.apple.com](https://account.apple.com):
   `xcrun notarytool store-credentials oskgn --apple-id <apple-id> --team-id <team-id>`
3. The Sparkle signing key: `Sparkle/*/bin/generate_keys --account oskgn` after the first build. It keeps the private key in the keychain and prints the public key; put that in `ED_KEY` in `build.sh`. Back up the private key (`generate_keys --account oskgn -x <file>`): without it, installed copies can never update again.
4. The runner, from the repository's Settings › Actions › Runners › New self-hosted runner, installed in `~/actions-runner-oskgn` with the label `oskgn` and started as a service (`./svc.sh install && ./svc.sh start`).

## License

MIT. Bundles [Sparkle](https://github.com/sparkle-project/Sparkle) (MIT) and draws [Primer Octicons](https://github.com/primer/octicons) (MIT).
