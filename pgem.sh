#!/bin/sh
#/ Usage: pgem <options> command
#/
set -e

# Bring in pgem config
. pgem-sh-setup

# Shift off the first argument to determine the real command:
command="$1"
shift

# Set PHEMV
if $PGEMTRACE
then log trace "$command" "$@" 1>&2
fi

if   $__SHC__
then
    command="pgem-${command}"
    $command "$@"
elif expr "$0" : '.*\.sh$' >/dev/null
then exec "pgem-${command}.sh" "$@"
else exec "pgem-${command}" "$@"
fi