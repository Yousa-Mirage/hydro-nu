# Hydro-inspired native Nushell prompt. Requires Nushell >= 0.117.0.
# Background jobs repaint through commandline set-prompt; no daemon or temp cache.

const mailbox_tag = 73401
const prompt_keys = [PROMPT_COMMAND PROMPT_COMMAND_RIGHT PROMPT_INDICATOR PROMPT_INDICATOR_VI_INSERT PROMPT_INDICATOR_VI_NORMAL PROMPT_MULTILINE_INDICATOR]
# Foreground colors only: `ansi` also accepts terminal controls such as cursor_off.
const foreground_colors = [black dark_gray red light_red green light_green yellow light_yellow blue light_blue magenta light_magenta cyan light_cyan white light_gray default]

export def "hydro themes" [] {
    [
        {name: hydro colors: {path: cyan git: magenta clean: cyan dirty: yellow pending: dark_gray duration: yellow error: red prompt: green vi: green start: cyan}}
        {name: rose-pine colors: {path: '#9ccfd8' git: '#c4a7e7' clean: '#31748f' dirty: '#f6c177' pending: '#6e6a86' duration: '#f6c177' error: '#eb6f92' prompt: '#9ccfd8' vi: '#ebbcba' start: '#9ccfd8'}}
        {name: catppuccin-mocha colors: {path: '#89dceb' git: '#cba6f7' clean: '#a6e3a1' dirty: '#f9e2af' pending: '#6c7086' duration: '#fab387' error: '#f38ba8' prompt: '#a6e3a1' vi: '#f5c2e7' start: '#89dceb'}}
        {name: mono colors: {path: white git: white clean: white dirty: white pending: dark_gray duration: white error: white prompt: white vi: white start: white}}
    ]
}

# Resolve a theme first, then apply individual color overrides.
export def "hydro resolve" [options: record = {}] {
    let defaults = {
        theme: hydro
        color: true
        two_line: false
        duration_min_ms: 1000
        path: {abbreviate: true keep_last: 1 parent_length: 1 home: '~' keep_repo: true bold_leaf: true dim_separators: true}
        git: {enabled: true untracked: true detached_tag: true ignored_paths: []}
        symbols: {start: '' prompt: '❱' dirty: '•' ahead: '↑' behind: '↓' pending: '' vi_insert: '' vi_normal: 'N' continuation: '…'}
    }
    let config = ($defaults | merge deep $options)
    let theme = (hydro themes | where name == $config.theme)
    if ($theme | is-empty) {
        error make {msg: $"Unknown hydro-nu theme: ($config.theme). Run `hydro themes`."}
    }
    let colors = ($theme.0.colors | merge ($options.colors? | default {}))
    for flag in [$config.color $config.two_line $config.path.abbreviate $config.path.keep_repo $config.path.bold_leaf $config.path.dim_separators $config.git.enabled $config.git.untracked $config.git.detached_tag] {
        if ($flag | describe) != bool { error make {msg: 'color, two_line, path styling and Git switches must be booleans.'} }
    }
    if ($config.path.keep_last | describe) != int or ($config.path.parent_length | describe) != int {
        error make {msg: 'keep_last and parent_length must be integers.'}
    }
    if ($config.duration_min_ms | describe) not-in [int float] {
        error make {msg: 'duration_min_ms must be a number.'}
    }
    if $config.path.keep_last < 1 or $config.path.parent_length < 0 or $config.duration_min_ms < 0 {
        error make {msg: 'keep_last must be >= 1; parent_length and duration_min_ms must be >= 0.'}
    }
    for entry in ($colors | transpose key value) {
        if ($entry.value | describe) != string {
            error make {msg: $"Color '($entry.key)' must be an ANSI color name or a #RRGGBB string."}
        }
        if $entry.value == '' { continue }
        if ($entry.value | str starts-with '#') {
            if not ($entry.value =~ '^#[0-9a-fA-F]{6}$') {
                error make {msg: $"Invalid hex color for '($entry.key)': ($entry.value)"}
            }
            ansi {fg: $entry.value} | ignore
        } else {
            if $entry.value not-in $foreground_colors {
                error make {msg: $"Invalid foreground color for '($entry.key)': ($entry.value). Use a full color name or #RRGGBB."}
            }
            ansi {fg: $entry.value} | ignore
        }
    }
    if not (($config.git.ignored_paths | describe) | str starts-with 'list<') {
        error make {msg: 'git.ignored_paths must be a list of absolute repository paths.'}
    }
    let ignored = ($config.git.ignored_paths | each {|entry|
        if ($entry | describe) != string {
            error make {msg: 'Every ignored repository path must be a string.'}
        }
        if not ($entry =~ '^(~([/\\]|$)|[/\\]|[A-Za-z]:[/\\])') {
            error make {msg: $"Ignored repository path must be absolute or start with ~: ($entry)"}
        }
        $entry | path expand --no-symlink
    })
    for entry in ($config.symbols | transpose key value) {
        if ($entry.value | describe) != string {
            error make {msg: $"Symbol '($entry.key)' must be a string."}
        }
    }
    if ($config.path.home | describe) != string {
        error make {msg: 'path.home must be a string.'}
    }
    $config | upsert colors $colors | upsert git.ignored_paths $ignored
        | upsert _home_keys (path-key $nu.home-dir)
        | upsert _ansi ($colors | transpose key value | reduce --fold {} {|entry, acc|
            $acc | insert $entry.key (if $entry.value == '' { '' } else { ansi {fg: $entry.value} })
        })
        | upsert _style {bold: (ansi bo) dim: (ansi d) reset: (ansi reset)}
}

def paint [text: string, role: string, config: record, --bold, --dim] {
    if $text == '' or not $config.color or ($env.NO_COLOR? != null) { return $text }
    let start = ($config._ansi | get $role)
    let style = if $bold { $config._style.bold } else if $dim { $config._style.dim } else { '' }
    $"($start)($style)($text)($config._style.reset)"
}

# Compare complete components; never treat "repo-old" as a child of "repo".
# Preserve original spelling for display and case-fold only on Windows.
def path-key [path: string] {
    let parts = ($path | path expand --no-symlink | path split)
    fold-path $parts
}

def fold-path [parts: list<string>] {
    if $nu.os-info.name == windows { $parts | str lowercase } else { $parts }
}

# One snapshot per prompt cycle, shared by the initial and completed Git frames.
def prepare-path [cwd: string, config: record] {
    let parts = ($cwd | path expand --no-symlink | path split)
    let keys = (fold-path $parts)
    let home_keys = $config._home_keys
    let is_home = (($keys | take ($home_keys | length)) == $home_keys)
    let display_parts = if $is_home {
        [$config.path.home] | append ($parts | skip ($home_keys | length))
    } else { $parts }
    {keys: $keys parts: $display_parts home_offset: (if $is_home { ($home_keys | length) - 1 } else { 0 })}
}

# Keep drive/UNC anchors, Git root and the requested number of trailing dirs.
export def "hydro path" [cwd: string, config: record, --root: string = ''] {
    format-path (prepare-path $cwd $config) $root $config
}

def format-path [info: record, root: string, config: record] {
    let root_keys = if $root == '' { [] } else { path-key $root }
    let root_index = if $config.path.keep_repo and ($root_keys | is-not-empty) and (($info.keys | take ($root_keys | length)) == $root_keys) {
        ($root_keys | length) - 1 - $info.home_offset
    } else { -1 }
    let count = ($info.parts | length)
    let display = ($info.parts | enumerate | each {|item|
        if (not $config.path.abbreviate) or $item.index == 0 or $item.index == $root_index or $item.index >= ($count - $config.path.keep_last) {
            $item.item
        } else if $config.path.parent_length == 0 {
            null
        } else {
            let length = if ($item.item | str starts-with '.') { $config.path.parent_length + 1 } else { $config.path.parent_length }
            $item.item | str substring --grapheme-clusters 0..<$length
        }
    } | compact | path join)
    # Backslashes are valid filename characters on Unix, not separators.
    if $nu.os-info.name == windows { $display | str replace --all '\' '/' } else { $display }
}

def render-path [info: record, root: string, config: record] {
    let display = (format-path $info $root $config)
    if not $config.color or ($env.NO_COLOR? != null) { return $display }
    let parts = ($display | split row '/')
    let nonempty = ($parts | enumerate | where item != '')
    let leaf = if ($nonempty | is-empty) { -1 } else { $nonempty | last | get index }
    let separator = (paint '/' path $config --dim=$config.path.dim_separators)
    $parts | enumerate | each {|part|
        paint $part.item path $config --bold=($config.path.bold_leaf and $part.index == $leaf)
    } | str join $separator
}

# Parse stable machine-readable porcelain output, including unborn/detached HEAD.
export def "hydro git parse" [text: string] {
    mut branch = ''
    mut oid = ''
    mut ahead = 0
    mut behind = 0
    mut dirty = false
    for line in ($text | lines) {
        if ($line | str starts-with '# branch.head ') {
            $branch = ($line | str replace '# branch.head ' '')
        } else if ($line | str starts-with '# branch.oid ') {
            $oid = ($line | str replace '# branch.oid ' '')
        } else if ($line | str starts-with '# branch.ab ') {
            let counts = ($line | parse '# branch.ab +{ahead} -{behind}')
            if ($counts | is-not-empty) {
                $ahead = ($counts.0.ahead | into int)
                $behind = ($counts.0.behind | into int)
            }
        } else if $line =~ '^(1 |2 |u |\? )' {
            $dirty = true
            # Git emits headers before file entries; the first change is enough.
            break
        }
    }
    let detached = ($branch == '(detached)')
    if $detached { $branch = ($oid | str substring 0..<7) }
    {branch: $branch detached: $detached dirty: $dirty ahead: $ahead behind: $behind}
}

# Keep failures as records: parallel collection must not drop failed commands.
def git-query [cwd: string, args: list<string>] {
    try { ^git --no-optional-locks -C $cwd ...$args | complete } catch {
        {exit_code: -1 stdout: '' stderr: ''}
    }
}

export def "hydro git query" [cwd: string, config: record] {
    if not $config.git.enabled { return null }
    mut root = ''
    let untracked = if $config.git.untracked { '--untracked-files=normal' } else { '--untracked-files=no' }
    let status_args = [status --porcelain=v2 --branch --no-renames $untracked]
    let discovery_args = [rev-parse --show-toplevel]
    let has_ignored = ($config.git.ignored_paths | is-not-empty)
    # With exclusions, discover first so ignored repositories never scan status.
    # Otherwise independent queries can overlap their process startup and I/O.
    let result = if $has_ignored {
        let discovery = (git-query $cwd $discovery_args)
        if $discovery.exit_code != 0 { return null }
        $root = ($discovery.stdout | str replace --regex '[\r\n]+$' '')
        let key = (path-key $root)
        if ($config.git.ignored_paths | any {|entry| (path-key $entry) == $key }) { return null }
        git-query $cwd $status_args
    } else if $config.path.keep_repo {
        let results = ([$discovery_args $status_args] | par-each --threads 2 --keep-order {|args| git-query $cwd $args })
        if $results.0.exit_code != 0 { return null }
        $root = ($results.0.stdout | str replace --regex '[\r\n]+$' '')
        $results.1
    } else {
        git-query $cwd $status_args
    }
    if $result.exit_code != 0 { return null }
    mut state = (hydro git parse $result.stdout | insert root $root)
    if $state.detached and $config.git.detached_tag {
        let tag = (try { ^git -C $cwd describe --tags --exact-match | complete } catch { null })
        if $tag != null and $tag.exit_code == 0 {
            $state.branch = ($tag.stdout | str trim)
        }
    }
    $state
}

export def "hydro duration" [milliseconds: number] {
    if $milliseconds <= 0 { return '0s' }
    # Round once before splitting units so 59.96s becomes 1m, not 60s.
    let ticks = ($milliseconds / 100 | math round | into int)
    let hours = ($ticks / 36000 | math floor | into int)
    let minutes = (($ticks mod 36000) / 600 | math floor | into int)
    let second_ticks = ($ticks mod 600)
    let seconds = if ($second_ticks mod 10) == 0 { $second_ticks / 10 | into int } else { $second_ticks / 10 }
    mut segments = []
    if $hours > 0 { $segments = ($segments | append $"($hours)h") }
    if $minutes > 0 { $segments = ($segments | append $"($minutes)m") }
    if $seconds > 0 or ($segments | is-empty) { $segments = ($segments | append $"($seconds)s") }
    $segments | str join ''
}

# Pure renderer: context is a snapshot taken before starting background work.
export def "hydro render" [context: record, config: record] {
    let root = if $config.git.enabled { $context.git?.root? | default '' } else { '' }
    render-frame $context $config (render-path (prepare-path $context.cwd $config) $root $config)
}

def render-frame [context: record, config: record, path_text: string] {
    mut segments = [$path_text]
    let git = ($context.git? | default null)
    let pending = ($context.pending? | default false)
    if $config.git.enabled and $git != null {
        let branch_role = if $pending { 'pending' } else { 'git' }
        mut segment = (paint $git.branch $branch_role $config)
        if $git.dirty { $segment = $segment + (paint $config.symbols.dirty dirty $config) }
        if $git.ahead > 0 { $segment = $segment + ' ' + (paint $"($config.symbols.ahead)($git.ahead)" clean $config) }
        if $git.behind > 0 { $segment = $segment + ' ' + (paint $"($config.symbols.behind)($git.behind)" dirty $config) }
        if $pending and ($config.symbols.pending | is-not-empty) {
            $segment = $segment + (paint $config.symbols.pending pending $config)
        }
        $segments = ($segments | append $segment)
    }
    if $context.duration_ms >= $config.duration_min_ms {
        $segments = ($segments | append (paint (hydro duration $context.duration_ms) duration $config))
    }
    if $context.status != 0 {
        $segments = ($segments | append (paint $"[($context.status)]" error $config))
    }
    let separator = if $config.two_line { "\n" } else { ' ' }
    (paint $config.symbols.start start $config) + ($segments | str join ' ') + $separator
}

export def "hydro indicator" [status: int, config: record, mode: string = emacs] {
    let role = if $status == 0 { 'prompt' } else { 'error' }
    let prefix = match $mode {
        vi_normal => $config.symbols.vi_normal
        vi_insert => $config.symbols.vi_insert
        _ => ''
    }
    let marker = (paint $config.symbols.prompt $role $config)
    if ($prefix | is-empty) { return ($marker + ' ') }
    let mode_role = if $status == 0 { 'vi' } else { 'error' }
    (paint $prefix $mode_role $config) + ' ' + $marker + ' '
}

# Cancel before executing commands too: a slow old result must never overwrite
# the prompt while the next command runs, or on the following command line.
export def --env "hydro stop" [] {
    let id = ($env.HYDRO_NU_JOB? | default null)
    if $id != null { try { job kill $id } }
    $env.HYDRO_NU_JOB = null
}

def --env collect-results [] {
    loop {
        let message = (try { job recv --tag $mailbox_tag --timeout 0sec } catch { null })
        if $message == null { break }
        if $message.generation == ($env.HYDRO_NU_GENERATION? | default 0) {
            $env.HYDRO_NU_CACHE = {cwd: $message.cwd git: $message.git}
        }
    }
}

export def --env "hydro refresh" [] {
    if not ($env.HYDRO_NU_ENABLED? | default false) { return }
    let status = ($env.LAST_EXIT_CODE? | default 0 | into int)
    let raw_duration = ($env.CMD_DURATION_MS? | default '0')
    let duration = if ($env.HYDRO_NU_FIRST? | default true) { 0 } else { try { $raw_duration | into float } catch { 0 } }
    $env.HYDRO_NU_FIRST = false
    hydro stop
    collect-results
    let cwd = $env.PWD
    let config = $env.HYDRO_NU_EFFECTIVE
    let cache = ($env.HYDRO_NU_CACHE? | default null)
    let cached_git = if $cache != null and $cache.cwd == $cwd { $cache.git } else { null }
    let context = {cwd: $cwd status: $status duration_ms: $duration git: $cached_git pending: true}
    let path_info = (prepare-path $cwd $config)
    let cached_root = if $config.git.enabled { $cached_git.root? | default '' } else { '' }
    let path_text = (render-path $path_info $cached_root $config)
    $env.HYDRO_NU_STATUS = $status
    $env.HYDRO_NU_FRAME = (render-frame $context $config $path_text)
    $env.HYDRO_NU_GENERATION = (($env.HYDRO_NU_GENERATION? | default 0) + 1)
    let generation = $env.HYDRO_NU_GENERATION
    if $config.git.enabled {
        $env.HYDRO_NU_JOB = (job spawn --auto-kill --description hydro-nu {
            let git = (hydro git query $cwd $config)
            let result = ($context | merge {git: $git pending: false})
            {cwd: $cwd git: $git generation: $generation} | job send 0 --tag $mailbox_tag
            let root = ($git.root? | default '')
            let completed_path = if $root == $cached_root { $path_text } else { render-path $path_info $root $config }
            render-frame $result $config $completed_path | commandline set-prompt
        })
    }
    $env.LAST_EXIT_CODE = $status
    $env.CMD_DURATION_MS = $raw_duration
}

# Safe to call repeatedly: hooks are installed once and other hooks survive.
export def --env "hydro enable" [--config: path] {
    let options = if $config != null {
        open $config
    } else { $env.HYDRO_NU_CONFIG? | default {} }
    let effective = (hydro resolve $options)
    if not ($env.HYDRO_NU_ENABLED? | default false) {
        $env.HYDRO_NU_ORIGINAL = ($env | select --optional ...$prompt_keys)
    }
    hydro stop
    $env.HYDRO_NU_CONFIG = $options
    $env.HYDRO_NU_EFFECTIVE = $effective
    $env.HYDRO_NU_CACHE = null
    $env.HYDRO_NU_GENERATION = (($env.HYDRO_NU_GENERATION? | default 0) + 1)
    $env.HYDRO_NU_CONFIG_PATH = if $config != null { $config | path expand } else { null }
    $env.HYDRO_NU_ENABLED = true
    $env.HYDRO_NU_FIRST = true
    $env.HYDRO_NU_STATUS = 0
    $env.PROMPT_COMMAND = {|| $env.HYDRO_NU_FRAME? | default '' }
    $env.PROMPT_COMMAND_RIGHT = {|| '' }
    $env.PROMPT_INDICATOR = {|| hydro indicator $env.HYDRO_NU_STATUS $env.HYDRO_NU_EFFECTIVE }
    $env.PROMPT_INDICATOR_VI_INSERT = {|| hydro indicator $env.HYDRO_NU_STATUS $env.HYDRO_NU_EFFECTIVE vi_insert }
    $env.PROMPT_INDICATOR_VI_NORMAL = {|| hydro indicator $env.HYDRO_NU_STATUS $env.HYDRO_NU_EFFECTIVE vi_normal }
    $env.PROMPT_MULTILINE_INDICATOR = ((paint $effective.symbols.continuation pending $effective) + ' ')
    let hooks = ($env.config.hooks.pre_prompt? | default [])
    if not ('hydro refresh' in $hooks) {
        $env.config.hooks.pre_prompt = ($hooks | append 'hydro refresh')
    }
    let execution_hooks = ($env.config.hooks.pre_execution? | default [])
    if not ('hydro stop' in $execution_hooks) {
        $env.config.hooks.pre_execution = ($execution_hooks | append 'hydro stop')
    }
    hydro refresh
}

export def --env "hydro disable" [] {
    if not ($env.HYDRO_NU_ENABLED? | default false) { return }
    hydro stop
    $env.HYDRO_NU_ENABLED = false
    $env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt | where {|hook| $hook != 'hydro refresh' })
    $env.config.hooks.pre_execution = ($env.config.hooks.pre_execution | where {|hook| $hook != 'hydro stop' })
    let saved = $env.HYDRO_NU_ORIGINAL
    for key in $prompt_keys {
        if $key in $saved { load-env {$key: ($saved | get $key)} } else { hide-env --ignore-errors $key }
    }
}

# Session-only theme change; edit hydro.toml to make a preference persistent.
export def --env "hydro theme" [name: string] {
    let options = (($env.HYDRO_NU_CONFIG? | default {}) | upsert theme $name)
    let effective = (hydro resolve $options)
    $env.HYDRO_NU_CONFIG = $options
    $env.HYDRO_NU_EFFECTIVE = $effective
    if ($env.HYDRO_NU_ENABLED? | default false) {
        $env.PROMPT_MULTILINE_INDICATOR = ((paint $effective.symbols.continuation pending $effective) + ' ')
        hydro refresh
    }
}

export def --env "hydro reload" [] {
    if $env.HYDRO_NU_CONFIG_PATH? == null {
        error make {msg: 'No hydro.toml loaded. Use `hydro enable --config <path>` first.'}
    }
    hydro enable --config $env.HYDRO_NU_CONFIG_PATH
}

export def "hydro preview" [--theme: string] {
    let options = ($env.HYDRO_NU_CONFIG? | default {})
    let config = (hydro resolve (if $theme == null { $options } else { $options | upsert theme $theme }))
    let example = {cwd: ($nu.home-dir | path join projects hydro-nu) status: 0 duration_ms: 1300 git: {branch: main dirty: true ahead: 2 behind: 1} pending: false}
    print ((hydro render $example $config) + (hydro indicator 0 $config))
    print ((hydro render ($example | merge {status: 1 duration_ms: 0 git: null}) $config) + (hydro indicator 1 $config))
}
