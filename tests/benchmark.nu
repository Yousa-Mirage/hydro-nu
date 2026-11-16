# Run from any directory: nu --no-config-file tests/benchmark.nu
# Synthetic local workload; reports warm medians, not a universal speed claim.
use ../hydro.nu *

def measure [action: closure, samples: int = 7] {
    do $action | ignore
    1..$samples | each { (timeit { do $action | ignore }) / 1ms } | math median
}

def --wrapped git-ok [cwd: path, ...args: string] {
    let result = (^git -C $cwd ...$args | complete)
    if $result.exit_code != 0 { error make {msg: $result.stderr} }
}

def main [--files: int = 5000, --samples: int = 7] {
    if $files < 1 or $samples < 1 { error make {msg: 'files and samples must be positive.'} }
    let parent = ($env.FILE_PWD | path dirname | path join .test-tmp | path expand)
    let root = ($parent | path join (random uuid))
    mkdir $root
    let outcome = (try {
        git-ok $root init --quiet --initial-branch=benchmark
        for i in 1..$files { 'tracked' | save ($root | path join $"tracked-($i).txt") }
        git-ok $root add .
        git-ok $root -c user.name=hydro-test -c user.email=hydro-test@example.invalid -c commit.gpgsign=false commit --quiet -m baseline
        for i in 1..$files { 'untracked' | save ($root | path join $"untracked-($i).txt") }
        let config = (hydro resolve {})
        let no_untracked = (hydro resolve {git: {untracked: false}})
        let no_root = (hydro resolve {path: {keep_repo: false}})
        let ignored = (hydro resolve {git: {ignored_paths: [$root]}})
        let context = {cwd: ($root | path join src nested leaf) status: 0 duration_ms: 1300 git: {root: $root branch: benchmark dirty: true ahead: 2 behind: 1}}
        let plain = (hydro resolve {color: false})
        let render_plain = (measure { for i in 1..300 { hydro render $context $plain | ignore } } $samples) / 300
        let render_color = (do {
            hide-env --ignore-errors NO_COLOR
            (measure { for i in 1..300 { hydro render $context $config | ignore } } $samples) / 300
        })
        let result = {
            nu: (version | get version)
            os: $nu.os-info.name
            tracked_files: $files
            untracked_files: $files
            samples: $samples
            median_ms: {
                render_plain: $render_plain
                render_color: $render_color
                git_default: (measure { hydro git query $root $config } $samples)
                git_without_untracked: (measure { hydro git query $root $no_untracked } $samples)
                git_without_root_discovery: (measure { hydro git query $root $no_root } $samples)
                git_ignored: (measure { hydro git query $root $ignored } $samples)
            }
        }
        {ok: true result: $result}
    } catch {|err| {ok: false error: $err.msg} })
    if (($root | path expand | path dirname) != $parent) { error make {msg: 'Unsafe fixture cleanup path.'} }
    rm --recursive --force $root
    if not $outcome.ok { error make {msg: $outcome.error} }
    $outcome.result | to json
}
