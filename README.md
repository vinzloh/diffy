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
git clone https://github.com/vinzloh/diffy.git ~/workspace/diffy && cd ~/workspace/diffy && ./install.sh
diffy serve
```

The installer asks for the webhook URL and key (hidden) and a machine label
(default: short hostname), writes `~/.config/diffy/config.json` (mode 600),
links `~/.local/bin/diffy` to the clone (so keep the clone where it is), and
prints the label and the repos it found. Options:

- `--roots DIR[,DIR]` folders to scan for repos (default: `~`, 4 levels deep)
- `--machine LABEL` name sent as `machine` (default: `hostname -s`)
- `--port 4747` (default), `--host 0.0.0.0` (default), saved as the defaults for `diffy serve`

Re-run it with any flag to change the config later (e.g. `./install.sh --port 5000`).
For a non-interactive install, see [Setup for agents](#setup-for-agents).

## Setup for agents

A recipe an AI agent (Grok Bot, Cursor, Claude Code, ...) can run end to end.
The only inputs needed from the user are the webhook URL and key.

**Rules:** never echo, print or log the key, and never ask for it in chat. Read
it from the user's secret store or an environment variable, and pass it only via
`DIFFY_WEBHOOK_KEY`. Every step is safe to re-run.

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

3. Install without prompts (an existing config is kept; flags update it):

   ```sh
   DIFFY_WEBHOOK_URL="$URL" DIFFY_WEBHOOK_KEY="$KEY" "$DIR/install.sh" --roots ~/workspace </dev/null
   ```

   Drop `--roots` to scan all of `~`. Check the printed machine label and repo
   list with the user; re-run with `--roots` or `--machine` to change them.

4. Verify, then stop (or leave it running if the user wants):

   ```sh
   ~/.local/bin/diffy serve >/dev/null 2>&1 & PID=$!
   for i in $(seq 1 15); do sleep 1; curl -fs -o /dev/null http://localhost:4747/ && break; done
   curl -s -o /dev/null -w '%{http_code}\n' http://localhost:4747/   # expect 200
   ~/.local/bin/diffy ping                                            # expect "ping: 200"
   kill $PID
   ```

5. Tell the webhook receiver what to expect: `action` (`submit`, or `ping`
   to ignore), `machine`, `repo`, `branch`, optional `scope`/`base`/`commit`,
   `summary`, and `comments[]` of `{file, line, side, code, text}` (`line`
   null for file comments). Full schema: [Webhook payload](#webhook-payload).

6. Uninstall: `"$DIR/install.sh" --uninstall && rm -rf "$DIR"`

### Using with Grok Bot

Create a webhook routine on your Grok Bot whose prompt treats the POST body as
untrusted data and acts on `action: "submit"` (for example, hand the comments
to the bot that owns that repo) while ignoring `ping`. Copy the routine's
webhook URL from its panel, and give the sender key to the agent as a secret
(the app's secret box, never chat). Then run the recipe above with those values.

## Run

diffy runs on demand in the foreground. Start it in a terminal, tmux or Herdr
pane, open the URL it prints, and press Ctrl+C when you're done:

```sh
diffy serve                      # http://0.0.0.0:4747
diffy serve --host 127.0.0.1 --port 5000
```

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
  "host": "0.0.0.0"
}
```

Only `url` and `key` are required. `machine` defaults to the short hostname.
Repos: if `repos` is set, only those are shown (plus anything under `roots` if
`roots` is also set). Otherwise diffy scans `roots` (default `~`) up to `depth`
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
- There is **no authentication** on the page. By default it binds `0.0.0.0`
  so other devices (e.g. on your Tailscale tailnet) can reach it. Anyone who
  can reach the port can read your diffs and submit reviews. Use
  `--host 127.0.0.1`, a firewall, or keep the port to a private network such
  as Tailscale.

## License

MIT, see [LICENSE](LICENSE). highlight.js is vendored under its BSD-3-Clause
license in [vendor/highlight.js/LICENSE](vendor/highlight.js/LICENSE).
