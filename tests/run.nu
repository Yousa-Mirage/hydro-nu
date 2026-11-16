use ../hydro.nu *

mut passed = 0

def check [condition: bool, message: string] {
    if not $condition { error make {msg: $message} }
}

def --wrapped git-ok [cwd: path, ...args: string] {
    let result = (^git -C $cwd ...$args | complete)
    if $result.exit_code != 0 { error make {msg: $"git failed: ($args | str join ' '): ($result.stderr)"} }
    $result.stdout | str trim
}

def commit [cwd: path, message: string] {
    git-ok $cwd -c user.name=hydro-test -c user.email=hydro-test@example.invalid commit --quiet -m $message | ignore
}

let config = (hydro resolve {color: false})
let context = {cwd: ($nu.home-dir | path join projects hydro-nu) status: 0 duration_ms: 1300 git: {branch: main dirty: true ahead: 2 behind: 1} pending: false}
let rendered = (hydro render $context $config) + (hydro indicator 0 $config)
check ($rendered == '~/p/hydro-nu main• ↑2 ↓1 1.3s ❱ ') $"Unexpected rendering: ($rendered)"
check ((hydro render ($context | merge {status: 7 git: null duration_ms: 0}) $config) | str contains '[7]') 'Exit code missing'
check ((hydro render $context (hydro resolve {color: false two_line: true})) | str ends-with "\n") 'Two-line mode missing'
check ((hydro indicator 1 $config vi_normal) == 'N ❱ ') 'Vi normal indicator missing'
check ((hydro duration 61000) == '1m1s') 'Long duration formatting'
check ((hydro render ($context | merge {duration_ms: 999}) $config) | str contains '1s' | not $in) 'Duration threshold'
$passed += 6

let home = $nu.home-dir
check ((hydro path $home $config) == '~') 'Home abbreviation'
check ((hydro path ($home | path join .config hydro-nu) $config) == '~/.c/hydro-nu') 'Hidden directory abbreviation'
check ((hydro path ($home | path join projects '中文目录' '带 空格') $config) == '~/p/中/带 空格') 'Unicode or spaced path'
if $nu.os-info.name == windows {
    check ((hydro path 'C:\projects\example' $config) == 'C:/p/example') 'Windows drive root'
    check ((hydro path 'C:\' $config) == 'C:/') 'Windows drive root only'
    check ((hydro path '\\server\share\projects\example' $config) == '//server/share/p/example') 'UNC root'
} else {
    check ((hydro path '/' $config) == '/') 'Unix root'
    check ((hydro path '/projects/.hidden/example' $config) == '/p/.h/example') 'Unix hidden directory'
    check ((hydro path '/projects/back\slash' $config) == '/p/back\slash') 'Unix backslash filename'
}
let unshortened = (hydro resolve {color: false path: {abbreviate: false}})
check ((hydro path ($home | path join projects example) $unshortened) == '~/projects/example') 'Abbreviation toggle'
$passed += 7

# Preserve meaningful repository names and handle Windows case folding by parts.
let repo_path = ($home | path join projects hydro-nu)
check ((hydro path ($repo_path | path join src nested leaf) $config --root $repo_path) == '~/p/hydro-nu/s/n/leaf') 'Repository name was abbreviated'
check ((hydro path ($repo_path | path join src nested leaf) (hydro resolve {color: false path: {keep_repo: false}}) --root $repo_path) == '~/p/h/s/n/leaf') 'keep_repo toggle failed'
check ((hydro path ($repo_path | path join src leaf) (hydro resolve {color: false path: {parent_length: 0}}) --root $repo_path) == '~/hydro-nu/leaf') 'Zero-length parent mode lost repository or leaf'
check ((hydro path ($home | path join projects repo-old src leaf) $config --root ($home | path join projects repo)) == '~/p/r/s/leaf') 'Sibling prefix mistaken for repository ancestor'
check ((hydro path ($repo_path | path join src leaf) $config --root $home) == '~/p/h/s/leaf') 'Home repository handling failed'
if $nu.os-info.name == windows {
    check ((hydro path ($home | str uppercase | path join Projects Repo src leaf) $config --root ($home | path join Projects Repo)) == '~/P/Repo/s/leaf') 'Windows case folding lost home or root'
    $passed += 1
}
let styled_context = ($context | merge {cwd: ($repo_path | path join src leaf) git: {root: $repo_path branch: main dirty: false ahead: 0 behind: 0}})
do {
    hide-env --ignore-errors NO_COLOR
    let styled = (hydro render $styled_context (hydro resolve {}))
    check (($styled | ansi strip) == (hydro render $styled_context $config)) 'Path styling changed visible text'
    check ($styled | str contains (ansi bo)) 'Leaf bold missing'
    check ($styled | str contains (ansi d)) 'Dim separator missing'
    let disabled = (hydro render $styled_context (hydro resolve {path: {bold_leaf: false dim_separators: false}}))
    check (not ($disabled | str contains (ansi bo)) and not ($disabled | str contains (ansi d))) 'Path style toggles ignored'
    let resolved = (hydro resolve {})
    check ((with-env {NO_COLOR: '1'} { hydro render $styled_context $resolved }) == (hydro render $styled_context $config)) 'Cached colors ignored a later NO_COLOR change'
}
$passed += 1
let prefix_config = (hydro resolve {color: false symbols: {start: '╭─ '}})
check ((hydro render $context $prefix_config) | str starts-with '╭─ ~/') 'Start symbol missing'
check ((hydro resolve {colors: {path: ''}}).colors.path == '') 'Neutral color rejected'
check (try { hydro resolve {path: {parent_length: -1}}; false } catch { true }) 'Negative parent length accepted'
check (try { hydro resolve {git: {ignored_paths: 'not-a-list'}}; false } catch { true }) 'Invalid ignored paths type accepted'
check (try { hydro resolve {git: {ignored_paths: [relative/repo]}}; false } catch { true }) 'Relative ignored path accepted'
check (try { hydro resolve {symbols: {start: 12}}; false } catch { true }) 'Non-string symbol accepted'
check ((hydro duration 3600000) == '1h') 'Exact hour formatting failed'
check ((hydro duration 3661200) == '1h1m1.2s') 'Hour minute second formatting failed'
check ((hydro duration 59960) == '1m') 'Second rounding did not carry into minutes'
check ((hydro duration 3599960) == '1h') 'Minute rounding did not carry into hours'
check ((hydro duration 0) == '0s') 'Zero duration formatting failed'
$passed += 20
let porcelain = "# branch.oid 1234567890abcdef\n# branch.head main\n# branch.ab +12 -3\n? 文件.txt\n"
let state = (hydro git parse $porcelain)
check ($state.branch == main and $state.ahead == 12 and $state.behind == 3 and $state.dirty) 'Porcelain parsing'
let detached = (hydro git parse "# branch.oid abcdef123456\n# branch.head (detached)\n")
check ($detached.detached and $detached.branch == abcdef1) 'Detached HEAD parsing'
check ((hydro git parse "# branch.head main\n! ignored.txt\n").dirty == false) 'Ignored files marked dirty'
check ((hydro git parse "# branch.head main\nu conflict\n").dirty) 'Conflict not marked dirty'
$passed += 4

for theme in (hydro themes | get name) {
    let resolved = (hydro resolve {theme: $theme})
    check ($resolved.theme == $theme) 'Theme resolution failed'
    check ((hydro render $context $resolved | ansi strip) == (hydro render $context $config)) 'Colors changed visible layout'
    $passed += 2
}
let custom = (hydro resolve {theme: rose-pine colors: {path: '#123456' prompt: red}})
check ($custom.colors.path == '#123456' and $custom.colors.prompt == red and $custom.colors.git == '#c4a7e7') 'Color overrides lost theme values'
check (try { hydro resolve {colors: {path: '#bad'}}; false } catch { true }) 'Invalid hex accepted'
check (try { hydro resolve {theme: nonexistent}; false } catch { true }) 'Unknown theme accepted'
check (try { hydro resolve {color: 'yes'}; false } catch { true }) 'Invalid boolean accepted'
check (try { hydro resolve {colors: {path: invalid_color_name}}; false } catch { true }) 'Invalid named color accepted'
$passed += 5

for color in [cursor_off cursor_on reset erase_screen red_bold bg_red] {
    check (try { hydro resolve {colors: {path: $color}}; false } catch { true }) $"Non-foreground color accepted: ($color)"
    $passed += 1
}
check ((hydro resolve {colors: {path: default}}).colors.path == default) 'Default foreground rejected'
check ((hydro path . $config) == (hydro path $env.PWD $config)) 'Relative current directory differs'
check ((hydro path .. $config) == (hydro path ($env.PWD | path dirname) $config)) 'Relative parent path differs'
check ((hydro path '~' $config) == '~') 'Tilde expansion differs'
check ((hydro path ($env.PWD | path join src leaf) $config --root '.') == (hydro path ($env.PWD | path join src leaf) $config --root $env.PWD)) 'Relative root differs'
$passed += 5

# End-to-end Git fixtures, isolated from the user's repositories and Git identity.
let fixture_parent = ($env.FILE_PWD | path dirname | path join .test-tmp)
let root = ($fixture_parent | path join (random uuid))
mkdir $root
let repo = ($root | path join '中文 仓库')
mkdir $repo
let outcome = (try {
    with-env {GIT_CEILING_DIRECTORIES: $fixture_parent} {
        check ((hydro git query $root $config) == null) 'Non-repository must be silent'
    }
    check ((hydro git query ($root | path join missing) $config) == null) 'Failed parallel queries must be silent'
    with-env {PATH: []} {
        check ((hydro git query $repo $config) == null) 'Missing Git broke parallel query'
        check ((hydro git query $repo (hydro resolve {path: {keep_repo: false}})) == null) 'Missing Git broke status-only query'
        check ((hydro git query $repo (hydro resolve {git: {ignored_paths: [$repo]}})) == null) 'Missing Git broke sequential query'
    }
    git-ok $repo init --quiet --initial-branch=main | ignore
    let unborn = (hydro git query $repo $config)
    check ($unborn.branch == main and not $unborn.dirty) 'Unborn branch failed'
    'first' | save ($repo | path join 'tracked.txt')
    check ((hydro git query $repo $config).dirty) 'Untracked file missed'
    check (not (hydro git query $repo (hydro resolve {git: {untracked: false}})).dirty) 'Untracked toggle failed'
    git-ok $repo add tracked.txt | ignore
    commit $repo initial
    check (not (hydro git query $repo $config).dirty) 'Clean repository marked dirty'
    'second' | save --force ($repo | path join 'tracked.txt')
    check ((hydro git query $repo $config).dirty) 'Modified file missed'
    git-ok $repo add tracked.txt | ignore
    check ((hydro git query $repo $config).dirty) 'Staged file missed'
    commit $repo update
    git-ok $repo tag v0-test | ignore
    git-ok $repo checkout --quiet --detach HEAD | ignore
    check ((hydro git query $repo $config).branch == v0-test) 'Detached tag failed'
    let short = (git-ok $repo rev-parse --short=7 HEAD)
    check ((hydro git query $repo (hydro resolve {git: {detached_tag: false}})).branch == $short) 'Detached short SHA failed'
    git-ok $repo switch --quiet main | ignore
    git-ok $repo branch upstream HEAD~1 | ignore
    git-ok $repo branch --set-upstream-to=upstream main | ignore
    check ((hydro git query $repo $config).ahead == 1) 'Ahead count failed'
    mkdir ($repo | path join 子目录)
    check ((hydro git query ($repo | path join 子目录) $config).branch == main) 'Subdirectory query failed'
    # Ignored repositories are checked before the costly status traversal.
    let ignored_config = (hydro resolve {git: {ignored_paths: [$repo]}})
    let trace_path = ($root | path join git-trace.log)
    let ignored_result = (with-env {GIT_TRACE: $trace_path} { hydro git query $repo $ignored_config })
    check ($ignored_result == null) 'Ignored repository still displayed'
    let trace = (open --raw $trace_path)
    check (not ($trace | str contains ' status ')) 'Ignored repository still scanned status'
    check ((hydro git query ($repo | path join 子目录) $ignored_config) == null) 'Ignored repository subdirectory still displayed'
    if $nu.os-info.name == windows {
        let variant = (($repo | str uppercase | str replace --all '\' '/') + '/')
        check ((hydro git query $repo (hydro resolve {git: {ignored_paths: [$variant]}})) == null) 'Ignored path case/separator normalization failed'
    }
    let sibling = ($repo + '-other')
    check ((hydro git query $repo (hydro resolve {git: {ignored_paths: [$sibling]}})) != null) 'Ignored sibling hid unrelated repository'
    check (((hydro git query $repo $config).root | path expand) == ($repo | path expand)) 'Repository root discovery failed'
    let single_call_trace = ($root | path join git-single-call.log)
    let single_call = (with-env {GIT_TRACE: $single_call_trace} { hydro git query $repo (hydro resolve {path: {keep_repo: false}}) })
    check ($single_call.branch == main and $single_call.root == '') 'Optional root discovery changed Git state'
    check (not (open --raw $single_call_trace | str contains ' rev-parse ')) 'Disabled root features still queried repository root'
    # Worktrees have a .git file rather than a directory.
    let worktree = ($root | path join 'work tree')
    git-ok $repo worktree add --quiet --detach $worktree HEAD | ignore
    check (((hydro git query $worktree $config).root | path expand) == ($worktree | path expand)) 'Worktree root discovery failed'
    # Diverged local branches exercise real ahead AND behind counts, without a remote.
    git-ok $repo switch --quiet upstream | ignore
    'side' | save ($repo | path join side.txt)
    git-ok $repo add side.txt | ignore
    commit $repo side
    git-ok $repo switch --quiet main | ignore
    let diverged = (hydro git query $repo $config)
    check ($diverged.ahead == 1 and $diverged.behind == 1) 'Diverged ahead/behind counts failed'
    let nested = ($repo | path join nested)
    mkdir $nested
    git-ok $nested init --quiet --initial-branch=nested | ignore
    check ((hydro git query $nested $ignored_config).branch == nested) 'Exact ignored root incorrectly hid a nested repository'
    {ok: true}
} catch {|err| {ok: false error: $err} })
# Delete only the unique fixture created above, after checking its resolved parent.
if (($root | path expand | path dirname) != ($fixture_parent | path expand)) {
    error make {msg: 'Refusing fixture cleanup outside .test-tmp.'}
}
rm --recursive --force $root
if not $outcome.ok { error make {msg: $outcome.error.rendered} }
$passed += (11 + 14 + (if $nu.os-info.name == windows { 1 } else { 0 }))

# Lifecycle: preserve unrelated hooks and prompt values, including repeated enable.
$env.PROMPT_COMMAND = {|| 'existing prompt' }
let original_prompt = $env.PROMPT_COMMAND
let original_hooks = $env.config.hooks.pre_prompt
$env.config.hooks.pre_prompt = ($original_hooks | append {|| null})
let original_count = ($env.config.hooks.pre_prompt | length)
$env.HYDRO_NU_CONFIG = {git: {enabled: false} color: false}
hydro enable
hydro enable
check (($env.config.hooks.pre_prompt | length) == ($original_count + 1)) 'Enable duplicated hooks'
$env.LAST_EXIT_CODE = 7
$env.CMD_DURATION_MS = '1300'
hydro refresh
check ($env.HYDRO_NU_STATUS == 7 and $env.LAST_EXIT_CODE == 7) 'Exit status changed'
check ($env.HYDRO_NU_FRAME | str contains '1.3s') 'Duration snapshot lost'
hydro theme rose-pine
check ($env.HYDRO_NU_EFFECTIVE.theme == rose-pine) 'Theme switching failed'
do {
    hide-env --ignore-errors NO_COLOR
    $env.HYDRO_NU_CONFIG = ($env.HYDRO_NU_CONFIG | upsert color true)
    hydro theme hydro
    let previous_indicator = $env.PROMPT_MULTILINE_INDICATOR
    hydro theme rose-pine
    check ($env.PROMPT_MULTILINE_INDICATOR != $previous_indicator) 'Continuation indicator kept previous theme color'
}
$passed += 1
let before_invalid = $env.HYDRO_NU_EFFECTIVE
try { hydro theme nonexistent } catch { null }
check ($env.HYDRO_NU_EFFECTIVE == $before_invalid) 'Invalid theme changed working configuration'
# A cancelled job must not deliver a late result; stale mailbox generations
# must not become the cache used by the next prompt.
$env.HYDRO_NU_JOB = (job spawn --auto-kill { sleep 250ms; 'obsolete' | job send 0 --tag 73402 })
hydro stop
sleep 300ms
let late = (try { job recv --tag 73402 --timeout 0sec } catch { null })
check ($late == null) 'Cancelled job delivered a late result'
check ($env.HYDRO_NU_JOB == null) 'Cancelled job ID was not cleared'
$env.HYDRO_NU_CACHE = null
{generation: ($env.HYDRO_NU_GENERATION - 1) cwd: $env.PWD git: {branch: stale}} | job send 0 --tag 73401
hydro refresh
check ($env.HYDRO_NU_CACHE == null) 'Stale generation became the cache'
{generation: $env.HYDRO_NU_GENERATION cwd: $env.PWD git: {branch: fresh}} | job send 0 --tag 73401
hydro refresh
check ($env.HYDRO_NU_CACHE.git.branch == fresh) 'Current generation was not collected'
$passed += 4
hydro disable
check (($env.config.hooks.pre_prompt | length) == $original_count) 'Disable damaged unrelated hooks'
check ((view source $env.PROMPT_COMMAND) == (view source $original_prompt)) 'Original prompt not restored'
$env.config.hooks.pre_prompt = $original_hooks
$passed += 7

# File and memory sources must not silently replace one another on reload.
hydro enable --config ($env.FILE_PWD | path join .. hydro.example.toml)
let file_path = $env.HYDRO_NU_CONFIG_PATH
hydro theme mono
hydro reload
check ($env.HYDRO_NU_EFFECTIVE.theme == rose-pine and $env.HYDRO_NU_CONFIG_PATH == $file_path) 'File reload lost its source'
hydro disable
$env.HYDRO_NU_CONFIG = {theme: mono color: false git: {enabled: false}}
hydro enable
check ($env.HYDRO_NU_CONFIG_PATH == null) 'Memory enable retained old file source'
check (try { hydro reload; false } catch { true }) 'Memory reload silently loaded an old file'
check ($env.HYDRO_NU_EFFECTIVE.theme == mono and not $env.HYDRO_NU_EFFECTIVE.color) 'Rejected reload changed active settings'
try { hydro enable --config ($env.FILE_PWD | path join missing.toml) } catch { null }
check ($env.HYDRO_NU_CONFIG_PATH == null and $env.HYDRO_NU_EFFECTIVE.theme == mono) 'Failed enable changed active source'
hydro disable
$passed += 5
print $"PASS: ($passed) checks"
