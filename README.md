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

## Install

Needs Linux with systemd (user services), `python3` and `git`.

```sh
git clone <this repo> ~/code/diffy
cd ~/code/diffy
./install.sh            # asks for webhook URL, key (hidden), machine label
```

Options: `--port 4747` (default), `--host 0.0.0.0` (default). The installer is
idempotent: it writes `~/.config/systemd/user/diffy.service`, enables and
restarts it, and links `~/.local/bin/diffy`.

**Update:** `git pull && ./install.sh`
**Uninstall:** `./install.sh --uninstall` (keeps `~/.config/diffy/`; delete it if you want)

### CLI

```sh
diffy serve [--host H] [--port N]   # what the service runs
diffy rediscover                    # re-scan for repos and print them
diffy ping                          # send {"action":"ping"} to the webhook once
```

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

Only `url` and `key` are required. `machine` defaults to the hostname.
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
