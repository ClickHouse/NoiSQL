# NoiSQL — Generating Music With SQL Queries

NoiSQL (named after [Robert Noyce](https://en.wikipedia.org/wiki/Robert_Noyce)) shows how to play sound and music with declarative SQL queries.

It contains oscillators for basic waves, envelopes, sequencers, arpeggiators, effects (distortion, delay), noise generators, AM and FM, LFO, ...
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

# How It Works

An SQL query selects from the `system.numbers` table, containing a sequence of natural numbers, and transforms this sequence into a PCM audio signal in the CD format. This output signal is piped to the `aplay -f cd` tool (on Linux) to play it.

The CD (Compact Disc) format is a 44100 Hz 16-bit stereo PCM signal.
- **44100 Hz** is the "sampling frequency", meaning that the signal has a value 44 100 times every second;
- **16 bit** is the precision of every value, and the value is represented by `Int16` (signed, two's complement, little endian) integer; 
- **stereo** means that we have two values at every sample - for the left channel and for the right channel;

The signal is represented in binary, corresponding to the ClickHouse's `RowBinary` format. Therefore, the bit rate of the signal is 16 * 2 * 44100 = 1411 kBit.

Although we could also use the classic 8-bit mono 9 kHz format, the CD format gives more possibilities. 

To get the idea, run this:
```
clickhouse-local --query "
    SELECT 
        (number % 44100)::Int16           AS left, 
        ((number + 22050) % 44100)::Int16 AS right 
    FROM system.numbers
    FORMAT RowBinary" | aplay -f cd
```

It will give you uninteresting clicky sound.

```
clickhouse-local --query "
    WITH number * 2 * pi() / 44100 AS time 
    SELECT
        (sin(time * 200) * 0x7FFF)::Int16 AS left,
        (sin(time * 400) * 0x7FFF)::Int16 AS right
    FROM system.numbers
    FORMAT RowBinary" | aplay -f cd
```

It will give you uninteresting waves.

# Something Interesting

Here is a query from [music0.sql](music0.sql), that generates something at least listenable. Let's walk through this SQL query.

The WITH clause in the SQL query allows to define expressions for further use.
We can define both constants and functions (in form of lambda expressions).
We use the `allow_experimental_analyzer` setting to make this query possible.

### Input

Let's define the `time` column to be floating point value, representing the number of seconds.

```
WITH

44100 AS sample_frequency
, number AS tick
, tick / sample_frequency AS time
```

### Output Control

Let us work with the signal in the floating point format, with values in the `[-1, 1]` range.
Here are the functions to convert it to the output PCM CD signal.

A knob for the volume:
```
, 1 AS master_volume
```

If the signal exceeds the boundaries, it will be clipped:
```
, level -> least(1.0, greatest(-1.0, level)) AS clamp
```

Floating point values are converted to Int16 for the output:
```
, level -> (clamp(level) * 0x7FFF * master_volume)::Int16 AS output
```

If we don't care about stereo - we can simply output a tuple (pair) of identical values:
```
, x -> (x, x) AS mono
```

### Basic waves

We define oscillators as functions of time, with period adjusted to be one second.
You can modify the frequency simply by multiplying the time argument.
For example, `sine_wave(time * 400)` - a sine wave of 400 Hz frequency.

The sine wave gives the most clean and boring sound.
```
, time -> sin(time * 2 * pi()) AS sine_wave
```

The square wave gives a very harsh sound, it can be imagined as a maximally-distorted sine wave.
``` 
, time -> time::UInt64 % 2 * 2 - 1 AS square_wave
```

Sawtooth wave
``` 
, time -> (time - floor(time)) * 2 - 1 AS sawtooth_wave
```

Triangle wave
``` 
, time -> abs(sawtooth_wave(time)) * 2 - 1 AS triangle_wave
```

### Helpers and LFO

LFO means "Low Frequency Oscillation" and it is used to control a parameter of one signal with another low-frequency signal.
It can give multiple interesting effects. 

For example, AM - amplitude modulation is modulating a volume of one signal with another signal, and it will give a tremble effect, making your sine waves sounding more natural.

Another example, FM - frequency modulation is making a frequency of one signal to change with another frequency.
See [the explanation](https://www.youtube.com/watch?v=vvBl3YUBUyY)

We take the wave and map it to the `[from, to]` interval:
```
, (from, to, wave, time) -> from + ((wave(time) + 1) / 2) * (to - from) AS lfo
```

Here is a discrete version of an LFO. It allows to change the signal as step function:
```
, (from, to, steps, time) -> from + floor((time - floor(time)) * steps) / steps * (to - from) AS step_lfo
```

For some unknown reason, the frequencies of musical notes ("musical scale") are exponentially distributed, so sometimes we have to apply computations in the logarithmic coordinates to make a more pleasant sound:
```
, (from, to, steps, time) -> exp(step_lfo(log(from), log(to), steps, time)) AS exp_step_lfo
```

### Noise

Generating noise is easy, we just need random numbers.

But we want the noise to be deterministic (determined by the time) for further processing.
That's why we use `cityHash64` instead of a random, and `erf` instead of `randNormal`.

In fact, all the following are variants of white noise. Although we can also generate brown noise with the help of `runningAccumulate`.

``` 
, time -> cityHash64(time) / 0xFFFFFFFFFFFFFFFF AS uniform_noise
, time -> erf(uniform_noise(time)) AS white_noise
, time -> cityHash64(time) % 2 ? 1 : -1 AS bernoulli_noise
```

### Distortion

Distortion alters the signal in various ways, to make it sound less boring.

The most harsh distortion amplifies the signal, then clips what's above the range.
It adds higher harmonics, and makes sound more metallic, and makes sine waves more square.
```
, (x, amount) -> clamp(x * amount) AS clipping
```

For a milder version, it makes sense to apply `pow` function, such as square root to the `[-1, 1]` signal:
```
, (x, amount) -> clamp(x > 0 ? pow(x, amount) : -pow(-x, amount)) AS power_distortion
```

We can reduce the number of bits in the values of the signal, making it more coarse.
It adds some sort of noise, making it sound worn-out.
```
, (x, amount) -> round(x * exp2(amount)) / exp2(amount) AS bitcrush
```

Lowering the sample rate makes the signal dirty. Try to apply it for white noise.
```
, (time, sample_frequency) -> round(time * sample_frequency) / sample_frequency AS desample
```

Something like compressing the periodic components in time and adding empty space - no idea why I need it:
``` 
, (time, wave, amount) -> (time - floor(time) < (1 - amount)) ? wave(time * (1 - amount)) : 0 AS thin
```

Skewing the waves in time making sine ways more similar to sawtooth waves:
``` 
, (time, wave, amount) -> wave(floor(time) + pow(time - floor(time), amount)) AS skew
```

### Envelopes

Envelope is a way to make the signal sound like a note of a keyboard musical instrument, such as piano.

It modulates the volume of the signal by:
- attack - time for the sound to appear;
- hold - time for the sound to play in maximum volume; 
- release - time for the sound to decay to zero;

This is a simplification of what typical envelopes are, but it's good enough.
```
, (time, offset, attack, hold, release) ->
       time < offset ? 0
    : (time < offset + attack                  ? ((time - offset) / attack)
    : (time < offset + attack + hold           ? 1
    : (time < offset + attack + hold + release ? (offset + attack + hold + release - time) / release
    : 0))) AS envelope
```

We can make the musical note to sound periodically, to define a rhythm.
For convenience, we define "bpm" as "beats per minute" and make it sound once in every beat.
```
, (bpm, time, offset, attack, hold, release) ->
    envelope(
        time * (bpm / 60) - floor(time * (bpm / 60)),
        offset,
        attack,
        hold,
        release) AS running_envelope
```

### Sequencers

To create a melody, we need a sequence of notes. A sequencer generates it.

In the first example, we simply take it from an array and make it repeat indefinitely:
``` 
, (sequence, time) -> sequence[1 + time::UInt64 % length(sequence)] AS sequencer
```

But the obvious way to generate a melody is to take a Sierpinski triangle.

Sierpinski triangles sound delicious:
```
, time -> bitAnd(time::UInt8, time::UInt8 * 8) AS sierpinski
```

Another way is to map the number of bits in a number to a musical note:
```
, time -> bitCount(time::UInt64) AS bit_count
```

Calculating the number of trailing zero bits give us a nice arpeggiator:
```
, time -> log2(time::UInt64 > 0 ? bitXor(time::UInt64, time::UInt64 - 1) : 1) AS trailing_zero_bits
```

### Delay

If you ever wanted to generate a dub music, you cannot go without a delay effect:
```
, (time, wave, delay, decay, count) -> arraySum(n -> wave(time - delay * n) * pow(decay, n), range(count)) AS delay
```

### Components

Here is a kick:
```
sine_wave(time * 50) * running_envelope(120, time, 0, 0.01, 0.01, 0.025) AS kick,
```

Here is a snare:
```
white_noise(time) * running_envelope(120, time, 0.5, 0.01, 0.01, 0.05) AS snare,
```

Let's also define five melodies. 

What is the idea? Let's take a Sierpinski triangle, put it into a sine wave, add FM to make it even fancier, and apply a few LFO over the place.

```
sine_wave(
    time * (100 * exp2(trailing_zero_bits(time * 8) % 12 / 6))
  + sine_wave(time * 3 + 1/4)) * 0.25 * lfo(0.5, 1, sine_wave, time * 11)
    * running_envelope(480, time, 0, 0.01, 0.1, 0.5)
    * lfo(0, 1, sine_wave, time / 12
    ) AS melody1,
  
sine_wave(time * (200 * exp2(bit_count(time * 8) % 12 / 6))
  + sine_wave(time * 3 + 1/4)) * 0.25 * lfo(0.5, 1, sine_wave, time * 11)
    * running_envelope(480, time, 0, 0.11, 0.1, 0.5) * lfo(0, 1, sine_wave, time / 24
    ) AS melody2,
    
sine_wave(time * (400 * exp2(sierpinski(time * 8) % 12 / 6))
    + sine_wave(time * 3 + 1/4)) * 0.25 * lfo(0.5, 1, sine_wave, time * 11)
    * running_envelope(480, time, 0, 0.21, 0.1, 0.5) * lfo(0, 1, sine_wave, time / 32
    ) AS melody3,
    
sine_wave(time * (800 / exp2(trailing_zero_bits(time * 8) % 12 / 6))
    + sine_wave(time * 3 + 1/4)) * 0.25 * lfo(0.5, 1, sine_wave, time * 11)
    * running_envelope(480, time, 0, 0.31, 0.1, 0.5) * lfo(0, 1, sine_wave, time / 16
    ) AS melody4
```

### Combine It Together

So, what will happen if we mix together some garbage and listen to it?
```
SELECT

mono(output(
      1.0   * melody1
    + 0.5   * melody2
    + 0.25  * melody3
    + 1.0   * melody4
    + 1     * kick
    + 0.025 * snare))

FROM table;
```
