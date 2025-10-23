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
files_list="$work_root/files.list"
cache_list="$work_root/cache.list"
comm_file="$work_root/comm"
stat_words="$work_root/statWords"
stat_words_vars="$work_root/statWords.vars"

mkdir -p "$files_dir" "$cache_dir" "$diff_dir"

# Copy files into the working directory, inflating gzip archives on the fly so
# each file is processed only once.
found_file=0
for file_path in "$input_dir"/*; do
  [ -f "$file_path" ] || continue
  found_file=1
  base_name=$(basename "$file_path")
  if [ "${base_name##*.}" = "gz" ]; then
    output_name="$files_dir/${base_name%.gz}"
    gunzip -c "$file_path" >"$output_name"
    touch -r "$file_path" "$output_name" 2>/dev/null || true
  else
    cp -p "$file_path" "$files_dir/"
  fi
done

if [ "$found_file" -eq 0 ]; then
  printf 'Error: "%s" does not contain any files to diff.\n' "$input_dir" >&2
  exit 1
fi

# Snapshot the list of working files so subsequent stages can reuse it without
# rescanning the directory tree.
find "$files_dir" -type f >"$files_list"

if [ ! -s "$files_list" ]; then
  printf 'Error: "%s" does not contain any files to diff.\n' "$input_dir" >&2
  exit 1
fi

file_count=$(wc -l <"$files_list" | tr -d '[:space:]')
trigger_value=$(( file_count / 2 ))

# Build the list of unique tokens per file.
: >"$stat_words"
while IFS= read -r file_name; do
  tr -c '[:alnum:]_' '[\n*]' <"$file_name" \
    | grep -v '^\s*$' \
    | sort -u >>"$stat_words"
done <"$files_list"

# Identify tokens that appear in more than half of the files and mask them so
# the diffs focus on the outliers rather than the shared structure.
awk -v limit="$trigger_value" '{ count[$0]++ } END { for (word in count) if (count[word] > limit) print word }' \
  "$stat_words" | sort -u >"$stat_words_vars"

# Copy the files so we can mask the less frequent tokens.
cp -a "$files_dir/." "$cache_dir/"
find "$cache_dir" -type f >"$cache_list"

if [ -s "$stat_words_vars" ]; then
  mask_pattern=$(paste -sd '|' "$stat_words_vars")
  while IFS= read -r file_name; do
    perl -0pi -e 's/\b(?:'"$mask_pattern"')\b/\${varMy}/g' "$file_name"
  done <"$cache_list"
fi

# Collect the common lines across all files.
tr '\n' '\0' <"$cache_list"   | xargs -0 awk -v limit="$trigger_value" '
      FNR == 1 { delete seen }
      {
        if (!seen[$0]++) {
          count[$0]++
        }
      }
      END {
        for (line in count) {
          if (count[line] > limit) {
            print line
          }
        }
      }
    ' >"$comm_file"

LC_ALL=C sort -u "$comm_file" -o "$comm_file"

# Build a diff for each file, highlighting only the unique lines.
while IFS= read -r file_name; do
  base_name=$(basename "$file_name")
  {
    printf '== %s ==\n' "$base_name"
    awk 'NR == FNR { common[$0] = 1; next } !common[$0] && !seen[$0]++' \
      "$comm_file" "$file_name"
    printf '=== missing ===\n'
    awk 'NR == FNR { present[$0] = 1; next } !present[$0] && !seen[$0]++' \
      "$file_name" "$comm_file"
  } >"$diff_dir/$base_name"
  touch -r "$file_name" "$diff_dir/$base_name" 2>/dev/null || true
done <"$cache_list"

# The diff files are available in "$diff_dir" when the script exits.
