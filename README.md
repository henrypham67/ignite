# ignite

One command turns a blank company laptop into my platform-engineering setup: macOS, Windows (PowerShell and WSL) or Ubuntu. It's built on [chezmoi](https://www.chezmoi.io) and [mise](https://mise.jdx.dev).

## Run it

macOS, Linux or WSL:

```sh
curl -fsSL https://raw.githubusercontent.com/henrypham67/ignite/main/bootstrap.sh | bash
```

Windows, from a normal (not elevated) PowerShell window:

```powershell
irm https://raw.githubusercontent.com/henrypham67/ignite/main/bootstrap.ps1 | iex
```

It asks a few questions (work email, company git host, which clouds, whether Docker Desktop is licensed, optional tool groups), installs everything, then runs `ignite-doctor`. The doctor lists what's installed, what's missing, and what's left to do by hand: sign-ins, adding the SSH key, filling in secrets. On Windows it also prints the one-liner to run inside Ubuntu once WSL is up.

Running it again is safe. It only adds or updates things, and never uninstalls. On the first run, any file it's about to replace (a `.zshrc` or `.gitconfig` from the company image, say) is copied to `~/.config/ignite/backup-<time>/` first. After that, chezmoi asks before overwriting a file you've changed.

## With or without admin

The bootstrap checks whether you can get admin rights.

With admin, the admin-only steps run first and together: Xcode tools, Homebrew, apt, machine-wide winget installs, enabling WSL, Docker or Rancher Desktop. If your company hands out admin for a limited time, grant it, run the bootstrap, and that part is finished early.

Without admin, everything that can be installed per user still gets installed. CLIs come from mise, apps go to `~/Applications` on a Mac, and Windows uses Scoop and per-user winget installers. The rest shows up in the doctor under "Needs IT".

## Environment variables

| Variable | What it does |
|---|---|
| `IGNITE_CA_CERT` | Path to the company root CA, for laptops behind a TLS-inspecting proxy. It's trusted before anything downloads, and curl, git, Python, Node and the AWS CLI are pointed at it. |
| `IGNITE_NO_ADMIN=1` | Take the no-admin path even when sudo or UAC would work. |
| `IGNITE_SKIP` | Comma-separated catalog entries to leave out, e.g. `docker-desktop,multipass`. |
| `GITHUB_TOKEN` | Used by mise when resolving tool versions. Set it if installs fail with a GitHub rate limit. |
| `IGNITE_REPO`, `IGNITE_REF` | Install from a fork or a branch. |

## Day to day

- Check the machine with `ignite-doctor` (`ignite-doctor.ps1` on Windows).
- Pull changes with `chezmoi update`.
- Retry failed installs with the commands the doctor prints under "Failed installs". They reset only the install steps that failed, then run `chezmoi apply`.
- To switch a tool, run `chezmoi edit-config`, set it under `[data.ignite.choices]` (for example `editor = "zed"`), then run `chezmoi apply`. The jobs and their options are in `home/.chezmoidata/choices.yaml`. The old tool stays installed and the doctor lists it as a duplicate.
- Secrets go in `~/.config/ignite/secrets.env` (`secrets.ps1` on Windows). The file starts out with the expected names, only you can read it, your shell loads it, and it's never committed.
- Settings for one machine only go in `~/.zshrc.local`, `~/.bashrc.local`, `~/.gitconfig.local`, `~/.ssh/config.local` or `~/.config/powershell/profile.local.ps1`, which are loaded if they exist.

## How it works

`home/` is the chezmoi source. Everything installed is listed once in `home/.chezmoidata/packages.yaml`. Each entry does one job (editor, prompt, local Kubernetes, …) and says where it comes from on each OS. Each job gets exactly one tool: either it has a single entry, or it has alternatives and `choices.yaml` picks one. A check fails the build if two entries ever compete for the same job.

For each machine, `home/.chezmoitemplates/selected.json` works out which entries apply and how each gets installed. The install scripts in `home/.chezmoiscripts/` and `ignite-doctor` are rendered from that one list. When an install fails, the run records it and carries on, and the doctor reports it at the end.

## Adding a tool

Add an entry to `home/.chezmoidata/packages.yaml`:

```yaml
  dive:
    job: container_image_explorer
    group: core          # or cloud-aws, specialist, personal, ...
    mise: dive           # check the name with `mise registry dive`
```

Then run `mise run validate` and `mise run test`.

## Working on ignite

```sh
mise install                          # chezmoi, bats, shellcheck, gitleaks, pwsh
git config core.hooksPath .githooks   # gitleaks, denylist and catalog checks on commit
mise run test                         # bats
mise run pester                       # Pester (Install-Module Pester first)
mise run lint                         # shellcheck + PSScriptAnalyzer, including rendered scripts
mise run e2e-linux                    # full bootstrap in a throwaway Ubuntu container
```

The repo is public, so nothing in it may name an employer or an internal host. Put those words, one per line, in `~/.config/ignite/denylist.txt`. The pre-commit hook then refuses any commit that contains them. CI reads the same list from the `IGNITE_DENYLIST` secret.

## Not covered

- macOS and Windows system preferences.
- Claude Code's own config, which will get its own repo.
- The Kindle app (Mac App Store only) and Garmin tooling.
- Migrating a laptop that was set up by hand. ignite is built for blank machines.
- Uninstalling anything.
