#!/usr/bin/env bash
set -Eeuo pipefail

WORKSPACE=${CDMX_WORKSPACE:-/home/cdmx/workspace}

update_repo() {
    local name=$1 url=$2 target=$WORKSPACE/$1

    if [[ -d $target/.git ]]; then
        printf '\n==> Updating %s\n' "$name"
        git -C "$target" remote set-url origin "$url"
        git -C "$target" pull --ff-only
    elif [[ -e $target ]]; then
        printf '\nERROR: %s already exists but is not a Git repository.\n' "$target" >&2
        printf 'It was left untouched. Rename it, then run this launcher again.\n' >&2
        return 1
    else
        printf '\n==> Downloading %s\n' "$name"
        git clone "$url" "$target"
    fi
}

selection=${1:-all}
case "$(basename "$0")" in
    cdmx-get-bayesopt) selection=bayesopt ;;
    cdmx-get-local-ai) selection=local-ai ;;
esac

mkdir -p "$WORKSPACE"
case "$selection" in
    all)
        update_repo cdmx-bayesopt https://github.com/the-matter-lab/cdmx-bayesopt.git
        update_repo cdmx-local-ai https://github.com/the-matter-lab/cdmx-local-ai.git
        ;;
    bayesopt)
        update_repo cdmx-bayesopt https://github.com/the-matter-lab/cdmx-bayesopt.git
        ;;
    local-ai)
        update_repo cdmx-local-ai https://github.com/the-matter-lab/cdmx-local-ai.git
        ;;
    *)
        printf 'Usage: %s [all|bayesopt|local-ai]\n' "$(basename "$0")" >&2
        exit 64
        ;;
esac

printf '\nReady. Open the code at:\n  ~/workspace\n'
find "$WORKSPACE" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sed "s|^$WORKSPACE/|  ~/workspace/|"
