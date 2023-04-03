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

, (a, b, t) -> (1 - t) * a + t * b AS linear_transition
, (a, b, t) -> linear_transition(a, b, (1 - sin((t + 1/2) * pi())) / 2) AS smooth_transition

-- Noise
, time -> cityHash64(time) / 0xFFFFFFFFFFFFFFFF AS uniform_noise
, time -> erf(uniform_noise(time)) AS white_noise
, time -> cityHash64(time) % 2 ? 1 : -1 AS bernoulli_noise

, (time, frequency) -> cityHash64(floor(time * frequency)) / 0xFFFFFFFFFFFFFFFF
    AS step_noise

, (time, frequency) -> linear_transition(
        cityHash64(floor(time * frequency)),
        cityHash64(1 + floor(time * frequency)),
        (time * frequency - floor(time * frequency))) / 0xFFFFFFFFFFFFFFFF
    AS linear_noise

, (time, frequency) ->
    smooth_transition(
        cityHash64(floor(time * frequency)),
        cityHash64(1 + floor(time * frequency)),
        (time * frequency - floor(time * frequency))) / 0xFFFFFFFFFFFFFFFF
    AS sine_noise

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

, (bpm, time, offset, swing, attack, hold, release) ->
    envelope(
        time * (bpm / 60) - floor(time * (bpm / 60)),
        (time * (bpm / 60))::UInt64 % 2 ? offset - swing : offset + swing,
        attack,
        hold,
        release) AS running_envelope_swing

-- Sequencers
, (sequence, time) -> sequence[1 + time::UInt64 % length(sequence)] AS sequencer
, time -> bitAnd(time::UInt8, time::UInt8 * 8) AS sierpinski
, time -> bitCount(time::UInt64) AS bit_count
, time -> log2(time::UInt64 > 0 ? bitXor(time::UInt64, time::UInt64 - 1) : 1) AS trailing_zero_bits

, (from, to, time, seed) -> from + cityHash64(seed, floor(time)) % (1 + to - from) AS timed_rand

-- Notes and Octaves
, n -> transform(n, ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'], (SELECT arrayMap(x -> 220 * exp2((x + 3) / 12), range(12))), 0) AS note
, ns -> arrayMap(n -> note(n), splitByChar(' ', ns)) AS notes
, (ns, octave) -> arrayMap(x -> x * exp2(octave - 4), notes(ns)) AS notes_in_octave

-- Delay
, (time, wave, del, decay, count) -> arraySum(n -> wave(time - del * n) * pow(decay, n), range(count)) AS delay

-- Melodies
, 'G G A B A G E G G A B A G E G G A B A G E G A A B C B A G' AS chatgpt_melody1
, 'E E G A G E E G A G E E E G A G E E D D F# G F# E D D F# G F# E' AS chatgpt_melody2
, 'C C E G G E C C E G G E C C E G G E G G F F G A G F F G A G' AS chatgpt_melody3

SELECT

mono(output(
    0.2 * sine_wave(
        time * sequencer(notes_in_octave(chatgpt_melody2, timed_rand(1, 7, time * 4 / 7, 1)), time * 4)
        + sine_wave(time * sequencer(notes_in_octave(chatgpt_melody2, timed_rand(1, 5, time * 4 / 7, 2)), time * 4)))
    * lfo(0.5, 1, sine_wave, time * 10) * running_envelope(240 * 1, time, 0, 0.01, 0.01, 0.9)

    + 0.9 * clipping(sine_wave(time * 80 + 1 * sine_wave(time * 120 / 60 + 1/2)) * running_envelope(120, time, 0, 0.01, 0.01, 0.1), 2)
    + 0.5 * sine_wave(time * 80) * running_envelope(60, time, 0.25, 0.01, 0.01, 0.1)
    + 0.5 * sine_wave(time * 80) * running_envelope(60, time, 0.75, 0.01, 0.01, 0.1)

    + 0.25 * white_noise(time) * running_envelope(240, time, 0, 0.01, 0.01, 0.05)
    + 0.125 * white_noise(time) * running_envelope(60, time, 0.05, 0.01, 0.01, 0.05)
    + 0.0625 * white_noise(time) * running_envelope(60, time, 0.1, 0.01, 0.01, 0.05)
))

/*mono(output(
    delay(time, (time ->
        0.25 *
            skew(time, (time ->
                sine_wave(time * sequencer([250, 450, 150, 350, 450], time * 4)) * lfo(0.5, 1, sine_wave, time * 10) * running_envelope(240, time, 0, 0.01, 0.01, 0.9)),
            0.5)),
    0.0975, 0.5, 2)
))*/

FROM table;
