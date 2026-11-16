# <i>H</i>ydro-nu

<p align="center">
    <a href="README.md">中文</a> / <a href="README_en.md">English</a>
</p>

A lightweight prompt for Nushell, inspired by [Hydro](https://github.com/jorgebucaran/hydro).

```text
~/p/hydro-nu main• ↑1 ↓2 1.3s ❱
```

## Installation

Requires Nushell **0.117.0+**. Git is optional; it is only needed for repository status. Run this in Nushell:

```nu
nu --no-config-file -c (http get --raw https://raw.githubusercontent.com/Yousa-Mirage/hydro-nu/main/install.nu) --config-file $nu.config-path
```

The installer places hydro-nu in `~/.config/nushell/hydro/` and adds the startup configuration automatically. Restart Nushell to use it. Running the installer again updates the module while preserving your existing `hydro.toml`.

If another prompt, such as Starship, is enabled, disable its initialization first.

## Features

Show the Git branch, working tree status, and commits ahead of or behind the upstream:

```text
~/p/hydro-nu main ❱
~/p/hydro-nu main• ❱
~/p/hydro-nu main• ↑1 ↓2 ❱
```

`•` means that staged, unstaged, or untracked files are present. `↑` and `↓` show commits ahead of and behind the upstream.

Show command duration when it reaches one second and the exit code after a failure:

```text
~/p/hydro-nu main 1.3s ❱
~/p/hydro-nu main [1] ❱
```

Parent directories are abbreviated while the repository name and current directory are kept in full:

```text
~/projects/hydro-nu/functions/share
~/p/hydro-nu/f/share ❱
```

Two-line layout and Vi mode indicators are supported:

```text
~/p/hydro-nu main
❱

~/p/hydro-nu main N ❱
```

## Configuration

Edit `~/.config/nushell/hydro/hydro.toml`, then run `hydro reload`.
See [hydro.example.toml](hydro.example.toml) for all options.

### Themes and colors

Four themes are included: `hydro`, `rose-pine`, `catppuccin-mocha`, and `mono`. The installer uses `rose-pine`.

```toml
theme = "rose-pine"

[colors]
path = "cyan"
git = "#c4a7e7"
prompt = "green"
error = "red"
```

Colors accept full foreground color names or `#RRGGBB`. Unspecified colors inherit the selected theme. Set `color = false` or the `NO_COLOR` environment variable to disable colors and styles.

```nu
hydro themes                         # list themes
hydro preview --theme mono           # preview a theme
hydro theme catppuccin-mocha         # switch themes for this session
```

### Symbols

Configure these under `[symbols]`:

| Option | Description | Default |
| --- | --- | --- |
| `start` | Prompt prefix | empty |
| `prompt` | Input indicator | `❱` |
| `dirty` | Working tree changes | `•` |
| `ahead` | Ahead of upstream | `↑` |
| `behind` | Behind upstream | `↓` |
| `vi_normal` | Vi normal mode | `N` |
| `continuation` | Continuation indicator | `…` |

### Other options

| Option | Description | Default |
| --- | --- | --- |
| `two_line` | Put the input indicator on the next line | `false` |
| `duration_min_ms` | Minimum duration to display, in milliseconds | `1000` |
| `path.abbreviate` | Abbreviate parent directories | `true` |
| `path.parent_length` | Characters kept in parent directories; `0` hides intermediate directories | `1` |
| `path.keep_last` | Number of trailing directories kept in full | `1` |
| `path.keep_repo` | Keep the repository name in full | `true` |
| `git.untracked` | Include untracked files in the dirty state | `true` |
| `git.ignored_paths` | Repository roots where Git status is hidden | `[]` |

For example, enable two-line mode and ignore a large repository:

```toml
two_line = true

[git]
ignored_paths = ['~/projects/large-repo']
```

Edit the existing TOML sections and run `hydro reload`.

## License

[MIT](LICENSE). The visual style and interaction ideas are inspired by Jorge Bucaran's [Hydro](https://github.com/jorgebucaran/hydro).
