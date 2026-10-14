# Debian and Alpine base images carrying the same tool set. Build one with --target debian or --target alpine.
# build.nu passes every ARG below from config.yml.
ARG DEBIAN_IMAGE=docker.io/library/debian
ARG DEBIAN_TAG=13-slim
ARG ALPINE_IMAGE=docker.io/library/alpine
ARG ALPINE_TAG=3.24

# ---- Stage: nushell ----
# Static musl build, so the same files run on both distros. setup.nu needs nu before anything else.
FROM ${ALPINE_IMAGE}:${ALPINE_TAG} AS nushell
ARG NU_VERSION=0.112.2
ARG NU_FILENAME=nu-0.112.2-x86_64-unknown-linux-musl.tar.gz
ARG NU_SHA256
RUN set -eux; \
	test -n "${NU_SHA256}"; \
	apk add --no-cache curl; \
	curl --fail --silent --show-error --location --retry 3 --output "/tmp/${NU_FILENAME}" \
		"https://github.com/nushell/nushell/releases/download/${NU_VERSION}/${NU_FILENAME}"; \
	echo "${NU_SHA256}  /tmp/${NU_FILENAME}" | sha256sum -c -; \
	mkdir /tmp/nu /nu; \
	tar -xzf "/tmp/${NU_FILENAME}" -C /tmp/nu --strip-components 1; \
	install -m 0755 /tmp/nu/nu /tmp/nu/nu_plugin_* /nu/

# ---- Stage: debian ----
FROM ${DEBIAN_IMAGE}:${DEBIAN_TAG} AS debian
COPY --from=nushell /nu/ /usr/local/bin/
# --chmod keeps the files readable when the host checkout is 0600.
COPY --chmod=644 config.yml setup.nu /tmp/build/
RUN nu /tmp/build/setup.nu install-packages --distro debian
RUN nu /tmp/build/setup.nu install-node
RUN nu /tmp/build/setup.nu install-binaries --distro debian
RUN nu /tmp/build/setup.nu install-npm-globals
RUN nu /tmp/build/setup.nu add-user
USER dev
WORKDIR /home/dev

# ---- Stage: alpine ----
FROM ${ALPINE_IMAGE}:${ALPINE_TAG} AS alpine
COPY --from=nushell /nu/ /usr/local/bin/
COPY --chmod=644 config.yml setup.nu /tmp/build/
RUN nu /tmp/build/setup.nu install-packages --distro alpine
RUN nu /tmp/build/setup.nu install-binaries --distro alpine
RUN nu /tmp/build/setup.nu install-npm-globals
RUN nu /tmp/build/setup.nu add-user
USER dev
WORKDIR /home/dev
