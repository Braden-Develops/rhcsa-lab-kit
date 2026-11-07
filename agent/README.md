# Lab host agent

`labkit-agent` is a small service that runs on the machine that hosts your labs. With it, this site can **start, grade, reset and stop labs** and give you a **root shell in the browser**. It also keeps your **notes** in a git repo.

```
browser (GitHub Pages site, or the agent's local copy)
   │  HTTPS + WebSocket, only inside your Tailscale network
   ▼
tailscale serve  ──►  labkit-agent on 127.0.0.1:8737  ──►  ./lab start|check|reset|stop|shell NN
                                                       └─►  ~/rhcsa-notes (git, pushed to a private repo)
```

## Why this is safe on a public site

- **The site holds no secrets.** The agent's address and token are kept only in your browser's local storage.
- **Nothing is exposed to the internet.** The agent listens on `127.0.0.1`, and `tailscale serve` publishes it only to devices on *your* tailnet, with a real HTTPS certificate. Don't port-forward it or bind it to a public interface.
- **Token on every call.** API calls send `Authorization: Bearer <token>`. The terminal WebSocket sends the token as its first message, and the agent drops the connection if it's wrong.
- **Origin allow-list.** The agent only accepts browser requests from `https://braden-develops.github.io`, from localhost, and from its own address. Add others to `allowed_origins` in the config.
- **Fixed commands only.** The API can run `./lab start|check|reset|stop NN` and open `./lab shell NN`, with `NN` checked against the labs that exist. There is no generic command runner. The shell it opens is inside the lab container or VM, not on the host.
- **Runs as your user, not root.** It uses rootless Podman and your user's libvirt access.

## Install on the lab host (Ubuntu 24.04+)

1. **Lab prerequisites:** Podman for the container labs, and Vagrant + libvirt for the VM labs.
   ```bash
   sudo apt install -y git python3 podman qemu-kvm libvirt-daemon-system libvirt-dev ruby-dev build-essential
   sudo usermod -aG libvirt,kvm "$USER"          # log out and back in afterwards
   # Vagrant from HashiCorp's apt repo: https://developer.hashicorp.com/vagrant/install#linux
   vagrant plugin install vagrant-libvirt
   ```
2. **Get the kit and check that it works on its own:**
   ```bash
   git clone https://github.com/Braden-Develops/rhcsa-lab-kit ~/rhcsa-lab-kit
   cd ~/rhcsa-lab-kit && ./lab start 01 && ./lab check 01
   ```
3. **Create the agent's config, token and notes repo:**
   ```bash
   python3 agent/labkit-agent.py init      # prints the token; `... token` prints it again
   ```
   The config is in `~/.config/labkit-agent/config.json` (mode 600).
4. **Run it as a user service:**
   ```bash
   mkdir -p ~/.config/systemd/user && cp agent/labkit-agent.service ~/.config/systemd/user/
   systemctl --user daemon-reload && systemctl --user enable --now labkit-agent
   sudo loginctl enable-linger "$USER"
   journalctl --user -u labkit-agent -f     # logs
   ```
5. **Publish it to your tailnet over HTTPS.** In the Tailscale admin console, turn on MagicDNS and HTTPS certificates first.
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   sudo tailscale serve --bg 8737
   tailscale serve status                   # shows https://<host>.<tailnet>.ts.net
   ```
6. **Connect the site.** Open **Lab host** in the site's sidebar, paste the `https://…ts.net` URL and the token, then press **Save and test**.
   You can also open `https://<host>.<tailnet>.ts.net` directly. The agent serves its own copy of the site there and connects to itself automatically, so you only need to paste the token.

## Back up your notes

Notes are Markdown files, one per lecture, guide section or lab (`lecture-4.md`, `lab-06.md`, …).

**Without a lab host:** on the site's **My notes** page, open **GitHub backup** and paste a fine-grained token that can only write to a private `rhcsa-notes` repo. The site then commits each note to that repo itself.

**With the agent:** the agent keeps notes in `~/rhcsa-notes`. It commits about 20 seconds after you stop typing, then pulls with `--rebase` and pushes, so it can share one repo with the site's GitHub backup. If that repo already exists, clone it into place **before** running `init`. `init` leaves an existing repo alone:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/rhcsa-notes -N ''      # add the .pub to the repo as a deploy key with write access
GIT_SSH_COMMAND="ssh -i ~/.ssh/rhcsa-notes" git clone git@github.com:<you>/rhcsa-notes.git ~/rhcsa-notes
git -C ~/rhcsa-notes config core.sshCommand "ssh -i ~/.ssh/rhcsa-notes"
python3 agent/labkit-agent.py init
```

The site also keeps a copy of every note in your browser, so notes still work offline and sync the next time they can.

## API (for reference)

| Method | Path | |
|---|---|---|
| GET | `/api/status` | running lab containers, VM state, busy job, notes git status |
| POST | `/api/labs/NN/{start,reset,check,stop}` | runs `./lab <action> NN`, returns `{job}`. Only one start/reset/stop runs at a time. |
| GET | `/api/jobs/ID?offset=N` | job output from byte N, plus `done` and `rc` |
| WS | `/api/term?lab=NN` | first message `{"token","cols","rows"}`; then binary frames are keystrokes/output, text frames are JSON (`{"cols","rows"}` resize, `{"exit":true}`) |
| GET/PUT | `/api/notes/KEY` | `{text, updated}` |
| GET | `/api/notes` | every note key and its mtime |

Only Python 3.8+ is needed: no pip packages. Lab 05 (boot) needs the VM's console for GRUB, not a shell. Use `virt-manager` on the host for that lab.
