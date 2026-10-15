# diffy

A Plannotator-style local git diff reviewer. It runs on your own machine, shows
your repos' changes in the browser, lets you comment on lines or whole files,
and POSTs the review as JSON to a webhook of your choice. It was built to feed
review comments to [Grok Bot](https://grokbot.com) webhook routines, but any
endpoint that accepts JSON works.

- Single Python 3 file, standard library only. No build step, no npm.
- Sidebar with **Tree / Git status / Commits** tabs, folder tree with +/- counts,
  viewed checkmarks (saved in localStorage), search and hide-viewed filter.
- Scopes: all changes since a base branch, uncommitted, staged, unstaged,
  last commit, or any single commit.
- Split or unified view, syntax highlighting (vendored highlight.js, no CDN).
- Line comments, file comments, an overall summary, and one Submit button.

## Quick start

Needs `python3` and `git` (Linux or macOS).

```sh
git clone https://github.com/vinzloh/diffy.git ~/workspace/diffy && cd ~/workspace/diffy && ./install.sh --roots ~/workspace
diffy serve
```

`--roots` is required: the folder(s) that hold your repos (comma-separated).
diffy never scans your whole home folder; without `--roots` an interactive
install asks for the folder and a non-interactive one stops with an error.
The installer also asks for the webhook URL and key (hidden) and a machine label
(default: short hostname), writes `~/.config/diffy/config.json` (mode 600),
links `~/.local/bin/diffy` to the clone (so keep the clone where it is), and
prints the label and the repos it found. Options:

- `--roots DIR[,DIR]` **required**: folders to scan for repos, 4 levels deep (or set `DIFFY_ROOTS`)
- `--machine LABEL` name sent as `machine` (default: `hostname -s`)
- `--port 4747` (default) and `--host 127.0.0.1` (default, this machine only), saved as the defaults for `diffy serve`.
  Use `--host 0.0.0.0` to reach it from other devices, see [Security](#security).

Re-run it with any flag to change the config later (e.g. `./install.sh --port 5000`).
**Non-interactive install (CI and scripts only, not for agents):** set
`DIFFY_WEBHOOK_URL` and `DIFFY_WEBHOOK_KEY` (and optionally `DIFFY_ROOTS`,
`DIFFY_MACHINE`) and run with stdin not a terminal. Read the key from a file or
secret manager so it stays out of shell history:

```sh
DIFFY_WEBHOOK_URL=https://example.com/webhook \
DIFFY_WEBHOOK_KEY="$(cat /path/to/keyfile)" \
./install.sh --roots ~/code </dev/null
```

## Setup for agents

A recipe for an AI agent (Grok Bot, Cursor, Claude Code, ...) helping a user
install diffy. The agent does the setup around the install; **the user types the
webhook URL and key themselves**, in their own terminal.

**Rules for agents:** never ask for the webhook key, never store it, never copy
it between machines, and never pass it through environment variables or
command arguments. Never guess the repo folder or use the home folder; ask.
Every step is safe to re-run.

1. Check prerequisites. If either is missing, install it with the system
   package manager (e.g. `sudo pacman -S python git`, `sudo apt install python3 git`,
   `brew install python git`) or ask the user to.

   ```sh
   command -v python3 && command -v git
   ```

2. Clone, or update an existing clone:

   ```sh
   DIR=~/workspace/diffy
   if [ -d "$DIR/.git" ]; then git -C "$DIR" pull --ff-only; else git clone https://github.com/vinzloh/diffy.git "$DIR"; fi
   ```

3. Ask the user which folder holds their repos (for example `~/workspace`).

4. Hand over. Tell the user to run this in their own terminal and answer the
   prompts (webhook URL, key, typed hidden, and a confirm for the folder):

   ```sh
   cd ~/workspace/diffy && ./install.sh --roots <folder>
   ```

   Wait for them to say it's done. If diffy is already set up, the installer
   keeps the existing URL and key and doesn't ask again.

5. Verify, then stop (or leave it running if the user wants):

   ```sh
   ~/.local/bin/diffy serve >/dev/null 2>&1 & PID=$!
   for i in $(seq 1 15); do sleep 1; curl -fs -o /dev/null http://localhost:4747/ && break; done
   curl -s -o /dev/null -w '%{http_code}\n' http://localhost:4747/   # expect 200
   ~/.local/bin/diffy ping                                            # expect "ping: 200"
   kill $PID
   ```

   Show the user the repos it found (`~/.local/bin/diffy rediscover`) so they
   can check them; re-running step 4 with another `--roots` changes them.

6. Tell the webhook receiver what to expect: `action` (`submit`, or `ping`
   to ignore), `machine`, `repo`, `branch`, optional `scope`/`base`/`commit`,
   `summary`, and `comments[]` of `{file, line, side, code, text}` (`line`
   null for file comments). Full schema: [Webhook payload](#webhook-payload).

7. Uninstall: `~/workspace/diffy/install.sh --uninstall && rm -rf ~/workspace/diffy`

### Using with Grok Bot

Create a webhook routine on your Grok Bot whose prompt treats the POST body as
untrusted data and acts on `action: "submit"` (for example, hand the comments
to the bot that owns that repo) while ignoring `ping`. Copy the routine's
webhook URL and sender key from its panel and paste them into the installer's
prompts yourself. Your agent can run every other step.

## Run

diffy runs on demand in the foreground. Start it in a terminal, tmux or Herdr
pane, open the URL it prints, and press Ctrl+C when you're done:

```sh
diffy serve                      # http://localhost:4747/ (this machine only)
diffy serve --port 5000
diffy serve --host 0.0.0.0       # also reachable from other devices, e.g. over Tailscale
```

With `--host 0.0.0.0` diffy turns on a **passcode** and prints it, plus
links for localhost, Tailscale and LAN with the passcode built in:

```text
diffy on http://localhost:4747/?k=Xy3kP9aQwRt
  tailscale: http://100.x.y.z:4747/?k=Xy3kP9aQwRt
  lan: http://192.168.1.20:4747/?k=Xy3kP9aQwRt
  passcode: Xy3kP9aQwRt  (open a link once per browser; a cookie keeps you in until diffy restarts)
Ctrl+C to stop
```

Click a link once per browser. diffy checks the code, sets a session cookie
and drops `?k=` from the address bar. Without the cookie you get a passcode
box instead. A new random passcode is made every run. To keep one fixed,
add `"passcode": "..."` to `~/.config/diffy/config.json`. `--passcode CODE`
works too, but it ends up in your shell history. Plain `diffy serve`
(localhost) has no passcode.

Other commands:

```sh
diffy rediscover    # re-scan for repos and print them (also runs at every start)
diffy ping          # send {"action":"ping"} to the webhook once
```

**Update:** `git pull` in the clone, restart `diffy serve`, hard-refresh the page.
**Uninstall:** `./install.sh --uninstall` (removes the config and the `diffy`
link, and any systemd service from older versions), then delete the clone.

## Config

`~/.config/diffy/config.json` (mode 600, never inside the repo):

```json
{
  "url": "https://example.com/webhook",
  "key": "your-webhook-key",
  "machine": "laptop",
  "roots": ["~/code"],
  "depth": 4,
  "repos": ["~/code/app", "~/work/api"],
  "port": 4747,
  "host": "127.0.0.1"
}
```

`url`, `key` and `roots` (or `repos`) are required. `machine` defaults to the short hostname.
Repos: diffy shows the repos listed in `repos` plus any git repos found under
`roots`, scanning up to `depth`
levels for git repos, skipping hidden and dependency folders. A repo's name is
its directory name. Run `diffy rediscover` after adding repos.

## Webhook payload

On Submit, the **server** (never the browser) sends one POST with
`Content-Type: application/json`, `Authorization: Bearer <key>` and
`X-Automation-Key: <key>`, an 8-second timeout and no retry:

```json
{
  "action": "submit",
  "machine": "laptop",
  "repo": "app",
  "branch": "feature/x",
  "scope": "all | uncommitted | staged | unstaged | last | commit",
  "base": "origin/main",
  "commit": "full sha, only for a commit view",
  "summary": "overall comment, may be empty",
  "comments": [
    {"file": "src/a.ts", "line": 12, "side": "new", "code": "+const x = 1", "text": "rename this"},
    {"file": "src/b.ts", "line": null, "side": null, "code": null, "text": "file-level comment"}
  ]
}
```

`scope`, `base` and `commit` are optional. `side` is `new` or `old`. `diffy ping`
sends `{"action":"ping","machine":...}`, which receivers should ignore.
If a POST fails, the payload is appended to `~/.config/diffy/pending.jsonl`
and the error is shown in the page.

## Security

- Read-only on git: diffy only runs `diff`, `show`, `log`, `status`,
  `ls-files`, `rev-parse`, `merge-base` and `for-each-ref`. It never stages,
  commits, checks out or writes to your repos.
- The webhook key stays in the config file on the server side. It is never
  sent to the browser or logged.
- By default diffy binds `127.0.0.1`, so only this machine can open it, and
  there is no passcode.
- With a non-loopback `--host` (e.g. `0.0.0.0`) every route, including the
  API and Submit, needs a passcode or a session cookie. The cookie is
  `HttpOnly` and `SameSite=Strict` and stops working when diffy restarts.
  Codes are compared in constant time. Each wrong attempt waits 1 s, and an
  IP is locked out for 10 minutes after 10 wrong attempts.
- Traffic is plain HTTP, so keep it on a private network such as a
  Tailscale tailnet (which encrypts it), not the open internet.

## License

MIT, see [LICENSE](LICENSE). highlight.js is vendored under its BSD-3-Clause
license in [vendor/highlight.js/LICENSE](vendor/highlight.js/LICENSE).
