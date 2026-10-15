#!/usr/bin/env nu

# Run every tool's version check inside a built debian-base or alpine-base image.
# Exits non-zero naming each tool that fails.

use build.nu image-ref

const base_dir = path self .

# Runs inside the container as the image's default user. Reads the check list as JSON on stdin.
const in_container = '
# PASS shows the first output line (the version); FAIL shows all of it, so the cause is in the report.
def result [command: string, r: record] {
	let text = ([$r.stdout $r.stderr] | str join "\n" | str trim | lines | where {|l| $l | is-not-empty })
	if $r.exit_code == 0 {
		{command: $command, status: "PASS", output: ($text | first 1 | str join "")}
	} else {
		{command: $command, status: "FAIL", output: $"exit ($r.exit_code): ($text | str join (char newline))"}
	}
}
let checks = ($in | from json)
let results = ($checks | each {|c|
	# A command that cannot be started at all (missing, or its loader is absent) raises instead of exiting.
	let r = (try { run-external $c.command ...$c.args | complete } catch {|e| {exit_code: 127, stdout: "", stderr: ($e.rendered | ansi strip)} })
	result $c.command $r
})
let user = (^id -un | str trim)
let sudo = (^sudo -n true | complete)
let plugins = (glob /usr/local/bin/nu_plugin_* | each {|p|
	let registry = (mktemp --tmpdir plugins-XXXXXX.msgpackz)
	rm $registry
	result ($p | path basename) (^nu --no-config-file -c $"plugin add --plugin-config ($registry) ($p)" | complete)
})
$results
| append $plugins
| append {command: "user is dev", status: (if $user == "dev" { "PASS" } else { "FAIL" }), output: $user}
| append {command: "sudo -n true", status: (if $sudo.exit_code == 0 { "PASS" } else { "FAIL" }), output: ($sudo.stderr | str trim)}
| to json
'

def main [
	distro: string			# debian or alpine
] {
	let image = (image-ref $distro)
	let config = (open ($base_dir | path join config.yml))

	let binary_checks = ($config.binaries | each {|e|
		let override = ($e | get --optional $distro | default {})
		let entry = ($e | merge $override)
		$entry.commands | each {|cmd| {command: $cmd, args: ($entry.args? | default [--version])} }
	} | flatten)
	let checks = (
		[{command: nu, args: [--version]}]
		| append ($config.os_commands | each {|c| {command: $c.command, args: ($c.args? | default [--version])} })
		| append ($config.npm | each {|p| $p.commands | each {|cmd| {command: $cmd, args: [--version]} } } | flatten)
		| append $binary_checks
	)

	print $"Testing ($image.ref): ($checks | length) commands plus nu plugins, user and sudo"
	let run = ($checks | to json | ^docker run --rm --interactive --entrypoint nu $image.ref --no-config-file --stdin --commands $in_container | complete)
	if $run.exit_code != 0 {
		error make {msg: $"docker run failed with exit code ($run.exit_code): ($run.stderr)"}
	}
	let results = ($run.stdout | from json)
	print ($results | table --expand)

	let failed = ($results | where status == FAIL)
	print $"($image.ref): ($results | where status == PASS | length) passed, ($failed | length) failed"
	if ($failed | is-not-empty) {
		error make {msg: $"($image.ref) failed: ($failed | get command | str join ', ')"}
	}
}
