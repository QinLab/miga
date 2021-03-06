#!/bin/bash
# Available variables: $PROJECT, $RUNTYPE, $MIGA, $CORES, $DATASET
set -e
SCRIPT="mytaxa_scan"
echo "MiGA: $MIGA"
echo "Project: $PROJECT"
# shellcheck source=scripts/miga.bash
source "$MIGA/scripts/miga.bash" || exit 1
DIR="$PROJECT/data/07.annotation/03.qa/02.mytaxa_scan"
[[ -d "$DIR" ]] || mkdir -p "$DIR"
cd "$DIR"

# Initialize
miga date > "$DATASET.start"
if [[ "$MIGA_MYTAXA" == "no" ]] ; then
  echo "This system doesn't currently support MyTaxa." \
    > "$DATASET.nomytaxa.txt"
else
  MT=$(dirname -- "$(which MyTaxa)")
  TMPDIR=$(mktemp -d /tmp/MiGA.XXXXXXXXXXXX)
  trap "rm -rf '$TMPDIR'; exit" SIGHUP SIGINT SIGTERM

  # Check type of dataset
  NOMULTI=$(miga list_datasets -P "$PROJECT" -D "$DATASET" --no-multi \
    | wc -l | awk '{print $1}')
  if [[ "$NOMULTI" -eq "1" ]] ; then
    # Check requirements
    if [[ ! -e "$MT/AllGenomes.faa.dmnd" ]] ; then
      echo "Cannot locate the database: $MT/AllGenomes.faa.dmnd:" \
            "no such file or directory" >&2
      exit 1
    fi
    if [[ ! -d "$MT/db" ]] ; then
      echo "Cannot locate the MyTaxa index: $MT/db:" \
            "no such file or directory" >&2
      exit 1
    fi
    if [[ ! -d "$MT/utils" ]] ; then
      echo "Cannot locate the MyTaxa utilities: $MT/utils:" \
            "no such file or directory" >&2
      exit 1
    fi
     
    if [[ ! -s "$DATASET.mytaxa" ]] ; then
      # Execute search
      if [[ ! -s "$DATASET.blast" ]] ; then
        diamond blastp -q "../../../06.cds/$DATASET.faa" \
          -d "$MT/AllGenomes.faa" -k 5 -p "$CORES" --min-score 60 \
          -a "$DATASET.daa" -t "$TMPDIR"
        diamond view -a "$DATASET.daa" -o "$DATASET.blast" -t "$TMPDIR"
      fi

      # Prepare MyTaxa input, execute MyTaxa, and generate profiles
      perl "$MT/utils/infile_convert.pl" -f no "LOREM_IPSUM" "$DATASET.blast" \
        | sort -k 13 > "$DATASET.mytaxain"
      "$MT/MyTaxa" "$DATASET.mytaxain" "$DATASET.mytaxa" "0.5"
    fi
    ruby "$MIGA/utils/mytaxa_scan.rb" "../../../06.cds/$DATASET.faa" \
          "$DATASET.mytaxa" "$DATASET.wintax"
    echo "
    source('$MIGA/utils/mytaxa_scan.R');
    pdf('$DATASET.pdf', 12, 7);
    mytaxa.scan('$DATASET.wintax');
    dev.off();
    " | R --vanilla

    # Extract genes from flagged regions
    [[ -d "$DATASET.reg" ]] || mkdir "$DATASET.reg"
    if [[ -e "$DATASET.wintax.regions" ]] ; then
      i=0
      for win in $(cat "$DATASET.wintax.regions") ; do
        let i=$i+1
        awk "NR==$win" "$DATASET.wintax.genes" | tr "\\t" "\\n" \
          > "$DATASET.reg/$i.ids"
        FastA.filter.pl -q "$DATASET.reg/$i.ids" \
          "../../../06.cds/$DATASET.faa" > "$DATASET.reg/$i.faa"
      done
    fi

    # Clean
    [[ -e "$DATASET.daa" ]] && rm "$DATASET.daa"
    [[ -s "$DATASET.blast" && ! -s "$DATASET.blast.gz" ]] \
      && gzip -9 -f "$DATASET.blast"
    [[ -s "$DATASET.mytaxain" && ! -s "$DATASET.mytaxain.gz" ]] \
      && gzip -9 -f "$DATASET.mytaxain"
  fi

fi

# Finalize
miga date > "$DATASET.done"
miga add_result -P "$PROJECT" -D "$DATASET" -r "$SCRIPT"
