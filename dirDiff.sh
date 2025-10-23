#!/bin/sh
# diff "<directory>"
# APA 20180712
# ynotopec at gmail.com

set -eu

usage() {
  cat <<'USAGE' >&2
Usage: dirDiff.sh <directory>

Generate simplified diffs for every file contained in <directory>.
The script extracts shared lines across files and highlights only the
lines that are unique to each file.
USAGE
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

input_dir=$1
if [ ! -d "$input_dir" ]; then
  printf 'Error: "%s" is not a directory.\n' "$input_dir" >&2
  usage
  exit 1
fi

work_root=$(mktemp -d -t dirDiff.XXXXXX)
cleanup() {
  rm -rf "$work_root"
}
trap cleanup EXIT HUP INT TERM

files_dir="$work_root/files"
cache_dir="$work_root/files.cache"
diff_dir="$work_root/diff"
comm_file="$work_root/comm"
stat_words="$work_root/statWords"
stat_words_vars="$work_root/statWords.vars"
tmp_file="$work_root/tmp"

mkdir -p "$files_dir" "$cache_dir" "$diff_dir"

# Copy files into the working directory.
find "$input_dir" -mindepth 1 -maxdepth 1 -type f -print \
  | while IFS= read -r file_name; do
      cp -p "$file_name" "$files_dir/"
    done

if ! find "$files_dir" -mindepth 1 -maxdepth 1 -type f | read -r _; then
  printf 'Error: "%s" does not contain any files to diff.\n' "$input_dir" >&2
  exit 1
fi

# Decompress gzip archives so they can be diffed like regular files.
find "$files_dir" -type f -name '*.gz' -print \
  | while IFS= read -r gz_file; do
      gunzip -f "$gz_file"
    done

# Build the list of unique tokens per file.
find "$files_dir" -type f -print \
  | while IFS= read -r file_name; do
      tr -c '[:alnum:]_' '[\n*]' <"$file_name" \
        | grep -v '^\s*$' \
        | sort -u
    done >"$stat_words"

file_count=$(find "$files_dir" -type f | wc -l | tr -d '[:space:]')
trigger_value=$(( file_count / 2 ))

# Identify tokens that appear in at most half of the files.
awk -v limit="$trigger_value" '{ count[$0]++ } END { for (word in count) if (count[word] <= limit) print word }' \
  "$stat_words" | sort -u >"$stat_words_vars"

# Copy the files so we can mask the less frequent tokens.
cp -a "$files_dir/." "$cache_dir/"

if [ -s "$stat_words_vars" ]; then
  while IFS= read -r token; do
    sed -i "s#\\b${token}\\b#\\$""{varMy}#g" "$cache_dir"/*
  done <"$stat_words_vars"
fi

# Collect the common lines across all files.
find "$cache_dir" -type f -print \
  | while IFS= read -r file_name; do
      awk '!seen[$0]++' "$file_name"
    done >"$comm_file"

awk -v limit="$trigger_value" 'NR == FNR { count[$0]++; next } count[$0] > limit' \
  "$comm_file" "$comm_file" | awk '!seen[$0]++' >"${comm_file}.filtered"
mv "${comm_file}.filtered" "$comm_file"

# Build a diff for each file, highlighting only the unique lines.
find "$cache_dir" -type f -print \
  | while IFS= read -r file_name; do
      {
        printf '== %s ==\n' "$(basename "$file_name")"
        cat "$file_name"
        printf '=== missing ===\n'
        cat "$comm_file"
      } >"$tmp_file"

      awk 'NR == FNR { count[$0]++; next } count[$0] == 1' "$tmp_file" "$tmp_file" \
        | tee "$diff_dir/$(basename "$file_name")"
    done

# The diff files are available in "$diff_dir" when the script exits.
