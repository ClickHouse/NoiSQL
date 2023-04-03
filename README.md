# NoiSQL — Generating Music With SQL Queries

NoiSQL (named after [Robert Noyce](https://en.wikipedia.org/wiki/Robert_Noyce)) shows how to play sound and music with declarative SQL queries.

It contains oscillators for basic waves, envelopes, sequencers, arpeggiators, effects (distortion, delay), noise generators, AM and FM, and LFO, ...
Sometimes it can generate something nice, but usually not. 

# Table of Contents
- [NoiSQL — Generating Music With SQL Queries](#noisql---generating-music-with-sql-queries)
  * [Quick Start - Linux](#quick-start---linux)
  * [Quick Start - MacOS](#quick-start---macos)
  * [Bleeps and Bloops - a demonstration](#bleeps-and-bloops---a-demonstration)
  * [Examples](#examples)
- [How It Works](#how-it-works)
  * [Making Something Interesting](#making-something-interesting)
    + [Input](#input)
    + [Output Control](#output-control)
    + [Basic waves](#basic-waves)
    + [Helpers and LFO](#helpers-and-lfo)
    + [Noise](#noise)
    + [Distortion](#distortion)
    + [Envelopes](#envelopes)
    + [Sequencers](#sequencers)
    + [Delay](#delay)
    + [Components](#components)
    + [Combine It](#combine-it)
    + [Additional Commands](#additional-commands)
  * [Limitations](#limitations)
  * [Further Directions](#further-directions)
- [Motivation](#motivation)
- [Contributing](#contributing)
  * [Reading Corner](#reading-corner)

## Quick Start - Linux
Clone the Repository.

Download clickhouse-local:
```
curl https://clickhouse.com/ | sh
```

Install (Linux):
```
sudo ./clickhouse install
```

Check the installation:
```
clickhouse-local --version
```

## Quick Start - MacOS
Before beginning, please ensure that you have [homebrew](https://brew.sh/) installed.

Clone the Repository.

Change to the Repository folder (i.e. `cd NoiSQL`)

Install ClickHouse (macOS):
```
mkdir -p bin
mv clickhouse bin/clickhouse-local
export PATH="$(pwd)/bin:$PATH"
```

*NOTE: If you want this to live past a terminal restart add to your profile. That may look something like the below or `.bash_profile` or `.zshrc` depending on your terminal of choice.*

```
echo 'export PATH="'$(pwd)'/bin:$PATH"' >> .profile
```

In order to playback audio from the terminal (via STDIN) we use an open source project (with a convenient brew recipe) called 'sox'

```
brew install sox
```

## Bleeps and Bloops - a demonstration
Now, ClickHouse Local is setup and it is time to make our first noises.

Demo (Linux):
```
./music2.sql.sh | aplay -f cd
```

Demo (macOS):
```
./music2.sql.sh | play -t raw -b 16 -e signed -c 2 -r 44100 -v .75 -
```

Live editing (Linux):
```
sudo apt install inotifytools
./play.sh music0.sql
```

You can edit the `music0.sql` file, and the changes will automatically apply while playing. On macOS this is not possible due to the lack of inotifytools BUT the play script can be used to play any of the samples music*.sql files provided

## Examples
If, you are unable to use it yourself. You can still hear the output as .mp4 here.

https://user-images.githubusercontent.com/18581488/229301700-d71d5a9c-ad7e-492b-80ba-d49114fd0bfe.mp4

https://user-images.githubusercontent.com/18581488/229301704-d82d89b7-7650-44eb-a525-0630888d2080.mp4

https://user-images.githubusercontent.com/18581488/229301706-8e14b0c1-01a9-47a5-84dd-8a069832e63f.mp4

https://user-images.githubusercontent.com/18581488/229301709-9a102865-be02-4072-8707-48a6a571c500.mp4

--------------------------
# How It Works

An SQL query selects from the `system.numbers` table, containing a sequence of natural numbers, and transforms this sequence into a PCM audio signal in the CD format. This output signal is piped to the `aplay -f cd` tool (on Linux) to play it.

The CD (Compact Disc Audio) format is a 44100 Hz 16-bit stereo PCM signal.
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

It will give you an uninteresting clicky sound.

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

## Making Something Interesting

Here is a query from [music0.sql](music0.sql), that generates something at least listenable. Let's walk through this SQL query.

The WITH clause in the SQL query allows defining expressions for further use.
We can define both constants and functions (in form of lambda expressions).
We use the `allow_experimental_analyzer` setting to make this query possible.

### Input

Let's define the `time` column to be a floating point value representing the number of seconds.

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

We define oscillators as functions of time, with the period adjusted to be one second.
You can modify the frequency simply by multiplying the time argument.
For example, `sine_wave(time * 400)` - a sine wave of 400 Hz frequency.

The sine wave gives the cleanest and most boring sound.
```
, time -> sin(time * 2 * pi()) AS sine_wave
```

The [square wave](https://en.wikipedia.org/wiki/Square_wave) gives a very harsh sound; it can be imagined as a maximally-distorted sine wave.
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

LFO means "Low-Frequency Oscillation," and it is used to control a parameter of one signal with another low-frequency signal.
It can have multiple interesting effects. 

For example, AM - amplitude modulation is modulating the volume of one signal with another signal, and it will give a trembling effect, making your sine waves sound more natural.

Another example, FM - frequency modulation, is making the frequency of one signal change with another frequency.
See [the explanation](https://www.youtube.com/watch?v=vvBl3YUBUyY).

We take the wave and map it to the `[from, to]` interval:
```
, (from, to, wave, time) -> from + ((wave(time) + 1) / 2) * (to - from) AS lfo
```

Here is a discrete version of an LFO. It allows changing the signal as a step function:
```
, (from, to, steps, time) -> from + floor((time - floor(time)) * steps) / steps * (to - from) AS step_lfo
```

For some unknown reason, the frequencies of musical notes ("musical scale") are exponentially distributed, so sometimes we have to apply computations in the [logarithmic coordinates](https://en.wikipedia.org/wiki/Curvilinear_coordinates) to make a more pleasant sound:
```
, (from, to, steps, time) -> exp(step_lfo(log(from), log(to), steps, time)) AS exp_step_lfo
```

### Noise

Generating noise is easy. We just need random numbers.

But we want the noise to be deterministic (determined by the time) for further processing.
That's why we use `cityHash64` instead of a random and `erf` instead of `randNormal`.

All the following are variants of white noise. Although we can also generate [brown noise](https://en.wikipedia.org/wiki/Brownian_noise) with the help of `runningAccumulate`.

``` 
, time -> cityHash64(time) / 0xFFFFFFFFFFFFFFFF AS uniform_noise
, time -> erf(uniform_noise(time)) AS white_noise
, time -> cityHash64(time) % 2 ? 1 : -1 AS bernoulli_noise
```

### Distortion

Distortion alters the signal in various ways to make it sound less boring.

The harshest distortion - clipping - amplifies the signal, then clips what's above the range.
It adds higher harmonics and makes sound more metallic, and makes sine waves more square.
```
, (x, amount) -> clamp(x * amount) AS clipping
```

For a milder version, it makes sense to apply the `pow` function, such as square root to the `[-1, 1]` signal:
```
, (x, amount) -> clamp(x > 0 ? pow(x, amount) : -pow(-x, amount)) AS power_distortion
```

We can reduce the number of bits in the values of the signal, making it more coarse.
It adds some sort of noise, making it sound worn out.
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

The envelope is a way to make the signal sound like a note of a keyboard musical instrument, such as a piano.

It modulates the volume of the signal by:
- attack - time for the sound to appear;
- hold - time for the sound to play at maximum volume; 
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

We can make the musical note sound periodically to define a rhythm.
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

But the obvious way to generate a melody is to take a [Sierpinski triangle](https://en.wikipedia.org/wiki/Sierpi%C5%84ski_triangle).

Sierpinski triangles sound delicious:
```
, time -> bitAnd(time::UInt8, time::UInt8 * 8) AS sierpinski
```

Another way is to map the number of bits in a number to a musical note:
```
, time -> bitCount(time::UInt64) AS bit_count
```

Calculating the number of trailing zero bits gives us a nice arpeggiator:
```
, time -> log2(time::UInt64 > 0 ? bitXor(time::UInt64, time::UInt64 - 1) : 1) AS trailing_zero_bits
```

### Delay

If you ever wanted to generate dub music, you cannot go without a delay effect:
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

What is the idea? Let's take a [Sierpinski triangle](https://www.youtube.com/watch?v=IZHiBJGcrqI), put it into a sine wave, add FM to make it even fancier, and apply a few LFOs over the place.

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

### Combine It

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

### Additional Commands

Generate five minutes of audio and write to a `.pcm` file:
```
clickhouse-local --format RowBinary --query "SELECT * FROM system.numbers LIMIT 44100 * 5 * 60" \
 | clickhouse-local --allow_experimental_analyzer 1 --format RowBinary --structure "number UInt64" --queries-file music0.sql \
> music0.pcm
```

Convert `pcm` to `wav`:
```
ffmpeg -f s16le -ar 44.1k -ac 2 -i music0.pcm music0.wav
```

Convert `pcm` to `mp4`:
```
ffmpeg -f s16le -ar 44.1k -ac 2 -i music0.pcm music0.mp4
```

## Limitations

I haven't, yet, found a good way to implement filters (low-pass, high-pass, band-pass, etc.). It does not have Fourier transform, and we cannot operate on the frequency domain. However, the moving average can suffice as a simple filter.

## Further Directions

You can use ClickHouse as a sampler - storing the prepared musical samples in the table and arranging them with SELECT queries. For example, the [Mod Archive](https://modarchive.org/) can help.

You can use ClickHouse as a vocoder. Just provide the microphone input signal instead of the `system.numbers` as a table to `clickhouse-local`.

You can make the queries parameterized, replacing all the hundreds of constants with parameters. Then attach a device with hundreds of knobs and faders to your PC and provide their values of them as a streaming input table. Then you can control your sound like a pro. 

Real-time video generation can be added as well.

# Motivation

This is a fun project and neither a good nor convenient solution to a problem. Better solutions exist. 

There is not much sense in this project, although it can facilitate testing ClickHouse.

You could argue that modern AI, for example, [Riffusion](https://www.riffusion.com/), can do a better job. The counterargument is - if you enjoy what you are doing, it's better not to care if someone does it better but with less pleasure.

# Contributing

If you want to share new interesting examples, please make a pull request, adding them directly to this repository!


## Reading Corner

- [Sound](https://ciechanow.ski/sound/) by Bartosz Ciechanowski;
- [Bytebeat](https://www.youtube.com/watch?v=tCRPUv8V22o);
- [Color of Noise](https://en.wikipedia.org/wiki/Colors_of_noise);
- [Glitchmachine](https://www.youtube.com/watch?v=adoF2Lc70J8);
- [Audio Synthesis](https://www.youtube.com/watch?v=F1RsE4J9k9w);
- [44,100 Hz](https://en.wikipedia.org/wiki/44,100_Hz);
