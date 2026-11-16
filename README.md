# hydro-nu

> 为 Nushell 编写的轻量提示符，受 [Hydro](https://github.com/jorgebucaran/hydro) 启发。Git 状态异步刷新，无需 Nerd Font。

```text
~/p/hydro-nu main• ↑1 ↓2 1.3s ❱
```

## 安装

需要 Nushell **0.117.0+**；显示仓库状态需要 Git。在 Nushell 中执行：

```nu
nu --no-config-file -c (http get --raw https://raw.githubusercontent.com/Yousa-Mirage/hydro-nu/main/install.nu) --config-file $nu.config-path
```

安装到 `~/.config/nushell/hydro/`，自动配置启动加载。重新打开终端即可使用。
重复运行可更新，已有的 `hydro.toml` 会保留。

如果正在使用其他提示符（如 Starship），请先停用其初始化配置。

## 功能

显示 Git 分支、工作区状态，以及相对上游领先或落后的提交数：

```text
~/p/hydro-nu main ❱
~/p/hydro-nu main• ❱
~/p/hydro-nu main• ↑1 ↓2 ❱
```

`•` 表示存在暂存、未暂存或未跟踪的文件；`↑` 和 `↓` 分别表示领先和落后的提交数。

命令耗时达到一秒时显示耗时，失败时显示退出码：

```text
~/p/hydro-nu main 1.3s ❱
~/p/hydro-nu main [1] ❱
```

缩写父目录，保留仓库名和当前目录的完整名称：

```text
~/projects/hydro-nu/functions/share
~/p/hydro-nu/f/share ❱
```

支持两行布局和 Vi 模式标识：

```text
~/p/hydro-nu main
❱

~/p/hydro-nu main N ❱
```

## 配置

编辑 `~/.config/nushell/hydro/hydro.toml`，然后执行 `hydro reload`。
完整选项见 [hydro.example.toml](hydro.example.toml)。

### 主题与颜色

内置 `hydro`、`rose-pine`、`catppuccin-mocha` 和 `mono` 四种主题。安装配置使用 `rose-pine`。

```toml
theme = "rose-pine"

[colors]
path = "cyan"
git = "#c4a7e7"
prompt = "green"
error = "red"
```

颜色支持完整前景色名称或 `#RRGGBB`；未指定的颜色沿用主题。设置 `color = false` 或环境变量 `NO_COLOR` 可关闭颜色和样式。

```nu
hydro themes                      # 查看主题
hydro preview --theme mono        # 预览主题
hydro theme catppuccin-mocha       # 当前会话切换主题
```

### 符号

在 `[symbols]` 中修改：

| 选项 | 用途 | 默认值 |
| --- | --- | --- |
| `start` | 提示符前缀 | 空 |
| `prompt` | 输入标识 | `❱` |
| `dirty` | 工作区有改动 | `•` |
| `ahead` | 领先上游 | `↑` |
| `behind` | 落后上游 | `↓` |
| `vi_normal` | Vi 普通模式 | `N` |
| `continuation` | 续行标识 | `…` |

### 其他选项

| 选项 | 用途 | 默认值 |
| --- | --- | --- |
| `two_line` | 将输入标识放在下一行 | `false` |
| `duration_min_ms` | 显示耗时的阈值，单位毫秒 | `1000` |
| `path.abbreviate` | 缩写父目录 | `true` |
| `path.parent_length` | 父目录保留字符数，`0` 隐藏中间目录 | `1` |
| `path.keep_last` | 末尾保留完整名称的目录层数 | `1` |
| `path.keep_repo` | 保留完整仓库名 | `true` |
| `git.untracked` | 将未跟踪文件计入改动 | `true` |
| `git.ignored_paths` | 不显示 Git 状态的仓库根目录 | `[]` |

例如，使用两行布局并忽略一个大型仓库：

```toml
two_line = true

[git]
ignored_paths = ['~/projects/large-repo']
```

将选项修改到已有的对应 TOML 节中，然后执行 `hydro reload`。

## 许可证

[MIT](LICENSE)。外观与交互理念源自 Jorge Bucaran 的 [Hydro](https://github.com/jorgebucaran/hydro)。
