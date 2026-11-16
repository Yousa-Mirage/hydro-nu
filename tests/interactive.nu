use ../hydro.nu *
$env.config.show_banner = false
hydro enable --config ($env.FILE_PWD | path join .. hydro.example.toml)