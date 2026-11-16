[windows]
set shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]

check_nu := if os() == "windows" {
    "if (-not (Get-Command nu -CommandType Application -ErrorAction SilentlyContinue)) { Write-Error 'Nushell (nu) is required. Install it and add it to PATH.'; exit 1 }"
} else {
    "command -v nu >/dev/null 2>&1 || { printf '%s\\n' 'Nushell (nu) is required. Install it and add it to PATH.' >&2; exit 1; }"
}

# Run all automated tests (interactive checks and benchmarks are separate).
test:
    @{{check_nu}}
    nu --no-config-file tests/run.nu
    nu --no-config-file tests/install.nu

# Install locally, preserving any existing hydro.toml.
install:
    @{{check_nu}}
    nu --no-config-file install.nu --source-dir .
