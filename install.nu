# Local checkout: nu --no-config-file install.nu --source-dir .
# Online: nu --no-config-file install.nu [--repo OWNER/REPO] [--ref TAG_OR_COMMIT]
const begin_marker = '# >>> hydro-nu >>>'
const end_marker = '# <<< hydro-nu <<<'

def quote-nu [value: string] { $value | to nuon }

def update-config [text: string, block: string, newline: string] {
    let starts = ($text | split row $begin_marker)
    let ends = ($text | split row $end_marker)
    if ($starts | length) == 1 and ($ends | length) == 1 {
        let separator = if $text == '' or ($text | str ends-with "\n") { '' } else { $newline }
        return ($text + $separator + $block + $newline)
    }
    if ($starts | length) != 2 or ($ends | length) != 2 or not ($starts.1 | str contains $end_marker) {
        error make {msg: 'Malformed or duplicate hydro-nu markers in config.nu; no files were installed.'}
    }
    let lines = ($text | lines)
    if ($lines | where {|line| $line == $begin_marker } | length) != 1 or ($lines | where {|line| $line == $end_marker } | length) != 1 {
        error make {msg: 'Hydro markers must be on their own lines; no files were installed.'}
    }
    $starts.0 + $block + $ends.1
}

# Install or update hydro-nu without overwriting the user's theme preferences.
def main [
    --repo: string             # GitHub repository; default: Yousa-Mirage/hydro-nu
    --ref: string = main       # Branch, tag, or commit for online installation
    --source-dir: path         # Local directory containing hydro.nu and hydro.example.toml
    --install-dir: path        # Default: ~/.config/nushell/hydro
    --config-file: path        # Default: Nushell's actual config.nu path
] {
    let v = (version | get version | split row '.' | first 2 | each { into int })
    if $v.0 == 0 and $v.1 < 117 { error make {msg: 'hydro-nu requires Nushell >= 0.117.0.'} }
    if $repo != null and $source_dir != null { error make {msg: 'Use either --repo or --source-dir.'} }
    let destination = ($install_dir | default ($nu.home-dir | path join .config nushell hydro) | path expand)
    let config_path = ($config_file | default $nu.config-path | path expand)
    let module_path = ($destination | path join hydro.nu)
    let theme_path = ($destination | path join hydro.toml)
    if $config_path in [$module_path $theme_path] { error make {msg: 'config.nu must be separate from the installed files.'} }
    let original = if ($config_path | path exists) { open --raw $config_path } else { '' }
    let newline = if ($original | str contains "\r\n") { "\r\n" } else { "\n" }
    let block = ([$begin_marker $"use (quote-nu $module_path) *" $"hydro enable --config (quote-nu $theme_path)" $end_marker] | str join $newline)
    let updated = (update-config $original $block $newline)
    # Capture existing UTF-8 contents for rollback, preserving newline style.
    let targets = ([$module_path $theme_path $config_path] | each {|path|
        let exists = ($path | path exists)
        if $exists and ($path | path type) != file { error make {msg: $"Expected a regular file: ($path)"} }
        {path: $path existed: $exists bytes: (if $exists { open --raw $path | into binary } else { null })}
    })
    let sources = if $source_dir == null {
        let repository = ($repo | default 'Yousa-Mirage/hydro-nu')
        if not ($repository =~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { error make {msg: 'repo must be OWNER/REPOSITORY.'} }
        # Resolve the ref once so both files come from the same revision.
        let revision = (http get --max-time 30sec $"https://api.github.com/repos/($repository)/commits/($ref | url encode)")
        if not (($revision.sha? | default '') =~ '^[0-9a-fA-F]{40}$') { error make {msg: 'GitHub returned an invalid commit revision.'} }
        let base = $"https://raw.githubusercontent.com/($repository)/($revision.sha)"
        {module: (http get --raw --max-time 30sec $"($base)/hydro.nu") theme: (http get --raw --max-time 30sec $"($base)/hydro.example.toml")}
    } else {
        let source = ($source_dir | path expand)
        {module: (open --raw ($source | path join hydro.nu)) theme: (open --raw ($source | path join hydro.example.toml))}
    }
    let theme = if ($theme_path | path exists) { open --raw $theme_path } else { $sources.theme }
    # Validate the module and the preserved/custom theme before touching the installation.
    let staging = (mktemp --directory)
    mut written = []
    let outcome = (try {
        let candidate = ($staging | path join hydro.nu)
        $sources.module | save $candidate
        $theme | save ($staging | path join hydro.toml)
        let validation = $"use (quote-nu $candidate) *; hydro resolve \(open (quote-nu ($staging | path join hydro.toml))\) | ignore"
        let result = (^$nu.current-exe --no-config-file -c $validation | complete)
        if $result.exit_code != 0 { error make {msg: $"Installation validation failed: ($result.stderr)"} }
        mkdir $destination
        mkdir ($config_path | path dirname)
        if $updated != $original and ($config_path | path exists) {
            let backup = $"($config_path).hydro-(random uuid).bak"
            cp $config_path $backup
            print $"Config backup: ($backup)"
        }
        $written = ($written | append $module_path)
        $sources.module | save --force $module_path
        if not $targets.1.existed {
            $written = ($written | append $theme_path)
            $sources.theme | save $theme_path
        }
        if $updated != $original {
            $written = ($written | append $config_path)
            $updated | save --force $config_path
        }
        {ok: true}
    } catch {|err| {ok: false message: $err.msg} })
    if not $outcome.ok {
        for target in ($targets | where {|item| $item.path in $written }) {
            if $target.existed { $target.bytes | save --force $target.path } else if ($target.path | path exists) { rm --force $target.path }
        }
    }
    # Only remove the unique directory returned by mktemp above.
    if (($staging | path expand | path dirname) != ($nu.temp-dir | path expand)) { error make {msg: 'Unexpected staging directory; refusing cleanup.'} }
    rm --recursive --force $staging
    if not $outcome.ok { error make {msg: $outcome.message} }
    print $"Installed: ($module_path)"
    print $"Theme \(preserved if existing\): ($theme_path)"
    print $"Startup config: ($config_path)"
    print 'Open a new Nushell session to activate hydro-nu.'
}
