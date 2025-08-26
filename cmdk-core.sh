#!/usr/bin/env bash

# This is the core of cmdk, written in Bash.
# The entrypoint cmdk.sh and cmdk.fish call down to this
#
# Rationale: I didn't want to rewrite the entire thing to be zsh-
# and fish-compatible :S

set -euo pipefail
script_dirpath="$(cd "$(dirname "${0}")" && pwd)"

output_paths=()

# Initialize toggle state based on -e flag
if echo "$*" | grep -q '\-e'; then
    bash "${script_dirpath}/toggle-state.sh" init on >/dev/null
else
    bash "${script_dirpath}/toggle-state.sh" init off >/dev/null
fi

# Use a temporary file instead of process substitution for better shell compatibility
temp_output_file="$(mktemp)"
# EXPLANATION:
# -m allows multiple selections
# --ansi tells fzf to parse the ANSI color codes that we're generating with fd
# --scheme=path optimizes for path-based input
# --with-nth allows us to use the custom sorting mechanism
# --bind='ctrl-i:...' adds Ctrl+I to toggle .env visibility
set +u  # Temporarily disable unbound variable check for $*
FZF_DEFAULT_COMMAND="bash ${script_dirpath}/reload-with-toggle.sh $*" fzf \
    -m \
    --ansi \
    --bind='change:top' \
    --bind="ctrl-t:reload(bash ${script_dirpath}/toggle-state.sh toggle >/dev/null && bash ${script_dirpath}/reload-with-toggle.sh $*)" \
    --scheme=path \
    --preview="bash ${script_dirpath}/preview.sh {}" > "${temp_output_file}"
set -u  # Re-enable unbound variable check

# Cleanup toggle state
bash "${script_dirpath}/toggle-state.sh" cleanup >/dev/null 2>&1 || true

exit_code=$?
if [ "$exit_code" -ne 0 ]; then
    rm -f "${temp_output_file}"
    return
fi

while IFS="" read -r line; do  # IFS="" -> no splitting (we may have paths with spaces)
    output_paths+=("${line}")
done < "${temp_output_file}"

rm -f "${temp_output_file}"

dirs=()
text_files=()
open_targets=()
if [ "${#output_paths[@]}" -gt 0 ]; then
for output in "${output_paths[@]}"; do
    case "${output}" in
        HOME)
            dirs+=("${HOME}")
            ;;
        *.key)   # Mac's keynote presentation files are 'application/zip' MIME type, so we have to identify by extension
            open_targets+=("${output}")
            ;;
        *)
            case $(file -b --mime-type "${output}") in
                text/*)
                    text_files+=("${output}")
                    ;;
                application/json)
                    text_files+=("${output}")
                    ;;
                inode/directory)
                    dirs+=("${output}")
                    ;;
                application/pdf)
                    open_targets+=("${output}")
                    ;;
                application/vnd.openxmlformats-officedocument.wordprocessingml.document)
                    open_targets+=("${output}")
                    ;;
                image/*)
                    open_targets+=("${output}")
                    ;;
            esac
            ;;
    esac
done
fi

# We can open open_targets here (no need to pass them to the parent)
if [ "${#open_targets[@]}" -gt 0 ]; then
    for open_target_filepath in "${open_targets[@]}"; do
        open "${open_target_filepath}"
    done
fi

# However, text files & dirs need to be passed to the parent, so they
# get run in the user's shell process (and not this subprocess)

text_files_filepath=""
if [ "${#text_files[@]}" -gt 0 ]; then
    text_files_filepath="$(mktemp)"
    printf "%s\n" "${text_files[@]}" > "${text_files_filepath}"
fi

num_dirs="${#dirs[@]}"

dir_to_cd=""
if [ "${num_dirs}" -eq 1 ]; then
    dir_to_cd="${dirs[0]}"
elif [ "${num_dirs}" -gt 1 ]; then
    echo "Error: Cannot cd to more than one directory at a time" >&2
    exit 1
fi

# We put the tmp filepath first because we know it doesn't have a pipe
# This allows us to split on comma (because the dir to cd might have a pipe)
echo "${text_files_filepath}|${dir_to_cd}"
