# ⚡ CMD-Watch

**CMD-Watch notices when you repeatedly mistype terminal commands and offers to create a permanent alias — right there, in the moment.**

Type `push` instead of `git push` twice? CMD-Watch interrupts with a clean prompt, suggests the right command, and with a single keypress writes a permanent alias to your `.zshrc`. No configuration needed.

![CMD-Watch demo](demo.gif)

---

## Install

```sh
git clone https://github.com/MattX23/CMD-Watch.git ~/.cmd-watch
~/.cmd-watch/install.sh
source ~/.zshrc
```

Or manually add to your `~/.zshrc`:

```zsh
source "/path/to/cmdwatch.zsh"
```

---

## How it works

CMD-Watch hooks into zsh's built-in `command_not_found_handler` — called automatically whenever a command isn't found. It tracks how many times each unknown command is typed. Once you hit the threshold (default: 2), it shows an interactive prompt.

**"Did you mean?" suggestions come from:**
- Git subcommands — `push` → `git push`, `check` → `git checkout`
- Args you typed — `push origin main` → `git push origin main`
- npm/yarn scripts — if a `package.json` exists in the current directory tree

Aliases are written directly to your `.zshrc` under a `# cmdwatch aliases` section and activated immediately in the current session — no need to open a new terminal.

---

## Prompt options

| Key | Action |
|-----|--------|
| `1`–`9` | Instantly alias to that suggestion |
| `a` | Enter a custom expansion |
| `s` | Skip — keep tracking |
| `n` | Never ask about this command again |

---

## `cmdwatch` command

```sh
cmdwatch              # same as cmdwatch stats
cmdwatch stats        # show aliases, miss counts, and ignored commands
cmdwatch add [<cmd> [<expansion>]]  # manually create an alias
cmdwatch remove <cmd>               # remove an alias and resume tracking
cmdwatch unignore <cmd>             # resume watching a silenced command
cmdwatch reset <cmd>                # reset the miss count for a command
cmdwatch help                       # show all subcommands
```

---

## Configuration

Set these in your `.zshrc` **before** sourcing `cmdwatch.zsh`:

```zsh
CMDWATCH_THRESHOLD=3   # misses before prompting (default: 2)
CMDWATCH_DIR=~/.cmdwatch         # where counts and state are stored
CMDWATCH_ZSHRC=~/.zshrc          # which file aliases are written to
```

---

## Data files

All state lives in `~/.cmdwatch/`:

| File | Contents |
|------|----------|
| `count_<cmd>` | Miss count for that command |
| `ignored` | Commands that will never be prompted about |

---

## Requirements

- zsh 5.0+
- macOS or Linux

---

## Similar tools

- [`thefuck`](https://github.com/nvbn/thefuck) — corrects and reruns your last command when you type `fuck`. Reactive and ephemeral, doesn't create persistent aliases.
- [`alias-tips`](https://github.com/djui/alias-tips) — reminds you when you type a command you've already aliased. Complementary to CMD-Watch.

CMD-Watch fills a different niche: it watches for *patterns* in failed commands and turns them into *permanent shortcuts*.

---

## Contributing

Issues and PRs welcome. The entire tool is a single `cmdwatch.zsh` file — easy to read and hack on.
