#!/bin/sh
# diff "<directory>"
# APA 20180712

[ $# -lt 1 ] &&exit

# initialisation des variables
baseDir="$(realpath "$(dirname $0)"/..)"
cacheFile=/tmp/"$(basename $0)"$$

########### commun algo
rm -rf /tmp/analyse*
filesList="$(ls -1d $1/*)"

# work dirs
mkdir -p /tmp/analyse$$/files /tmp/analyse$$/diff

# cp files and unzip
echo "${filesList}" |while read fileName ;do
  cp -p "${fileName}" /tmp/analyse$$/files/.
done
gunzip /tmp/analyse$$/files/*.gz
filesList="$(ls -1d /tmp/analyse$$/files/*)"

## find words
# stat words
echo "${filesList}" |while read fileName ;do
  cat "${fileName}" \
    |tr -c "[:alnum:]_" "[\n*]" |grep -v "^\s*$" |sort -u
done \
  >/tmp/analyse$$/statWords

triggerValue=$(($(ls -1d /tmp/analyse$$/files/* |wc -l) / 2))

# keep vars words
#awk 'NR == FNR {count[$0]++; next}; count[$0] <= '"${triggerValue}" /tmp/analyse$$/statWords /tmp/analyse$$/statWords |sort -u >/tmp/analyse$$/statWords.vars

# replace vars
cp -a /tmp/analyse$$/files /tmp/analyse$$/files.cache
cat /tmp/analyse$$/statWords.vars |while read lineMy ;do sed -i "s#\b${lineMy}\b#\${varMy}#g" /tmp/analyse$$/files.cache/* ;done

# comm = /tmp/analyse$$/comm
ls -1d /tmp/analyse$$/files.cache/* |while read fileName ;do
  cat "${fileName}" \
    |awk '!seen[$0]++'
done \
  >/tmp/analyse$$/comm

awk 'NR == FNR {count[$0]++; next}; count[$0] > '"${triggerValue}" /tmp/analyse$$/comm /tmp/analyse$$/comm \
  |awk '!seen[$0]++' >/tmp/analyse$$/comm2
mv -f /tmp/analyse$$/comm2 /tmp/analyse$$/comm

# diff = /tmp/analyse$$/diff/
ls -1d /tmp/analyse$$/files.cache/* |while read fileName ;do
  ( echo "== $(basename "${fileName}") =="
    cat "${fileName}"
    echo "=== missing ==="
    cat /tmp/analyse$$/comm
  ) >/tmp/analyse$$/tmp

  awk 'NR == FNR {count[$0]++; next}; count[$0] == 1' /tmp/analyse$$/tmp /tmp/analyse$$/tmp \
    |tee /tmp/analyse$$/diff/"$(basename "${fileName}")"
done

# libère cache
rm -f /tmp/"$(basename $0)"$$*
