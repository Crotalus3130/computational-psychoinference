# Psychoinference Toolkit

**Lexeme collapse and frequency aggregation for psycholinguistic time series analysis.**

---

## Overview

This toolkit provides functions for collapsing inflected word forms into part-of-speech-tagged lexemes and retrieving their aggregated frequency time series from Google Books ngram data.

The core problem it solves: Google Books provides frequency data for individual word forms ("run", "runs", "running", "ran"), but psycholinguistic analysis often requires the aggregate frequency of the *lexeme* — all forms of "run" considered as a single unit, separated by part of speech (RUN_VERB vs RUN_NOUN).

This toolkit handles:
- Inflection expansion via `WordData`
- Pronoun special cases (I/me/myself → I, he/him/himself → he, etc.)
- Part-of-speech grouping
- Frequency aggregation into time series

---

## Installation

1. Place `PsychoinferenceToolkit.wl` in a directory on your `$Path`, or in:
   - macOS: `~/Library/Mathematica/Applications/`
   - Windows: `%AppData%\Mathematica\Applications\`
   - Linux: `~/.Mathematica/Applications/`

2. Load the package:
```mathematica
<< PsychoinferenceToolkit`
```

---

## Requirements

- Wolfram Mathematica 12.0+
- Internet connection (for `WordFrequencyData` queries)
- `WordData` access (included in Mathematica)

---

## Core Functions

### `InflectionTotal`

The primary function. Collapses inflections and returns POS-tagged frequency time series.

```mathematica
result = InflectionTotal[{"run", "walk", "I", "we"}, "TimeSeries", {1946, 2019}]
```

Returns an association like:
```
<|
  TextElement["run", "GrammaticalUnit" -> {Verb}] -> TimeSeries[...],
  TextElement["run", "GrammaticalUnit" -> {Noun}] -> TimeSeries[...],
  TextElement["walk", "GrammaticalUnit" -> {Verb}] -> TimeSeries[...],
  TextElement["I", "GrammaticalUnit" -> {Pronoun}] -> TimeSeries[...],
  ...
|>
```

### `InflectionFrequencyTotal`

Alternative that uses `PartOfSpeech[]` for stricter POS assignment:

```mathematica
result = InflectionFrequencyTotal[{"run", "walk"}, "TimeSeries", {1946, 2019}]
```

### `WordInflectAssociation`

Returns the intermediate structure (word → POS-tagged inflections) without querying frequencies:

```mathematica
WordInflectAssociation[{"run", "walk"}]
```

Useful for inspecting what inflections will be grouped before committing to a slow API call.

---

## Example: Group-Orientation Index

The "we/I" index measures collective vs. individual orientation in language:

```mathematica
<< PsychoinferenceToolkit`

(* Get pronoun frequencies *)
pronouns = InflectionTotal[{"I", "we"}, "TimeSeries", {1946, 2019}];

(* Extract the pronoun time series *)
Ip = pronouns[TextElement[{"I"}, "GrammaticalUnit" -> {Entity["GrammaticalUnit", "Pronoun"]}]];
we = pronouns[TextElement[{"we"}, "GrammaticalUnit" -> {Entity["GrammaticalUnit", "Pronoun"]}]];

(* Compute index: (we - I) / (we + I) *)
(* Positive = group-oriented, Negative = self-oriented *)
groupOrientationIndex = (we - Ip) / (we + Ip);

(* Smooth and plot *)
DateListPlot[GaussianFilter[groupOrientationIndex, 3]]
```

---

## Merging with Psycholinguistic Constants

The toolkit includes merge functions for combining ngram data with external psycholinguistic databases (valence, arousal, dominance, concreteness, etc.):

```mathematica
(* Assuming you have an association of word -> abstractness scores *)
abstractnessData = <|"run" -> 2.3, "walk" -> 2.1, ...|>;

(* Merge with your ngram dataset *)
combined = MergeMixedAssociation[ngramData, abstractnessData];
```

`MergeMixedAssociation` handles the key mismatch between TextElement keys (from ngram data) and plain string keys (from psycholinguistic databases).

---

## Function Reference

| Function | Purpose |
|----------|---------|
| `InflectionTotal` | Main lexeme collapse + frequency retrieval |
| `InflectionFrequencyTotal` | Alternative with stricter POS via `PartOfSpeech[]` |
| `WordInflectAssociation` | Inspect inflection structure without frequency query |
| `AssociationKeyFlatten` | Flatten nested associations to list keys |
| `KeyGroupBy` | Group association by key function |
| `GroupFlatten` | Flatten grouped association structure |
| `MergeMixedAssociation` | Merge TextElement-keyed with string-keyed associations |
| `SameHeadMerge` | Merge associations with matching key structure |
| `ConvertToTextElement` | Create TextElement with GrammaticalUnit metadata |

---

## Notes

- Queries to `WordFrequencyData` are slow. For large word lists, consider caching results to `.wdx` files.
- The pronoun special cases handle English accusative/reflexive forms. Other languages would need different mappings.
- Part-of-speech information from `WordFrequencyData` may not perfectly align with POS tags in external psycholinguistic databases — hence why the toolkit produces the lexeme-level aggregate, allowing downstream lookup by string only.

---

## Citation

```
[Citation information to be added upon preprint publication]
```

---

## Author

Kevin Ostanek — Computational psychoinference and collective attention measurement.

## License

MIT
