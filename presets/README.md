# Country presets

A preset is a short, curated station list for one country. Retuner fetches the
file for each country you configure and merges it into the "My stations" menu,
so a new install has something worth listening to before anyone edits a config
file.

```
presets/fi.ini      ->  https://raw.githubusercontent.com/ollisulopuisto/retuner/master/presets/fi.ini
```

The file name is the ISO 3166-1 alpha-2 country code, lowercased. The format is
exactly `stations.ini`, so anything you can put in your own station list works
here:

```ini
[National]
Some National Station=https://stream.example/live.mp3|https://example/logo.png

[Regional]
Some Regional Station=https://stream.example/regional.mp3
```

## What belongs in one

**A broadcaster's own published stream, and not much else.** Warner Music & Sony
Music v TuneIn [2021] EWCA Civ 441 turned on who is making the communication to
the public. A geo-scoped list pointing at streams a broadcaster already
publishes for its own audience keeps this a convenience for listeners. A list
that aggregates other people's catalogues, or that re-points streams through
somewhere they were not meant to go, does not.

Concretely:

- **Yes**: the national broadcaster's radio channels, commercial stations that
  publish a direct stream, community stations that want to be found.
- **No**: streams lifted from an aggregator, streams behind a login, streams a
  broadcaster restricts by geography (they will fail for most listeners
  anyway), and anything you cannot point at a public page for.
- Keep it short. Twenty good stations beat two hundred, because the person
  browsing has a jog dial and a two-line display.

## Adding or updating one

Generate a starting point, which connects to every candidate and keeps only the
ones that actually serve audio:

```sh
./script/make-preset.py --country fi --out presets/fi.ini
```

Then **edit it**. The generator is good at proving a URL plays and bad at
knowing whether a station belongs in a national preset — it sorts by
click-count and groups by whatever tag radio-browser happens to carry. Rename
the categories to something a person would recognise, drop the noise, and put
the broadcaster's own channels first.

If you cannot reach radio-browser from where you are, the
`Build a country preset` workflow does the same thing on a GitHub runner and
uploads the result for you to review:
Actions → Build a country preset → Run workflow → enter a country code.

To re-check a file that has been sitting for a while and drop what has gone
dead:

```sh
./script/make-preset.py --prune presets/fi.ini
```

## How Retuner uses them

Set the countries in the add-on's configuration, or in `ytuner.ini`:

```ini
[Presets]
Enable=1
PresetsCountries=fi,se
```

At startup Retuner fetches each file, validates that it parses and contains at
least one http(s) URL, and only then replaces its cached copy in
`config/presets/`. A fetch that fails leaves the previous copy in place, so a
network problem costs you yesterday's list rather than the whole menu. Your own
`stations.ini` is always loaded first and always wins: a category that appears
in both is merged, not duplicated, and a station you already have is not added
twice.
