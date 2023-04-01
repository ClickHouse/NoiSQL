# NoiSQL — Generating Music With SQL Queries

NoiSQL (named after [Robert Noyce](https://en.wikipedia.org/wiki/Robert_Noyce)) shows how to play sound and music with declarative SQL queries.

It contains oscillators for basic waves, envelopes, sequencers, arpeggiators, effects (distortion, delay), noice generators, AM and FM, LFO, ...
Sometimes it can generate something nice, but usually not. 

# Quick Start

Install clickhouse-local:
```
curl https://clickhouse.com/ | sh
sudo ./clickhouse install
clickhouse-local --version
```

Demo:
```
./music2.sql.sh | aplay -f cd
```

Live editing:
```
sudo apt install inotifytools
./play.sh music0.sql
```
