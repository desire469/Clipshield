# clipshield.nvim

Keeps secrets out of your clipboard. ([По-русски](README.ru.md))

You keep a list of values you never want to paste anywhere — API keys, tokens, passwords. They stay
fully visible while you edit, and your files are never modified. The moment you copy text to the
**system clipboard**, any of those values in it are substituted for a placeholder.

When you add a value you say what it should read as. Give a hostname a fake hostname and your logs
still make sense to you; say nothing and it becomes `REDACTED1`, `REDACTED2`, numbered so that two
different secrets never look like the same one.

```
# in your editor                          # in your clipboard
OPENAI_KEY=sk-proj-Ab3xK9zzQq             OPENAI_KEY=REDACTED1
GH_TOKEN=ghp_7fQ2mLwPd                    GH_TOKEN=REDACTED2
error.log  mysite.example                 error.log  site1.internal
```

Paste that into a chat window, an issue, a message to a colleague — the keys are not in it.

## What it does not protect against

**Selecting text with the mouse in your terminal does not go through Neovim, and is not masked.**
Your terminal copies straight from its own screen buffer; the plugin never sees it. If you copy by
dragging with the mouse, this plugin does nothing for you at all. Copy with `y` from Neovim, or
don't rely on it.

It also does not hide anything on screen, does not touch your files, and does not scan for things
that merely *look* like secrets — a value is masked because you added it, never because it was
guessed. See [docs/adr/0001-mask-clipboard-only.md](docs/adr/0001-mask-clipboard-only.md) for why.

The one workaround for mouse selections: a compositor-level keybind can hand the selection to the
plugin after the fact — see [From outside Neovim](#from-outside-neovim-hyprland).

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "desire469/Clipshield" }
```

No `setup()` call is needed — it works as soon as it is installed.

## Use

| Mapping        | Mode   | Does                                                    |
| -------------- | ------ | ------------------------------------------------------- |
| `<leader>sa`   | visual | Add the selection, asking what it should read as        |
| `<leader>sA`   | visual | Add the selection with the default placeholder, no questions |
| `<leader>sn`   | visual | Add the selection under a name, then say what it reads as |
| `<leader>sy`   | visual | Copy the selection **unmasked**, when the key is the point |
| `<leader>sl`   | normal | Open the watchlist as an ordinary buffer                |
| `<leader>sd`   | normal | Pick an entry to remove                                 |
| `<leader>sr`   | normal | Give an existing entry its replacement                  |

Same things as commands: `:ClipshieldAdd`, `:ClipshieldAddDefault` and `:ClipshieldAddNamed`
(with a range), `:ClipshieldSetReplacement`, `:YankRaw` (with a range), `:ClipshieldList`,
`:ClipshieldDelete`.

Editing the list *is* opening the file. It is a normal buffer: change a line, delete one with `dd`,
add one by hand, `:w`. Changes take effect on the next copy.

## From outside Neovim (Hyprland)

`bin/clipshield` drives the same plugin from a shell — a headless `--clean` Neovim runs the
masking and the Watchlist logic, nothing else loads. It reads whatever is piped in; with none —
which is what a keybind gets — the current Wayland selection, then the clipboard:

```sh
printf '%s' "sk-proj-…" | bin/clipshield add -n "openai" -r "my-key"
printf 'key=sk-proj-Ab3xK9zzQq' | bin/clipshield copy | wl-copy   # the masked text, to anywhere
```

Suggested binds for `hyprland.conf` (needs `wl-clipboard`; feedback via `notify-send` when
present) — not applied anywhere by the plugin:

```
bind = SUPER SHIFT, C, exec, /path/to/Clipshield/bin/clipshield copy
bind = SUPER SHIFT, A, exec, /path/to/Clipshield/bin/clipshield add
bind = SUPER SHIFT, L, exec, /path/to/Clipshield/bin/clipshield list
```

`list` opens the Watchlist manager (wofi, rofi, fuzzel or bemenu — the first found;
override with `CLIPSHIELD_PICKER="rofi -dmenu -i"`). The key legend sits at the top of the
menu; every entry reads as `name → replacement` (or `name · numbered`). Pick one to act on it:

- `✎ Edit replacement…` — a zenity dialog, prefilled with the current text; an empty answer
  returns the entry to the numbered default
- `↺ Use the numbered default` — the same, in one press
- `✖ Delete entry`

The list re-opens after each action, Esc closes. Entry values are never printed whole; they
never pass through arguments — everything goes by entry number. The only argv text is the
replacement you just typed, and that is not a secret.

Select a log line with the mouse, press the copy bind, paste anywhere — the keys are not in it.
That is the one way a mouse selection gets masked: the terminal copies from its own screen
buffer, and only a compositor bind can catch it on the way out. The add bind puts the selection
on the Watchlist (`-n` names it, `-r` says what it reads as; both optional).

Exit codes: `0` done, `1` refused (duplicate), `2` no input, `64` bad arguments. The
Watchlist file is shared with the editor; the only gap is a user `setup()` that moves it — a
headless Neovim does not load your config — so point the CLI at it:
`CLIPSHIELD_WATCHLIST=…/watchlist.jsonl clipshield …`.

## The watchlist

One JSON object per line, at `stdpath("data")/clipshield/watchlist.jsonl`. Blank lines and lines
starting with `#` are ignored, so you can leave yourself notes.

```
# work
{"value":"mysite.example","replacement":"site1.internal","label":"work host"}
{"value":"sk-proj-Ab3xK9zzQq"}
```

`replacement` is what the value reads as when copied; leave it out for the numbered default.
`label` is a short name for the entry — what `:ClipshieldDelete` and `<leader>sr` menus show it
by. It is display-only and never lands in copied text.

**This file holds your real keys, in the clear.** That is unavoidable — matching them in copied text
means knowing what they are. Treat it like any other file full of secrets.

Matching is exact and case-sensitive, anywhere in a line — including inside a URL such as
`https://user:PASSWORD@host`. Entries may span several lines, so a whole PEM key works. Where two
entries overlap, the longer one wins, so a short entry can never chop a longer key in half and leak
the remainder. There is no minimum length — but matching is a literal substring anywhere in
the line, so a short value will mask every accidental occurrence of itself.

If a line in the file is not valid, that line is skipped, the rest keep working, and you get a loud
error every time you copy until it is fixed. Silently masking nothing is the one failure this plugin
must never do quietly.

## Configuration

Defaults, all optional:

```lua
require("clipshield").setup({
  watchlist = vim.fs.joinpath(vim.fn.stdpath("data"), "clipshield", "watchlist.jsonl"),
  placeholder = "REDACTED",  -- entries without their own replacement use this plus a number
  keymaps = true,         -- false to bind everything yourself
  prefix = "<leader>s",
})
```

Only the system clipboard (`+`, `*`) is ever rewritten. The unnamed register keeps the true value,
so `yy` and `p` inside Neovim behave exactly as they always have.
