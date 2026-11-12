#!/bin/sh
# Compile et lance les tests sur PC.
# Usage : ./run.sh <dossier du nRF Connect SDK>   (par exemple ~/ncs/v3.4.1)
set -e
NCS="${1:?Indiquez le dossier du nRF Connect SDK}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
cc -Wall -Wextra -Werror -g -fsanitize=address,undefined \
	-I"$HERE/../src" -I"$NCS/modules/lib/cjson" \
	"$HERE/test_logic.c" "$HERE/../src/text.c" "$HERE/../src/config_json.c" \
	"$NCS/modules/lib/cjson/cJSON.c" -lm -o "$OUT/test_logic"
"$OUT/test_logic"
rm -rf "$OUT"
