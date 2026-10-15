#!/usr/bin/env nu

# Runs INSIDE the image during docker build. Subcommands are called from Dockerfile RUN steps.

const config_path = '/tmp/build/config.yml'
const bin_path = '/usr/local/bin'
const container_user = 'dev'

# Retry a closure with linear backoff; `http get` has no retry of its own.
def retry [
	label: string			# What is being attempted, named in the log line
	action: closure
	--attempts: int = 3		# Total tries before giving up
] {
	mut attempt = 1
	loop {
		let outcome = (try { {ok: true, value: (do $action)} } catch {|err| {ok: false, msg: $err.msg}})
		if $outcome.ok {
			return $outcome.value
		}
		if $attempt >= $attempts {
			error make {msg: $"($label) failed after ($attempts) attempts: ($outcome.msg)"}
		}
		print --stderr $"  ($label) failed \(attempt ($attempt)/($attempts)), retrying: ($outcome.msg)"
		sleep (2sec * $attempt)
		$attempt += 1
	}
}

# Download a URL into a file and fail the build unless its sha256 matches.
def fetch-verified [url: string, sha256: string, dest: string] {
	if ($sha256 | is-empty) {
		error make {msg: $"No sha256 pinned for ($url)"}
	}
	let payload = (retry $"download ($url)" { http get --raw --max-time 5min $url })
	$payload | save $dest
	let actual = (open --raw $dest | hash sha256)
	if $actual != $sha256 {
		error make {msg: $"sha256 mismatch for ($url): expected ($sha256), got ($actual)"}
	}
}

# Apply the distro override, if any, to a binary entry.
def resolve-entry [entry: record, distro: string]: nothing -> record {
	let override = ($entry | get --optional $distro | default {})
	$entry | reject --optional debian alpine | merge $override
}

# Install the OS packages listed for the distro.
def "main install-packages" [
	--distro: string		# debian or alpine
] {
	let config = (open $config_path)
	# Binaries whose distro override names a package install here instead of from the release asset.
	let binary_packages = (
		$config.binaries | each {|e| resolve-entry $e $distro } | where {|e| ($e.package? | is-not-empty) } | get package
	)
	let packages = ($config.packages | get $distro | append $binary_packages)
	print $"Installing ($distro) packages: ($packages | str join ' ')"
	match $distro {
		debian => {
			with-env {DEBIAN_FRONTEND: noninteractive} {
				^apt-get update
				^apt-get install --yes --no-install-recommends ...$packages
				^apt-get clean
			}
			rm --recursive ...(glob /var/lib/apt/lists/*)
		}
		alpine => {
			^apk add --no-cache ...$packages
		}
		_ => { error make {msg: $"Unknown distro '($distro)', expected debian or alpine"} }
	}
}

# Install Node.js from nodejs.org into /usr/local (Debian only; Alpine uses its nodejs package).
def "main install-node" [] {
	let node = (open $config_path | get node)
	let tmp = (mktemp --directory)
	let archive = ($tmp | path join $node.filename)
	fetch-verified $"https://nodejs.org/dist/($node.version)/($node.filename)" $node.sha256 $archive
	^tar --extract --file $archive --directory /usr/local --strip-components 1 --no-same-owner --exclude '*/CHANGELOG.md' --exclude '*/LICENSE' --exclude '*/README.md'
	rm --recursive $tmp
	print $"Installed Node.js (^node --version)"
}

# Download, verify and install every single-file binary for the distro.
def "main install-binaries" [
	--distro: string		# debian or alpine
] {
	let entries = (open $config_path | get binaries | each {|e| resolve-entry $e $distro })
	for e in ($entries | where {|e| ($e.package? | is-not-empty) }) {
		print $"  ($e.commands | str join ', '): installed from the ($distro) package '($e.package)' by install-packages"
	}

	$entries | where {|e| ($e.package? | is-empty) } | par-each --threads 4 {|e|
		let url = ($e.url? | default $"https://github.com/($e.repo)/releases/download/($e.version)/($e.filename)")
		let tmp = (mktemp --directory)
		let download = ($tmp | path join $e.filename)
		fetch-verified $url $e.sha256 $download

		if ($e.raw? | default false) {
			^install --mode 0755 $download ($bin_path | path join $e.commands.0)
		} else {
			let unpacked = ($tmp | path join 'unpacked')
			mkdir $unpacked
			if ($e.filename | str ends-with '.zip') {
				^unzip -q $download -d $unpacked
			} else {
				^tar --extract --file $download --directory $unpacked --no-same-owner
			}
			for command in $e.commands {
				let found = (glob --no-dir ($unpacked | path join '**' $command))
				if ($found | length) != 1 {
					error make {msg: $"Expected one '($command)' in ($e.filename), found ($found | length): ($found)"}
				}
				^install --mode 0755 $found.0 ($bin_path | path join $command)
			}
		}
		rm --recursive $tmp
		{commands: ($e.commands | str join ', '), version: $e.version, asset: $e.filename}
	} | sort-by commands | print
}

# Install the npm globals at their pinned versions.
def "main install-npm-globals" [] {
	let specs = (open $config_path | get npm | each {|p| $"($p.package)@($p.version)" })
	let cache = (mktemp --directory)
	print $"Installing npm globals: ($specs | str join ' ')"
	with-env {npm_config_cache: $cache, npm_config_fund: 'false', npm_config_update_notifier: 'false'} {
		^npm install --global ...$specs
	}
	rm --recursive $cache
}

# Create the dev user with passwordless sudo.
def "main add-user" [] {
	^useradd --groups users --shell /bin/bash --create-home $container_user
	$"($container_user) ALL=\(ALL) NOPASSWD:ALL\n" | save $"/etc/sudoers.d/50-($container_user)"
	^chmod 0440 $"/etc/sudoers.d/50-($container_user)"
	"/usr/local/bin/nu\n" | save --append /etc/shells
	print $"Created user ($container_user)"
}

def main [] {
	print "Usage: setup.nu <subcommand>"
	print "  install-packages --distro <debian|alpine>  - OS packages"
	print "  install-node                               - Node.js from nodejs.org (Debian)"
	print "  install-binaries --distro <debian|alpine>  - Verified single-file binaries"
	print "  install-npm-globals                        - Pinned npm globals"
	print "  add-user                                   - dev user with passwordless sudo"
}
