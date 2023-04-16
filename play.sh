#!/bin/sh

# sudo apt install inotifytools
#
# This script implements live reload of musical queries.
#
# Run it as
#   ./play.sh music0.sql
#
# It will start playing and watch for the changes in the file.
# When the file is changed, it reloads and continues playing
# from about the same moment (preserving the time counter).
#
# This enables live performance environment :)
# You open an SQL query in your favorite text editor,
# edit and save it, listening to the updates immediately.

MUSIC="$1"

OS=$(uname -s)

if [ "${OS}" = "Linux" ]
then
    PIPE=$(mktemp -u)
    mkfifo $PIPE
    exec 3<>$PIPE
    rm $PIPE

    clickhouse-local --format RowBinary --max_threads 1 --query "SELECT number FROM system.numbers" >&3 &

    while true
    do
        clickhouse-local --allow_experimental_analyzer 1 --format RowBinary --max_threads 1 --structure "number UInt64" --query "$(cat $MUSIC)" <&3 | aplay -f cd &
        PID=$!
        inotifywait -e modify $MUSIC
        echo "Music changed." >&2
        kill -9 $PID
        kill -9 $(pidof aplay) 2>/dev/null
    done
else
    # Fallback to a simple option:

    clickhouse-local --format RowBinary --max_threads 1 --query "SELECT number FROM system.numbers" | \
        clickhouse-local --allow_experimental_analyzer 1 --format RowBinary --max_threads 1 --structure "number UInt64" --query "$(cat $MUSIC)" | \
        play -t raw -b 16 -e signed -c 2 -v .75 -r 44100 -
fi
