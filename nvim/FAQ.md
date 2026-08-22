# Neovim FAQ

Situational "how do I actually do this well?" answers for this LazyVim config.
Answers are specific to what is actually installed here — see `lua/plugins/`
and `lazyvim.json`.

**Conventions:** `<leader>` is `<space>`. `<localleader>` is `\`.
Entries are grouped by situation, newest questions get folded into an existing
group when one fits.

## Index

- [Jumping between `/` search hits](#when-i-want-to-jump-between-search-hits)
- [Replacing the thing I just searched for](#when-i-want-to-replace-the-thing-i-just-searched-for)
- [Replacing without searching first](#when-i-want-to-replace-without-searching-first)
- [Controlling case sensitivity](#when-i-need-to-control-case-sensitivity)

---

## Movement & navigation

### When I want to jump between search hits

`n` = next hit, `N` = previous hit. The `[2/3]` counter follows along — it is
tied to the search itself, not to how you moved.

**Why it works here:** LazyVim rebinds `n`/`N` so `n` always moves *forward in
the file* even when you started the search backwards with `?`, and appends `zv`
so folds around the hit open automatically.

`<Esc>` in normal mode clears the search highlight (LazyVim maps it to `noh`).

**Related:** `*` searches for the word under the cursor as a whole word
(`\<word\>`) and jumps to the next one. `#` does the same backwards.

## Search & replace

### When I want to replace the thing I just searched for

Leave the pattern empty — Vim reuses the last search:

```vim
:%s//win-agent-pool/g
```

**Why it works:** an empty pattern in `:s` means "the last search pattern".
This is the payoff for searching first: you *verify* with `/` that you are
matching exactly what you think, then substitute without retyping it.

**Flags:**

| Flag | Effect |
| ---- | ------ |
| `g`  | every hit on the line, not just the first |
| `c`  | confirm each hit — `y` / `n` / `a` = all / `q` = quit |
| `n`  | count matches, change nothing (`:%s///gn`) |

`inccommand=nosplit` is set, so the replacement previews live as you type.

### When I want to replace without searching first

```vim
:%s/AzureBuildPool/win-agent-pool/g
```

`%` is the range = whole file. Other useful ranges: nothing = current line,
`.,+5` = next 5 lines, `'<,'>` = visual selection (typed for you if you press
`:` in visual mode).

**Across multiple files:** `<leader>sr` opens grug-far, prefilled with a filter
for the current file's extension.

### When I need to control case sensitivity

This config has `ignorecase` *and* `smartcase` on (LazyVim defaults), which
means for **searching** with `/`:

- pattern is all lowercase → **case-insensitive**
  (`/azurebuildpool` finds `AzureBuildPool`)
- pattern contains any uppercase → **case-sensitive**
  (`/AzureBuildPool` does not find `azurebuildpool`)

Force it per-pattern, from anywhere inside the pattern:

- `\c` → force case-**insensitive**
- `\C` → force case-**sensitive**

⚠️ **Gotcha:** `smartcase` does **not** apply to `:s` — only `ignorecase` does.
So `:%s/azurebuildpool/x/g` *will* replace `AzureBuildPool`. When a substitute
has to be exact, say so explicitly:

```vim
:%s/\CAzureBuildPool/win-agent-pool/g
```

## Editing & text objects

_(nothing yet)_

## Files, buffers & windows

_(nothing yet)_

## LSP & code actions

_(nothing yet)_

## Git

_(nothing yet)_

## Terminal & external tools

_(nothing yet)_

---

## Drill list

Things asked more than once, or that need muscle memory rather than knowledge.
Practice these; retire them once automatic.

- `/pattern` → `n`/`N` to survey the hits → `:%s//replacement/g` to act on them.
  The search-then-empty-pattern pairing is the whole point; drill it as one
  motion, not two facts.

## Config changes made because of a question

Answers that ended in a config edit, so the drift is traceable.

_(nothing yet)_
