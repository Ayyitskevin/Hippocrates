#!/bin/sh
set -eu
umask 077

LC_ALL=C
export LC_ALL

usage() {
    cat >&2 <<'USAGE'
Usage:
  Scripts/rxcalc-review-packet.sh --write
  Scripts/rxcalc-review-packet.sh --verify
  Scripts/rxcalc-review-packet.sh --commit <full-lowercase-object-id> --output <path>

--write   Regenerate the tracked worktree manifest after intentional bundle edits.
--verify  Fail unless the tracked manifest exactly matches the current worktree.
--commit  Generate a candidate manifest entirely from Git blobs at one full commit.
USAGE
    exit 64
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo_root=$(git -C "$script_dir/.." rev-parse --show-toplevel 2>/dev/null) ||
    die "RXcalc review packet must run inside a Git checkout"
relative_allowlist="docs/clinical-review/rxcalc-r1-v1/bundle-files.txt"
relative_script="Scripts/rxcalc-review-packet.sh"
rxcalc_directory="Hippocrates/Features/RXCalc"
review_packet_directory="docs/clinical-review/rxcalc-r1-v1"
relative_tracked_manifest="$review_packet_directory/bundle.sha256"
tracked_manifest="$repo_root/$relative_tracked_manifest"
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/rxcalc-review.XXXXXX") ||
    die "unable to create temporary directory"
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

hash_file() {
    file=$1
    if command -v sha256sum >/dev/null 2>&1; then
        digest=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        digest=$(shasum -a 256 "$file" | awk '{print $1}')
    elif command -v openssl >/dev/null 2>&1; then
        digest=$(openssl dgst -sha256 "$file" | awk '{print $NF}')
    else
        die "sha256sum, shasum, or openssl is required"
    fi
    printf '%s\n' "$digest" | grep -Eq '^[0-9a-f]{64}$' ||
        die "SHA-256 tool returned a malformed digest"
    printf '%s\n' "$digest"
}

file_size() {
    wc -c < "$1" | tr -d '[:space:]'
}

validate_allowlist() {
    list=$1
    [ -f "$list" ] && [ ! -L "$list" ] ||
        die "bundle allowlist is missing or is a symbolic link: $list"

    [ -s "$list" ] || die "bundle allowlist is empty"
    last_byte=$(tail -c 1 "$list" | od -An -tu1 | tr -d '[:space:]')
    [ "$last_byte" = "10" ] ||
        die "bundle allowlist must end with a line feed"

    tab=$(printf '\t')
    carriage_return=$(printf '\r')
    paths="$temp_dir/allowlist-paths"
    sorted_paths="$temp_dir/allowlist-paths.sorted"
    duplicates="$temp_dir/allowlist-paths.duplicates"
    : > "$paths"
    line_number=0
    while IFS= read -r line; do
        line_number=$((line_number + 1))
        case "$line" in
            *"$tab"*)
                class=${line%%"$tab"*}
                path=${line#*"$tab"}
                ;;
            *)
                die "allowlist line $line_number must contain exactly class<TAB>path"
                ;;
        esac
        case "$path" in
            *"$tab"*)
                die "allowlist line $line_number must contain exactly class<TAB>path"
                ;;
        esac
        [ -n "$class" ] && [ -n "$path" ] ||
            die "allowlist line $line_number must contain exactly class<TAB>path"
        [ "$class" = "immutable" ] ||
            die "allowlist line $line_number has unknown class: $class"
        case "$path" in
            /*|../*|*/../*|*/..|./*|*/./*|*/.|*//*|*/|*"$carriage_return"*)
                die "allowlist line $line_number has an unsafe path"
                ;;
        esac
        printf '%s\n' "$path" | grep -Eq '^[A-Za-z0-9._/-]+$' ||
            die "allowlist line $line_number contains unsupported path characters"
        printf '%s\n' "$path" >> "$paths"
    done < "$list"

    [ "$line_number" -gt 0 ] || die "bundle allowlist is empty"
    sort "$paths" > "$sorted_paths"
    cmp -s "$paths" "$sorted_paths" ||
        die "bundle allowlist paths must be bytewise sorted"
    sort "$paths" | uniq -d > "$duplicates"
    [ ! -s "$duplicates" ] ||
        die "bundle allowlist contains duplicate paths"

    if grep -Fqx "$relative_tracked_manifest" "$paths"; then
        die "bundle allowlist must exclude its recursive tracked manifest"
    fi

    for required_packet_path in \
        "$review_packet_directory/activation-boundary.json" \
        "$review_packet_directory/bundle-files.txt" \
        "$review_packet_directory/claims-and-policy-matrix.md" \
        "$review_packet_directory/golden-vectors.json" \
        "$review_packet_directory/packet-schema.json" \
        "$review_packet_directory/reviewer-checklist.md" \
        "$review_packet_directory/reviewer-packet.md" \
        "$review_packet_directory/source-provenance.json"
    do
        grep -Fqx "$required_packet_path" "$paths" ||
            die "bundle allowlist is missing required packet path: $required_packet_path"
    done
}

expected_rxcalc_paths() {
    list=$1
    tab=$(printf '\t')
    while IFS="$tab" read -r class path extra; do
        case "$path" in
            "$rxcalc_directory"/*)
                printf '%s\n' "$path"
                ;;
        esac
    done < "$list"
}

expected_review_packet_paths() {
    list=$1
    tab=$(printf '\t')
    while IFS="$tab" read -r class path extra; do
        case "$path" in
            "$review_packet_directory"/*)
                printf '%s\n' "$path"
                ;;
        esac
    done < "$list"
    printf '%s\n' "$relative_tracked_manifest"
}

validate_worktree_rxcalc_directory() {
    list=$1
    expected="$temp_dir/expected-rxcalc-paths"
    actual="$temp_dir/actual-rxcalc-paths"
    expected_rxcalc_paths "$list" | sort > "$expected"
    : > "$actual"

    for file in "$repo_root/$rxcalc_directory"/* "$repo_root/$rxcalc_directory"/.[!.]* "$repo_root/$rxcalc_directory"/..?*; do
        if [ ! -e "$file" ] && [ ! -L "$file" ]; then
            continue
        fi
        [ -f "$file" ] && [ ! -L "$file" ] ||
            die "RXcalc directory contains a non-regular file or symbolic link"
        path=${file#"$repo_root/"}
        printf '%s\n' "$path" >> "$actual"
    done
    sort -o "$actual" "$actual"
    cmp -s "$expected" "$actual" ||
        die "RXcalc directory differs from the exact reviewed file set"
}

validate_worktree_review_packet_directory() {
    list=$1
    expected="$temp_dir/expected-review-packet-paths"
    actual="$temp_dir/actual-review-packet-paths"
    expected_review_packet_paths "$list" | sort > "$expected"
    : > "$actual"

    for file in "$repo_root/$review_packet_directory"/* "$repo_root/$review_packet_directory"/.[!.]* "$repo_root/$review_packet_directory"/..?*; do
        if [ ! -e "$file" ] && [ ! -L "$file" ]; then
            continue
        fi
        [ -f "$file" ] && [ ! -L "$file" ] ||
            die "RXcalc review packet directory contains a non-regular file or symbolic link"
        path=${file#"$repo_root/"}
        printf '%s\n' "$path" >> "$actual"
    done
    sort -o "$actual" "$actual"
    cmp -s "$expected" "$actual" ||
        die "RXcalc review packet directory differs from the exact reviewed file set"
}

validate_commit_rxcalc_directory() {
    commit=$1
    list=$2
    expected="$temp_dir/expected-commit-rxcalc-paths"
    actual="$temp_dir/actual-commit-rxcalc-paths"
    expected_rxcalc_paths "$list" | sort > "$expected"
    git -C "$repo_root" ls-tree -r --name-only "$commit" -- "$rxcalc_directory" |
        sort > "$actual"
    cmp -s "$expected" "$actual" ||
        die "candidate RXcalc tree differs from the exact reviewed file set"
}

validate_commit_review_packet_directory() {
    commit=$1
    list=$2
    expected="$temp_dir/expected-commit-review-packet-paths"
    actual="$temp_dir/actual-commit-review-packet-paths"
    expected_review_packet_paths "$list" | sort > "$expected"
    git -C "$repo_root" ls-tree -r --name-only "$commit" -- "$review_packet_directory" |
        sort > "$actual"
    cmp -s "$expected" "$actual" ||
        die "candidate RXcalc review packet differs from the exact reviewed file set"

    while IFS= read -r path; do
        entries=$(git -C "$repo_root" ls-tree "$commit" -- "$path")
        mode=$(printf '%s\n' "$entries" | awk 'NF { print $1 }')
        type=$(printf '%s\n' "$entries" | awk 'NF { print $2 }')
        case "$mode:$type" in
            100644:blob|100755:blob)
                ;;
            *)
                die "candidate RXcalc review packet contains a non-regular Git entry"
                ;;
        esac
    done < "$actual"
}

ensure_no_symlink_components() {
    path=$1
    current=$repo_root
    old_ifs=$IFS
    IFS='/'
    set -- $path
    IFS=$old_ifs
    for component do
        current="$current/$component"
        [ ! -L "$current" ] ||
            die "bundle path traverses a symbolic link: $path"
    done
}

worktree_mode() {
    path=$1
    entries=$(git -C "$repo_root" ls-files -s -- "$path")
    count=$(printf '%s\n' "$entries" | awk 'NF { count += 1 } END { print count + 0 }')
    [ "$count" -eq 1 ] ||
        die "bundle path is untracked or has conflicted index entries: $path"
    mode=$(printf '%s\n' "$entries" | awk 'NF { print $1 }')
    case "$mode" in
        100644|100755)
            printf '%s\n' "$mode"
            ;;
        *)
            die "bundle path has unsupported Git mode $mode: $path"
            ;;
    esac
}

generate_worktree_manifest() {
    list=$1
    output=$2
    validate_worktree_rxcalc_directory "$list"
    validate_worktree_review_packet_directory "$list"
    worktree_mode "$relative_tracked_manifest" >/dev/null
    printf 'schema_version\trxcalc-review-bundle-v1\n' > "$output"
    tab=$(printf '\t')

    while IFS="$tab" read -r class path extra; do
        file="$repo_root/$path"
        ensure_no_symlink_components "$path"
        [ -f "$file" ] && [ ! -L "$file" ] ||
            die "bundle path is missing, non-regular, or a symbolic link: $path"
        mode=$(worktree_mode "$path")
        size=$(file_size "$file")
        digest=$(hash_file "$file")
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$class" "$mode" "$size" "$digest" "$path" >> "$output"
    done < "$list"
}

validate_full_commit() {
    commit=$1
    case "$commit" in
        ""|*[!0-9a-f]*)
            die "candidate commit must be a full lowercase Git object ID"
            ;;
    esac
    resolved=$(git -C "$repo_root" rev-parse --verify "$commit^{commit}" 2>/dev/null) ||
        die "candidate commit does not resolve to a commit"
    [ "$resolved" = "$commit" ] ||
        die "candidate commit must be the full lowercase Git object ID"
}

generate_commit_manifest() {
    commit=$1
    output=$2
    committed_allowlist="$temp_dir/committed-bundle-files.txt"
    git -C "$repo_root" cat-file blob "$commit:$relative_allowlist" \
        > "$committed_allowlist" 2>/dev/null ||
        die "candidate commit does not contain the bundle allowlist"
    validate_allowlist "$committed_allowlist"
    validate_commit_rxcalc_directory "$commit" "$committed_allowlist"
    validate_commit_review_packet_directory "$commit" "$committed_allowlist"

    if ! git -C "$repo_root" diff --quiet "$commit" -- "$relative_script"; then
        die "run the packet script from the exact candidate script revision"
    fi

    printf 'schema_version\trxcalc-review-bundle-v1\n' > "$output"
    printf 'candidate_commit\t%s\n' "$commit" >> "$output"
    tab=$(printf '\t')

    while IFS="$tab" read -r class path extra; do
        entries=$(git -C "$repo_root" ls-tree "$commit" -- "$path")
        count=$(printf '%s\n' "$entries" | awk 'NF { count += 1 } END { print count + 0 }')
        [ "$count" -eq 1 ] ||
            die "candidate bundle path is missing or ambiguous: $path"
        mode=$(printf '%s\n' "$entries" | awk 'NF { print $1 }')
        type=$(printf '%s\n' "$entries" | awk 'NF { print $2 }')
        case "$mode:$type" in
            100644:blob|100755:blob)
                ;;
            *)
                die "candidate bundle path is not a regular Git blob: $path"
                ;;
        esac

        blob="$temp_dir/current-blob"
        git -C "$repo_root" cat-file blob "$commit:$path" > "$blob" ||
            die "unable to read candidate Git blob: $path"
        size=$(file_size "$blob")
        digest=$(hash_file "$blob")
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$class" "$mode" "$size" "$digest" "$path" >> "$output"
    done < "$committed_allowlist"
}

print_digest() {
    manifest=$1
    digest=$(hash_file "$manifest")
    printf 'RXcalc review manifest SHA-256: %s\n' "$digest"
}

case "${1:-}" in
    --write)
        [ "$#" -eq 1 ] || usage
        allowlist="$repo_root/$relative_allowlist"
        validate_allowlist "$allowlist"
        generated="$temp_dir/worktree-manifest"
        generate_worktree_manifest "$allowlist" "$generated"
        mv "$generated" "$tracked_manifest"
        print_digest "$tracked_manifest"
        printf 'RXcalc review bundle manifest regenerated.\n'
        ;;
    --verify)
        [ "$#" -eq 1 ] || usage
        allowlist="$repo_root/$relative_allowlist"
        validate_allowlist "$allowlist"
        [ -f "$tracked_manifest" ] && [ ! -L "$tracked_manifest" ] ||
            die "tracked RXcalc review manifest is missing or is a symbolic link"
        generated="$temp_dir/worktree-manifest"
        generate_worktree_manifest "$allowlist" "$generated"
        if ! cmp -s "$tracked_manifest" "$generated"; then
            diff -u "$tracked_manifest" "$generated" >&2 || true
            die "RXcalc review bundle verification failed: tracked manifest does not match current files"
        fi
        print_digest "$tracked_manifest"
        printf 'RXcalc review bundle verified.\n'
        ;;
    --commit)
        [ "$#" -eq 4 ] && [ "${3:-}" = "--output" ] || usage
        commit=$2
        requested_output=$4
        [ -n "$requested_output" ] || usage
        validate_full_commit "$commit"
        generated="$temp_dir/commit-manifest"
        generate_commit_manifest "$commit" "$generated"
        mkdir -p "$(dirname "$requested_output")"
        mv "$generated" "$requested_output"
        print_digest "$requested_output"
        printf 'RXcalc candidate manifest generated from Git objects.\n'
        ;;
    *)
        usage
        ;;
esac
