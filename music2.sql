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
    -- white_noise(time, 0.5)
    -- uniform_noise(time)
/*    # bernoulli_noise(desample(time, 100 + exp(sine_wave(desample(time, 10))) / e() * 10000)) +
    # bernoulli_noise(desample(time, 100 + log2(1 + triangle_wave(desample(time, 50))) * 10000)) +
    # combine(square_wave(time * 100), sine_wave(time * 100), lfo(0, 1, sine_wave, time)) +

    # sine_wave(time * 80) * running_envelope(120, time, 0.1, 0.001, 0.01, 0.1)

    power_distortion(
        sine_wave(time * 50 + 1 * sine_wave(time * 2 + 1/4))
            * running_envelope(120, time, 0, 0.01, 0.01, 0.1),
        lfo(1, 0.75, triangle_wave, time / 8))

    + (time > 4) * white_noise(time) * 0.2 * running_envelope(120, time, lfo(0.45, 0.55, sine_wave, time / 3), 0.01, lfo(0, 0.05, sine_wave, time / 5), 0.1)

    + (time > 8) * 0.1 * sine_wave(time * sequencer([400, 600, 300, 500], time * 2) + 0.2 * sine_wave(time * 5)) * running_envelope(120, time, 0.25, 0.01, 0.5, 0.1)
    + (time > 12) * 0.05 * sawtooth_wave(time * sequencer([200, 167, 139, 116, 97], time * 2) + 0.2 * sine_wave(time * 5)) * running_envelope(120, time, 0.5, 0.01, 0.1, 0.1)

    + (time > 16) * power_distortion(
        triangle_wave(time * 50 + 1 * sine_wave(time * 2 + 1/4))
            * running_envelope(120, time, lfo(0.5, 0.8, sine_wave, time / 5), 0.01, 0.01, 0.1),
        lfo(1, 0.75, triangle_wave, time / 9))

    + (time > 24) * 0.1 * triangle_wave(time * exp_step_lfo(400, 800, 7, time * 2 / 7) + 0.2 * sine_wave(time * 5)) * running_envelope(120, time, 0.25, 0.01, 0.5, 0.1)
    + (time > 28) * 0.03 * sawtooth_wave(time * exp_step_lfo(400, 200, 7, time * 2 / 7) + 0.2 * sine_wave(time * 5)) * running_envelope(480, time, 0.6, 0.01, 0.25, 0.1)

    + (time > 32) * power_distortion(
        sine_wave(time * 1400 + 1 * sine_wave(time * 50 + 1/4))
            * running_envelope(120, time, lfo(0.1, 0.5, sine_wave, time / 3), 0.01, 0.1, 0.1),
        lfo(1, 0.5, triangle_wave, time / 13)) * lfo(1, 0.25, triangle_wave, time / 13)*/

/*    power_distortion(
    lfo(0.5, 1, sine_wave, time) *
        ( 0.9 * running_envelope(40, time, 0.1, 0.005, 0.01, 0.5) * sine_wave(time * 200)
        + 0.8 * running_envelope(50, time, 0.2, 0.005, 0.01, 0.5) * sine_wave(time * 282)
        + 0.5 * running_envelope(60, time, 0.3, 0.005, 0.01, 0.5) * sine_wave(time * 400)
        + 0.5 * running_envelope(70, time, 0.4, 0.005, 0.01, 0.5) * sine_wave(time * 565)
        + 0.5 * running_envelope(80, time, 0.5, 0.005, 0.01, 0.5) * sine_wave(time * 800)
        + 0.5 * running_envelope(90, time, 0.5, 0.005, 0.01, 0.5) * sine_wave(time * 1131)
        + 0.5 * running_envelope(100, time, 0.6, 0.005, 0.01, 0.5) * sine_wave(time * 1600)),
    lfo(2, 0.5, triangle_wave, time / 32))*/

    arraySum(x -> 1 / 6
            * running_envelope(30 * (1 + x / 6), time, 0.05 * x, 0.005, lfo(0, 0.25, sine_wave, time / 8), 0.1)
            * sine_wave(time * 80 * exp2(x / 3)),
            range(12))
))

FROM table;
