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

PIPE=$(mktemp -u)
mkfifo $PIPE
exec 3<>$PIPE
rm $PIPE

clickhouse-local --format RowBinary --query "SELECT number FROM system.numbers" >&3 &

while true
do
    clickhouse-local --allow_experimental_analyzer 1 --format RowBinary --structure "number UInt64" --query "$(cat $MUSIC)" <&3 | aplay -f cd &
    PID=$!
    inotifywait -e modify $MUSIC
    echo "Music changed." >&2
    kill -9 $PID
    kill -9 $(pidof aplay) 2>/dev/null
done
