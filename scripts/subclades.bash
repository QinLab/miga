#!/bin/bash
# Available variables: $PROJECT, $RUNTYPE, $MIGA, $CORES
set -e
SCRIPT="subclades"
echo "MiGA: $MIGA"
echo "Project: $PROJECT"
# shellcheck source=scripts/miga.bash
source "$MIGA/scripts/miga.bash" || exit 1
cd "$PROJECT/data/10.clades/02.ani"

# Initialize
miga date > "miga-project.start"

# Run R code
"$MIGA/utils/subclades.R" \
  ../../09.distances/03.ani/miga-project.txt.gz \
  miga-project "$CORES"
mv miga-project.nwk miga-project.ani.nwk

# Compile
ruby "$MIGA/utils/subclades-compile.rb" . \
  >  miga-project.class.tsv \
  2> miga-project.class.nwk

# Finalize
miga date > "miga-project.done"
miga add_result -P "$PROJECT" -r "$SCRIPT"
