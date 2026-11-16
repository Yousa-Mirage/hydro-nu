# All installation targets are isolated under one unique .test-tmp directory.
const project = (path self | path dirname | path dirname)
const installer = ($project | path join install.nu)

def check [condition: bool, message: string] {
    if not $condition { error make {msg: $message} }
}

def backups [config: path] {
    ls ($config | path dirname) | where {|file| $file.name | str ends-with '.bak' } | get name
}

def invoke [destination: path, config: path, --source: path = $project, --inline] {
    let args = [--source-dir $source --install-dir $destination --config-file $config]
    if $inline {
        open --raw $installer | ^$nu.current-exe --no-config-file -c $in ...$args | complete
    } else {
        ^$nu.current-exe --no-config-file $installer ...$args | complete
    }
}

let parent = ($project | path join .test-tmp | path expand)
let root = ($parent | path join (random uuid))
mkdir $root
let outcome = (try {
    let destination = ($root | path join "中文 space ' dollar$" hydro)
    let config = ($root | path join custom config.nu)
    mkdir ($config | path dirname)
    let original = "# existing user config\r\n$env.INSTALL_TEST = 'kept'"
    $original | save $config
    let result = (invoke $destination $config)
    check ($result.exit_code == 0) $result.stderr
    check ((open --raw ($destination | path join hydro.nu)) == (open --raw ($project | path join hydro.nu))) 'Module content differs'
    check ((open --raw $config) | str starts-with $original) 'Existing config text changed'
    check ((backups $config | length) == 1) 'Backup missing'
    check ((open --raw (backups $config | first)) == $original) 'Backup content changed'
    let first_config = (open --raw $config)
    check (not ($first_config | str replace --all "\r\n" '' | str contains "\n")) 'Newline style not preserved'
    # Execute the installed startup block to prove quoting and actual enable work.
    let probe = $"source ($config | to nuon); print $env.INSTALL_TEST; print $env.HYDRO_NU_ENABLED; hydro disable"
    let load = (^$nu.current-exe --no-config-file -c $probe | complete)
    check ($load.exit_code == 0 and ($load.stdout | str contains 'kept') and ($load.stdout | str contains 'true')) $"Startup failed: ($load.stderr)"
    let theme_path = ($destination | path join hydro.toml)
    let custom_theme = 'theme = "mono"'
    $custom_theme | save --force $theme_path
    '# old module' | save --force ($destination | path join hydro.nu)
    let repeat = (invoke $destination $config --inline)
    check ($repeat.exit_code == 0) $repeat.stderr
    check ((open --raw $theme_path) == $custom_theme) 'Custom theme overwritten'
    check ((open --raw $config) == $first_config) 'Repeated install changed config'
    check ((backups $config | length) == 1) 'No-op install created another backup'
    check ((open --raw ($destination | path join hydro.nu)) == (open --raw ($project | path join hydro.nu))) 'Module was not updated'
    let moved = ($root | path join moved hydro)
    let migration = (invoke $moved $config)
    check ($migration.exit_code == 0) $migration.stderr
    check ((open --raw $config | lines | where {|line| $line == '# >>> hydro-nu >>>' } | length) == 1) 'Managed block duplicated'
    check ((open --raw $config) | str contains ($moved | path join hydro.nu | to nuon)) 'Managed block did not move'
    # Bad source or user preferences must fail before replacing installed files.
    let before = (open --raw $config)
    'theme = "does-not-exist"' | save --force $theme_path
    let invalid = (invoke $destination $config)
    check ($invalid.exit_code != 0) 'Invalid existing theme accepted'
    check ((open --raw $config) == $before) 'Failed validation changed startup config'
    let broken = ($root | path join broken)
    mkdir $broken
    'invalid syntax {{{' | save ($broken | path join hydro.nu)
    $custom_theme | save ($broken | path join hydro.example.toml)
    let broken_target = ($root | path join not-installed)
    let bad = (invoke $broken_target ($root | path join fresh.nu) --source $broken)
    check ($bad.exit_code != 0 and not ($broken_target | path exists)) 'Bad module left an installation'
    let malformed = ($root | path join malformed.nu)
    '# >>> hydro-nu >>>' | save $malformed
    let bad_markers = (invoke $broken_target $malformed)
    check ($bad_markers.exit_code != 0 and not ($broken_target | path exists)) 'Malformed markers changed files'
    let fresh_config = ($root | path join new config.nu)
    let fresh = (invoke ($root | path join fresh hydro) $fresh_config)
    check ($fresh.exit_code == 0 and ($fresh_config | path exists)) 'Fresh config creation failed'
    # Exercise the online branch without publishing or accessing the network.
    # The mock accepts only commit-pinned asset URLs, so a moving-ref fetch fails.
    let sha = ('a' | fill --width 40 --character a)
    let mock = ([
        'def "http get" [--raw, --max-time: duration, url: string] {'
        $'if $url == "https://api.github.com/repos/fixture/hydro-nu/commits/main" { return {sha: "($sha)"} }'
        ('if $url == "https://raw.githubusercontent.com/fixture/hydro-nu/' + $sha + '/hydro.nu" { return (open --raw ' + ($project | path join hydro.nu | to nuon) + ') }')
        ('if $url == "https://raw.githubusercontent.com/fixture/hydro-nu/' + $sha + '/hydro.example.toml" { return (open --raw ' + ($project | path join hydro.example.toml | to nuon) + ') }')
        'error make {msg: $"Unexpected download URL: ($url)"}'
        '}'
    ] | str join "\n")
    let online = (^$nu.current-exe --no-config-file -c ($mock + "\n" + (open --raw $installer)) --repo fixture/hydro-nu --install-dir ($root | path join online hydro) --config-file ($root | path join online config.nu) | complete)
    check ($online.exit_code == 0) $online.stderr
    check ((open --raw ($root | path join online hydro hydro.nu)) == (open --raw ($project | path join hydro.nu))) 'Online assets differ'
    let failed_download = (^$nu.current-exe --no-config-file -c ($mock + "\n" + (open --raw $installer)) --repo fixture/missing --install-dir ($root | path join download-failure) --config-file ($root | path join failure.nu) | complete)
    check ($failed_download.exit_code != 0 and not ($root | path join download-failure | path exists) and not ($root | path join failure.nu | path exists)) 'Download failure changed target files'
    # Force a late config write failure after updating the module and creating TOML.
    let rollback_dir = ($root | path join rollback hydro)
    mkdir $rollback_dir
    let rollback_config = ($root | path join rollback config.nu)
    '# original config' | save $rollback_config
    '# original module' | save ($rollback_dir | path join hydro.nu)
    let failure = ([
        'alias real-save = save'
        'def save [path: path, --force] {'
        'let data = $in'
        ('if $path == ' + ($rollback_config | to nuon) + ' and ($data | describe) == string and $data != "# original config" { "partial write" | real-save --force $path; error make {msg: "Injected write failure"} }')
        'if $force { $data | real-save --force $path } else { $data | real-save $path }'
        '}'
    ] | str join "\n")
    let rolled_back = (^$nu.current-exe --no-config-file -c ($failure + "\n" + (open --raw $installer)) --source-dir $project --install-dir $rollback_dir --config-file $rollback_config | complete)
    check ($rolled_back.exit_code != 0) 'Injected write failure did not fail'
    check ((open --raw ($rollback_dir | path join hydro.nu)) == '# original module') 'Failed install did not restore old module'
    check ((open --raw $rollback_config) == '# original config') 'Failed install did not restore config'
    check (not ($rollback_dir | path join hydro.toml | path exists)) 'Failed install left a newly created theme'
    {ok: true}
} catch {|err| {ok: false message: $err.rendered} })
if (($root | path expand | path dirname) != $parent) { error make {msg: 'Unsafe cleanup path.'} }
rm --recursive --force $root
if not $outcome.ok { error make {msg: $outcome.message} }
print 'PASS: installer lifecycle, inline bootstrap, quoting, preservation, validation, markers, pinned downloads, and rollback'
