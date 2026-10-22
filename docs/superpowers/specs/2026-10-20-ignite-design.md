# ignite: platform-engineering laptop setup

Design doc, 2026-10-20. Status: approved by the owner on 2026-10-20.

Notes in *italics* marked **(my call)** are decisions I made that the owner has not confirmed. Everything else reflects what the owner said.

## Intent

The owner is a platform engineer who keeps getting blank company laptops. Each time, they rebuild their workstation by hand. ignite is a repo they pull onto a new laptop and run, and it turns that laptop into their working setup.

There is one user. This is not a team onboarding tool, so it reflects one person's choices and does not need menus for anyone else.

## Where it runs

| System | How often | What gets set up |
|---|---|---|
| macOS (Apple Silicon) | most of the time | everything natively |
| Windows 11 | often | **both** native PowerShell *and* WSL (Ubuntu). The native side gets its own tools and profile, and WSL gets the Linux setup. |
| Linux | rarely | the Linux setup |

WSL and plain Linux run the same Linux path, so there is one Linux setup to maintain. *Ubuntu/Debian only. Fedora and Arch are out of scope.* **(my call)**

## Goals

1. **One command per system** takes a blank laptop to ready. After a few up-front questions it runs unattended, and it finishes with a checklist of what's left to do by hand (sign-ins, adding the SSH key, filling in secrets).
2. **One tool per job.** Every job (editor, terminal, prompt, local Kubernetes, ...) has exactly one default. Alternatives live in the repo but stay off unless turned on. Two tools for the same job never get installed by default.
3. **The same feel everywhere.** The prompt, aliases, tool versions and git setup match across macOS, WSL/Linux and PowerShell as closely as each system allows.
4. **Re-runnable.** Running it again on a set-up laptop is safe and only changes what's different. One command pulls the latest repo changes onto a laptop. *Changes made on one laptop can be sent back to the repo.* **(my call)**
   - *Add and update only. ignite never uninstalls anything. A tool switched off or dropped from the catalog stays installed until the owner removes it.* **(my call)**
   - *It's built for blank laptops. Running it on an already hand-built machine is not a supported migration in v1. chezmoi shows a diff and asks before overwriting any file that was changed locally, which protects files like today's `.zshrc` (where the GitLab token lives).* **(my call)**
   - *Commits to the ignite repo itself use a personal identity (the owner's GitHub noreply address), set by an `includeIf` on the chezmoi source directory. That way a work email never lands in the repo's history, even when changes are pushed from a company laptop.* **(my call)**

## Non-goals

- Onboarding other people, or supporting anyone else's preferences.
- Corporate IT's own software (MDM, VPN, endpoint security agents). The company installs those.
- macOS/Windows system preferences such as Dock, Finder or key repeat. *Out of scope for v1.* **(my call)**
- Personal apps on company laptops. They live in an off-by-default `personal` group. *The group exists because the owner may later want it on their own machine.* **(my call)**
- Claude Code's own config (`~/.claude`: CLAUDE.md, skills, hooks, settings). ignite installs Claude Code, and its config will go in a separate repo later. The catalog leaves room to pull that repo in as a chezmoi external.

## Anti-goals (a failure even if it technically works)

- **A secret, token, private key or employer-identifying value committed to the repo.** Today the owner's GitLab token sits in plain text in `~/.zshrc`. That file must never be copied into the repo as-is.
- **Duplicate tools for one job**, such as VS Code and Zed both installed by default, or nvm installed twice (both of which are true on the current Mac).
- **A run that dies halfway on a blank machine with no clear message.** A failed install is recorded, the run continues with everything else, and the final summary lists the failures.
- **Copying private SSH keys between laptops.** Each laptop gets its own key.
- **Fighting company policy** by disabling security tooling or working around MDM.

## Decided defaults (one per job)

The owner approved these:

| Job | Default | Off unless turned on |
|---|---|---|
| Editor | VS Code | Zed |
| Terminal editor | Neovim (LazyVim config); also `$EDITOR` and git's editor | plain vim |
| Terminal app | Ghostty (macOS, Linux); Windows Terminal (Windows) | Warp |
| Prompt | Starship, used in zsh, bash and PowerShell | powerlevel10k |
| Local Kubernetes | kind | minikube, Multipass |
| Language/runtime versions | mise | nvm |
| zsh plugins | autosuggestions, syntax-highlighting, zsh-bat, you-should-use, zsh-completions | zsh-autocomplete |
| AI coding assistant | Claude Code | Codex, Gemini CLI, Copilot, Cursor, opencode |

Switching to Starship means dropping the existing 90 KB powerlevel10k config. The owner accepted that.

## How it's built

### Engine: chezmoi **(my call)**

chezmoi manages the dotfiles and runs the install scripts. I chose it because it:
- runs natively on macOS, Linux and Windows/PowerShell
- renders one config template differently per OS
- asks per-machine questions once at init and remembers the answers
- re-runs install scripts only when their inputs change (`run_onchange_`)
- pulls git-hosted extras such as zsh plugins without a plugin manager (`.chezmoiexternal`)
- can read secrets from password managers or the OS keychain

I rejected the alternatives: Ansible has no Windows control node, Nix has no native Windows support, and plain scripts would mean rebuilding templating and secret handling from scratch.

The repo uses `.chezmoiroot` so that the chezmoi source tree sits in `home/`, with docs, tests and bootstrap scripts beside it.

### Bootstrap: one line per system

Thin bootstrap scripts install whatever chezmoi needs on a blank machine, then hand over to `chezmoi init --apply`:

- **macOS / Linux / WSL:** `bootstrap.sh`. On macOS it installs Xcode Command Line Tools and Homebrew. On Linux it installs `git curl zsh` via apt and sets zsh as the login shell.
- **Windows:** `bootstrap.ps1`. It checks for winget, installs PowerShell 7, git and Windows Terminal, and enables WSL with Ubuntu. Because WSL needs a reboot, the script ends by printing the Linux one-liner to run inside Ubuntu afterwards. The native PowerShell side is fully set up before that reboot.

The repo is a **public GitHub repo**, so the one-liners need no sign-in on a blank laptop:

```sh
curl -fsSL https://raw.githubusercontent.com/<github-user>/ignite/main/bootstrap.sh | bash
```
```powershell
irm https://raw.githubusercontent.com/<github-user>/ignite/main/bootstrap.ps1 | iex
```

Because the repo is public, nothing in it may name an employer or internal host. That includes the GitLab URL, company domains and internal hostnames. Values like these are asked at init (see below) and live only in the local chezmoi config. gitleaks guards against secrets, and a small denylist check in the pre-commit hook and CI guards against company names.

### With admin, without admin

Admin rights vary between company laptops, and sometimes there are none. The bootstrap **detects** whether the user can elevate (`sudo -n`/admin group on macOS and Linux, admin group membership on Windows), and `IGNITE_NO_ADMIN=1` forces the no-admin path.

- **With admin:** every admin step (Xcode CLT, Homebrew, enabling WSL, machine-scope installs, Docker/Rancher Desktop, apt) runs **first and together**, then the rest runs without elevation. That also covers time-limited elevation such as a Privileges-style app: grant it, run, and the admin part is done early.
- **Without admin:** everything that can be installed per-user still gets installed, and everything else becomes a "needs IT" list in the final checklist.
  - **CLIs:** mise into the home directory, the same path as with admin.
  - **macOS:** GUI apps that ship as a zip or dmg (VS Code, Ghostty) go to `~/Applications`. The font goes to `~/Library/Fonts`. If git is missing because Xcode CLT isn't installed, the clone uses chezmoi's built-in git, and CLT goes on the "needs IT" list.
  - **Windows:** Scoop (always per-user) stands in for winget's machine installs, and winget is still used for packages with a user-scope installer. If WSL is already enabled, the Ubuntu distro and the Linux setup still go ahead. If it isn't, WSL goes on the "needs IT" list.
  - **Linux:** apt is skipped. If zsh isn't present, a minimal bash profile gets the same Starship, zoxide, direnv and mise setup.
  - Docker Desktop, Rancher Desktop and Colima's VM support may need admin. If so, they go on the "needs IT" list.

### Per-machine questions (asked once at init, stored locally, never committed)

- Work email, used for git `user.email`
- Company git host: GitHub, or GitLab plus its URL. This decides whether `gh` or `glab` gets installed and configured as the credential helper. A laptop gets one of the two, never both.
- Cloud(s) used: AWS / Azure / GCP. Each turns on its CLI group (AWS → `awscli`, `eksctl`, the AWS VS Code extension; Azure → `az`, `kubelogin`; GCP → `gcloud`).
- Container engine; see below.
- **Alternatives are chosen per job, and choosing one replaces the default.** For example, `editor: vscode | zed` or `prompt: starship | powerlevel10k`. There is no "turn on all alternatives" switch, because that would install two tools for one job.
- Optional groups to turn on: `specialist`, `personal`.
- *Company root CA: the bootstrap scripts read an optional `IGNITE_CA_CERT` path, set before the one-liner runs, and install it before the first download. It then sets `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `NODE_EXTRA_CA_CERTS`, `AWS_CA_BUNDLE` and git `http.sslCAInfo`. This matters on laptops behind TLS-inspecting proxies such as Zscaler, Netskope or Cloudflare WARP. On Windows, the same CA is also installed into WSL's trust store. Unset means no CA handling.* **(my call)**

### Container engine (picked per laptop)

Docker Desktop needs a paid license at larger companies, so this is a per-laptop question: *"Does this company license Docker Desktop?"*

- **Yes:** Docker Desktop on macOS and Windows.
- **No:** *Colima on macOS, Rancher Desktop on Windows (which provides `docker` to both PowerShell and WSL).* **(my call)**
- Plain Linux always gets Docker Engine, which is free.

### One package catalog, many package managers

Every tool appears **once** in a single catalog, `home/.chezmoidata/packages.yaml`. Each entry records:
- the **job** it does, which is how duplicates get prevented
- its **group**: `core`, `cloud-aws`, `cloud-azure`, `cloud-gcp`, `github`, `gitlab`, `specialist`, `alt`, or `personal`
- **where to install it from on each OS**

Templates turn the catalog into the per-OS install lists:

- **mise** for versioned CLIs (kubectl, helm, terraform, k9s, argocd, flux, go, node, python, ...). mise runs on all three systems, so one `~/.config/mise/config.toml` gives the same versions on macOS, WSL and native Windows. *Tools float to latest unless the catalog pins them.* **(my call)**
- **Homebrew** (macOS), **winget** (Windows) and **apt** (Linux) for GUI apps, fonts, system packages, and any CLI that mise can't provide on that OS.
- **krew** for kubectl plugins.
- **`code --install-extension`** for VS Code extensions. Under WSL, VS Code runs on the Windows side through Remote-WSL; nothing gets installed inside WSL.

A catalog check, run in CI and as a pre-commit hook, fails if two default-on entries share a job.

### Shell

- **zsh** (macOS, Linux, WSL): oh-my-zsh with the owner's built-in plugin list (direnv, docker, docker-compose, history, git, kubectl, helm, aws, ansible, terraform, encode64, jsontools), the five extra plugins pulled via `.chezmoiexternal`, Starship, the current history settings (50k entries, shared, no dups), the lazy-completion helper from today's `.zshrc`, zoxide, direnv, and mise activation.
- *On Windows, the native PowerShell side gets the full `core` and cloud toolset, minus tools with no native Windows build (ansible, tmux, the zsh plugins). WSL is a complete Linux workbench of its own.* **(my call)**
- **PowerShell 7** (native Windows): Starship, PSReadLine prediction and syntax colouring (the closest match to autosuggestions and syntax highlighting), zoxide, completions for the same CLIs via `<tool> completion powershell`, and the same short aliases as zsh where PowerShell allows. The profile path must work when OneDrive redirects `Documents`, which is common on company laptops.
- **Windows Terminal:** pwsh as the default profile, a WSL Ubuntu profile, the Nerd Font, and the Catppuccin Mocha scheme. *Added through a Windows Terminal JSON fragment so that ignite doesn't take over `settings.json`.* **(my call)**
- **Font:** Hack Nerd Font everywhere, since Starship's icons need it.

### Editors and terminal configs

- **VS Code:** `settings.json` captured from the current Mac, plus a cleaned-up extension list (see appendix), with the per-OS settings path handled.
- **Neovim:** the current `~/.config/nvim` (LazyVim) as-is.
- **Ghostty:** the current config (Catppuccin Mocha, font-size 19, 0.7 opacity, blur 20, option-as-alt, hide mouse while typing).

### Git and SSH

- `.gitconfig` template: name, email (asked at init), editor `nvim`, a global excludes file, `core.hooksPath ~/.git-hooks` (the owner's global pre-commit hook that rejects `.claude/` files), and a credential helper based on the git host answer.
- `.gitignore_global` copied over.
- **SSH:** each laptop generates its own ed25519 key. *On Windows, native and WSL each generate their own key, with no agent bridging, so the checklist lists two keys to register.* **(my call)** The final checklist prints the public key and where to add it. `~/.ssh/config` is templated, with `AddKeysToAgent` everywhere and `UseKeychain` on macOS.

### Secrets

Nothing secret goes in the repo. The owner doesn't use a password manager, so setup creates `~/.config/ignite/secrets.env` (or `secrets.ps1` on Windows), readable only by the owner (mode 600, or the equivalent ACL on Windows). It lists the expected names (`GITLAB_PRIVATE_TOKEN`, ...) with empty values. The shell loads it, and the final checklist asks the owner to fill it in. Re-running setup never overwrites values already filled in. The repo also runs gitleaks as a pre-commit hook and in CI.

### `ignite doctor`

A command on every system (`ignite-doctor` for sh, `ignite-doctor.ps1` for PowerShell). It reads the same catalog and reports each expected tool as present or missing with its version, flags duplicate jobs, and lists the manual steps still to do. The bootstrap ends by running it, and CI uses it as the pass/fail check.

## Verification

- **CI:** GitHub Actions on `macos-latest`, `windows-latest` and `ubuntu-latest`. Each job runs the bootstrap non-interactively, with init answers passed via chezmoi's `--promptString` / `--promptChoice` flags, then runs `ignite doctor`, which must report no missing core tools.
- **No-admin path in CI:** one extra job per OS runs with `IGNITE_NO_ADMIN=1`. It checks that the run finishes, that every per-user tool is present, and that everything else shows up on the "needs IT" list instead of failing.
- **Idempotency:** each CI job runs apply a second time and checks that nothing changed.
- **Linux locally:** an Ubuntu container runs the Linux path.
- **Real test:** a fresh macOS VM and a fresh Windows 11 VM, before relying on it for a real new laptop. *The VM tooling is the builder's choice.*

## Left to the builder

- The exact per-OS install source for each tool, verified to work. Where mise's backends don't cover a tool on Windows, fall back to winget.
- The catalog schema details and template structure.
- PowerShell module choices beyond the ones above.
- Which version to pin, if any.
- The VM tooling for the real-machine test.

## Decided after review

- **Repo:** public GitHub.
- **Admin rights:** they vary, and are sometimes absent, so the setup supports both with-admin and no-admin paths.
- **Claude Code config:** a separate repo, later. Out of scope for ignite v1.
- **Secrets:** a local secrets file. No password manager.

## Appendix: starting inventory (from the owner's current Mac, 2026-10-20)

**core**: kubectl, helm, k9s, kustomize, kubeconform, kind, argocd, flux, terraform, tflint, terraform-docs, ansible, pre-commit, git, jq, yq, direnv, zoxide, ripgrep, bat, tree, wget, curl, uv, python, go, node, neovim, tmux, Starship, mise, Claude Code. krew plugins: ctx, ns, neat, view-secret.

**cloud-aws**: awscli, eksctl. **cloud-azure**: az, kubelogin. **cloud-gcp**: gcloud.

**github** (company git host is GitHub): gh. **gitlab** (company git host is GitLab): glab.

**specialist** (off): cilium-cli, istioctl, clusterctl, clusterawsadm, kops, vault, teleport (tsh), k6, libpq (psql), mkcert, krew `cnpg`, Java toolchain (openjdk, maven, gradle, coursier).

**alt** (off): Zed, Warp, minikube, Multipass, powerlevel10k, nvm, zsh-autocomplete, Codex, Gemini CLI, Copilot CLI, Cursor, opencode.

**macOS desktop extras** (default on, macOS only): Rectangle, AltTab, Maccy. **(my call)**

**personal** (off): Anki, Kindle, Telegram, Obsidian, ffmpeg, yt-dlp, whisper.cpp, imagemagick, poppler, hugo, vhs, blueutil, Garmin tooling.

**VS Code extensions (default)**: dropping duplicates leaves one per job. hashicorp.terraform (not 4ops / erd0s / azureterraform); github.vscode-github-actions (not the second Actions extension); yzhang.markdown-all-in-one + davidanson.vscode-markdownlint (not markdown-shortcuts / markdown-preview-enhanced); ms-azuretools.vscode-containers (not docker.docker as well); ms-python.python + pylance + debugpy (not the donjayamanne packs); ms-kubernetes-tools.vscode-kubernetes-tools, redhat.vscode-yaml, tim-koehler.helm-intellisense, golang.go, eamodio.gitlens, mkhl.direnv, ms-vscode-remote.remote-ssh, remote-containers, remote-wsl (Windows only), anthropic.claude-code, vscodevim.vim, streetsidesoftware.code-spell-checker, jeff-hykin.better-shellscript-syntax, pkief.material-icon-theme, sdras.night-owl. Cloud-gated: amazonwebservices.aws-toolkit-vscode. Everything else (Jupyter, PlantUML, draw.io, Excalidraw, Anki, Foam, Java migration, CSV tools, React) goes in `personal`.
