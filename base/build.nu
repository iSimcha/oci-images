#!/usr/bin/env nu

# Build the debian-base or alpine-base image and emit its name and tag for CI.

const distros = [debian alpine]
const base_dir = path self .

# Image name and tag for a distro, from config.yml.
export def image-ref [distro: string]: nothing -> record {
	if $distro not-in $distros {
		error make {msg: $"Invalid distro '($distro)'. Valid distros: ($distros | str join ', ')"}
	}
	let config = (open ($base_dir | path join config.yml))
	let name = ($config.published | get $distro | get name)
	let tag = ([$config.published.version $distro ($config | get $distro | get version)] | str join '-')
	{name: $name, tag: $tag, ref: $"($name):($tag)"}
}

def main [
	distro: string			# debian or alpine
] {
	use std log

	let image = (image-ref $distro)
	let config = (open ($base_dir | path join config.yml))

	log info $"Building ($image.ref) from target ($distro)"
	(^docker buildx build
		--target $distro
		--build-arg $"DEBIAN_IMAGE=($config.debian.image)"
		--build-arg $"DEBIAN_TAG=($config.debian.tag)"
		--build-arg $"ALPINE_IMAGE=($config.alpine.image)"
		--build-arg $"ALPINE_TAG=($config.alpine.tag)"
		--build-arg $"NU_VERSION=($config.nushell.version)"
		--build-arg $"NU_FILENAME=($config.nushell.filename)"
		--build-arg $"NU_SHA256=($config.nushell.sha256)"
		--tag $image.ref
		--load
		$base_dir)

	log info $"Built ($image.ref)"

	let output = ($env.GITHUB_OUTPUT? | default ($base_dir | path join output.log))
	$"image=($image.name)\n" | save --append $output
	$"tags=($image.tag)\n" | save --append $output
}
