#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <MAJOR.MINOR.PATCH>" >&2
    exit 64
fi

version="$1"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Version must be a stable semantic version (MAJOR.MINOR.PATCH): $version" >&2
    exit 64
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
output_dir="$repo_root/build"
bundle_name="Mocksmith-Documentation-$version"
output_zip="$output_dir/$bundle_name.zip"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mocksmith-documentation.XXXXXX")"
derived_data="$work_dir/DerivedData"
staging_dir="$work_dir/staging"

cleanup() {
    rm -rf "$work_dir"
}
trap cleanup EXIT

schemes=(Mocksmith MocksmithCombine MocksmithTesting MocksmithXCTest)

mkdir -p "$output_dir" "$staging_dir/$bundle_name"
rm -f "$output_zip"

for scheme in "${schemes[@]}"; do
    xcodebuild docbuild \
        -scheme "$scheme" \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$derived_data" \
        DOCC_SKIP_BUILDING_DOCUMENTATION_FOR_DEPENDENCIES=YES

    archive_matches="$(find "$derived_data/Build/Products" -type d -name "$scheme.doccarchive" -print)"
    archive_count="$(printf '%s\n' "$archive_matches" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "$archive_count" -ne 1 ]]; then
        echo "Expected exactly one documentation archive for $scheme; found $archive_count." >&2
        exit 1
    fi

    archive_path="$archive_matches"
    if [[ ! -f "$archive_path/metadata.json" ]]; then
        echo "Documentation archive for $scheme is missing metadata.json: $archive_path" >&2
        exit 1
    fi

    ditto "$archive_path" "$staging_dir/$bundle_name/$scheme.doccarchive"
done

ditto -c -k --keepParent "$staging_dir/$bundle_name" "$output_zip"
unzip -t "$output_zip" >/dev/null

zip_listing="$(unzip -Z1 "$output_zip")"
unexpected_entries="$(printf '%s\n' "$zip_listing" | awk -F/ -v bundle="$bundle_name" 'NF && $1 != bundle { print }')"
if [[ -n "$unexpected_entries" ]]; then
    echo "Documentation ZIP contains entries outside $bundle_name/." >&2
    exit 1
fi

archive_count="$(printf '%s\n' "$zip_listing" | awk -v bundle="$bundle_name" '$0 ~ "^" bundle "/[^/]+\\.doccarchive/$" { count++ } END { print count + 0 }')"
if [[ "$archive_count" -ne 4 ]]; then
    echo "Documentation ZIP must contain exactly four DocC archives; found $archive_count." >&2
    exit 1
fi

for scheme in "${schemes[@]}"; do
    archive_entry="$bundle_name/$scheme.doccarchive/"
    metadata_entry="$archive_entry"'metadata.json'
    if ! printf '%s\n' "$zip_listing" | grep -Fqx "$archive_entry"; then
        echo "Documentation ZIP is missing $archive_entry" >&2
        exit 1
    fi
    if ! printf '%s\n' "$zip_listing" | grep -Fqx "$metadata_entry"; then
        echo "Documentation ZIP is missing $metadata_entry" >&2
        exit 1
    fi
done

echo "Created $output_zip"
