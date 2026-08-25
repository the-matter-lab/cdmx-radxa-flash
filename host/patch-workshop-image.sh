#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=host/lib/imager.sh
source "$ROOT/host/lib/imager.sh"

base_image=""
base_sha512=""
base_version=""
image_version=""
while (($#)); do
    case "$1" in
        --base-image) base_image=${2:-}; shift 2 ;;
        --base-sha512) base_sha512=${2:-}; shift 2 ;;
        --base-version) base_version=${2:-}; shift 2 ;;
        --version) image_version=${2:-}; shift 2 ;;
        -h|--help)
            printf 'Usage: %s --base-image PATH --base-sha512 SHA512 --base-version YYYY-MM-DD.N --version YYYY-MM-DD.N\n' "$0"
            exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ -n $base_image && -n $base_sha512 && -n $base_version && -n $image_version ]] ||
    die 'The base image, base SHA-512, base version, and output version are required'
[[ $base_version =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]+$ ]] ||
    die 'Base version must use YYYY-MM-DD.N'
[[ $image_version =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]+$ ]] ||
    die 'Version must use YYYY-MM-DD.N'

need_command docker
need_command git
need_command xz
docker info >/dev/null 2>&1 || die 'Docker Desktop is not running'

mkdir -p "$ROOT/image/cache"
output_raw=$(mktemp "$ROOT/image/cache/cdmx-workshop-patch.XXXXXX.img")
output_xz="$ROOT/image/cdmx-workshop-golden.img.xz"
output_partial="$output_xz.partial"
checksum_partial="$output_xz.sha512.partial"
source_archive="$ROOT/image/cache/cdmx-patch-source.tar"
source_archive_partial="$source_archive.partial"
cleanup() {
    rm -f -- "$output_raw" "$output_partial" "$checksum_partial" \
        "$source_archive" "$source_archive_partial"
}
trap cleanup EXIT

source_commit=$(git -C "$ROOT" rev-parse HEAD)
note "Snapshotting tracked source at $source_commit"
git -C "$ROOT" archive --format=tar HEAD > "$source_archive_partial"
mv -f -- "$source_archive_partial" "$source_archive"

verify_compressed_image "$base_image" "$base_sha512"
note 'Expanding the proven workshop image without ARM emulation'
xz -dc -- "$base_image" > "$output_raw"

note 'Replacing the tracked CDMX runtime inside the image'
docker run --rm --privileged \
    -v "$ROOT:/source:ro" \
    -v "$ROOT/image/cache:/images" \
    -v "$source_archive:/source.tar:ro" \
    ubuntu:24.04 \
    /bin/bash /source/host/patch-image-in-container.sh \
    "/images/$(basename "$output_raw")" /source.tar "$image_version" "$source_commit" "$base_version"

note 'Compressing and checking the patched workshop image'
xz -T0 -1 -c -- "$output_raw" > "$output_partial"
xz -t -- "$output_partial"
checksum=$(sha512_file "$output_partial")
printf '%s  %s\n' "$checksum" "$(basename "$output_xz")" > "$checksum_partial"
mv -f -- "$output_partial" "$output_xz"
mv -f -- "$checksum_partial" "$output_xz.sha512"
note "Patched workshop image ready: $output_xz"
