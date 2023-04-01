#!/usr/bin/env -S clickhouse-local --max_block_size 441000 --allow_experimental_analyzer 1 --format RowBinary --queries-file
# Usage: ./music2.sql.sh | aplay -f cd

WITH

-- Input
44100 AS sample_frequency
, number AS tick
, tick / sample_frequency AS time

-- Output control
, 1 AS master_volume
, level -> least(1.0, greatest(-1.0, level)) AS clamp
, level -> (clamp(level) * 0x7FFF * master_volume)::Int16 AS output
, x -> (x, x) AS mono

-- Basic waves
, time -> sin(time * 2 * pi()) AS sine_wave
, time -> time::UInt64 % 2 * 2 - 1 AS square_wave
, time -> (time - floor(time)) * 2 - 1 AS sawtooth_wave
, time -> abs(sawtooth_wave(time)) * 2 - 1 AS triangle_wave

-- Helpers
, (from, to, wave, time) -> from + ((wave(time) + 1) / 2) * (to - from) AS lfo
, (from, to, steps, time) -> from + floor((time - floor(time)) * steps) / steps * (to - from) AS step_lfo
, (from, to, steps, time) -> exp(step_lfo(log(from), log(to), steps, time)) AS exp_step_lfo

-- Noise
, time -> cityHash64(time) / 0xFFFFFFFFFFFFFFFF AS uniform_noise
, time -> erf(uniform_noise(time)) AS white_noise
, time -> cityHash64(time) % 2 ? 1 : -1 AS bernoulli_noise

-- Distortion
, (x, amount) -> clamp(x * amount) AS clipping
, (x, amount) -> clamp(x > 0 ? pow(x, amount) : -pow(-x, amount)) AS power_distortion
, (x, amount) -> round(x * exp2(amount)) / exp2(amount) AS bitcrush
, (time, sample_frequency) -> round(time * sample_frequency) / sample_frequency AS desample
, (time, wave, amount) -> (time - floor(time) < (1 - amount)) ? wave(time * (1 - amount)) : 0 AS thin
, (time, wave, amount) -> wave(floor(time) + pow(time - floor(time), amount)) AS skew

-- Combining
, (a, b, weight) -> a * (1 - weight) + b * weight AS combine

-- Envelopes
, (time, offset, attack, hold, release) ->
       time < offset ? 0
    : (time < offset + attack                  ? ((time - offset) / attack)
    : (time < offset + attack + hold           ? 1
    : (time < offset + attack + hold + release ? (offset + attack + hold + release - time) / release
    : 0))) AS envelope

, (bpm, time, offset, attack, hold, release) ->
    envelope(
        time * (bpm / 60) - floor(time * (bpm / 60)),
        offset,
        attack,
        hold,
        release) AS running_envelope

-- Sequencers
, (sequence, time) -> sequence[1 + time::UInt64 % length(sequence)] AS sequencer

SELECT

mono(output(
    arraySum(x -> 1 / 6
        * running_envelope(30 * (1 + x / 6), time, 0.05 * x, 0.005, lfo(0, 0.25, sine_wave, time / 8), 0.1)
        * sine_wave(time * 80 * exp2(x / 3)),
        range(12))))

FROM system.numbers;
