(* ::Package:: *)

(* Psychoinference Toolkit *)
(* Lexeme collapse and frequency aggregation for psycholinguistic time series analysis *)
(* Author: Kevin Ostanek *)
(* License: MIT *)

BeginPackage["PsychoinferenceToolkit`"]
ObservedInflectionTotal
CanonicalInflectionTotal
WordInflectAssociation
AssociationKeyFlatten
KeyGroupBy
GroupFlatten
MergeMixedAssociation
MergeMixedAssociation2
SameHeadMerge
ConvertToTextElement
(* === Public Function Declarations === *)

ObservedInflectionTotal::usage = 
"ObservedInflectionTotal[wordlist, tsORtotal, dates] collapses inflected word forms into \
POS-tagged lexemes and returns aggregated frequency time series from Google Books ngram data.

Parameters:
  wordlist - List of words (strings) to analyze
  tsORtotal - \"TimeSeries\" for time series output, \"Total\" for aggregate counts
  dates - Date range as {startYear, endYear}

Returns: Association of TextElement keys (lexeme + POS) -> TimeSeries objects

Example:
  ObservedInflectionTotal[{\"run\", \"walk\"}, \"TimeSeries\", {1946, 2019}]

Notes:
- Automatically handles pronoun special cases (I/me/myself, he/him/himself, etc.)
- Groups inflections by part of speech before summing frequencies
- Uses WordData for base form lookup and inflection expansion"

CanonicalInflectionTotal::usage = 
"CanonicalInflectionTotal[wordlist, tsORtotal, dates] alternative lexeme collapse \
that enforces WordData's part-of-speech classification via PartOfSpeech[].

Parameters and returns identical to ObservedInflectionTotal.

Use this when you want stricter POS assignment from Wolfram's linguistic data \
rather than the POS variants returned by WordFrequencyData."

WordInflectAssociation::usage = 
"WordInflectAssociation[wordlist] returns the intermediate association mapping \
base words to their POS-tagged inflected forms, without frequency lookup.

Useful for inspecting the lexeme structure before committing to a frequency query."

AssociationKeyFlatten::usage = 
"AssociationKeyFlatten[assoc] flattens nested associations into a single-level \
association with list keys representing the path to each value.

AssociationKeyFlatten[assoc, f] applies function f to each flattened key."

KeyGroupBy::usage = 
"KeyGroupBy[assoc, f] groups association entries by applying f to their keys.

KeyGroupBy[assoc, f, red] applies reducer red to grouped values.

Operator forms KeyGroupBy[f] and KeyGroupBy[f, red] are supported."

GroupFlatten::usage = 
"GroupFlatten[group] flattens a grouped association structure, merging entries \
with matching first elements across groups."

MergeMixedAssociation::usage = 
"MergeMixedAssociation[assoc1, assoc2] merges two associations where assoc1 has \
TextElement keys and assoc2 has plain string keys matching the text content.

Missing keys in assoc2 are filled with Missing[\"NotAvailable\"]."

MergeMixedAssociation2::usage = 
"MergeMixedAssociation2[assoc1, assoc2] variant of MergeMixedAssociation for \
different key extraction patterns."

SameHeadMerge::usage = 
"SameHeadMerge[assoc1, assoc2] merges two associations with matching key structure, \
filling missing values from assoc2 with Missing[\"NotAvailable\"]."

ConvertToTextElement::usage = 
"ConvertToTextElement[word, pos] creates a TextElement with GrammaticalUnit metadata.

Example: ConvertToTextElement[\"run\", \"Verb\"] returns TextElement[\"run\", \"GrammaticalUnit\" -> Entity[\"GrammaticalUnit\", \"Verb\"]]"


Begin["`Private`"]

(* === Pronoun Special Cases === *)
(* Accusative and reflexive forms mapped to nominative base *)

$pronounSpecialCases = {
  "I" -> {"I", "me", "myself"}, 
  "he" -> {"he", "him", "himself"}, 
  "she" -> {"she", "her", "herself"}, 
  "we" -> {"we", "us", "ourselves"}, 
  "they" -> {"they", "them", "themselves"}, 
  "it" -> {"it", "itself"}
};

$pronounDropKeys = {
  "me", "myself", "him", "himself", "her", "herself", 
  "us", "ourselves", "them", "themselves"
};


(* === Association Utilities === *)

(* Internal: flatten nested associations *)
associationFlatten[] := <||>;
associationFlatten[assoc_Association] := 
  Join @@ KeyValueMap[listKey, Map[associationFlatten, assoc]];
associationFlatten[value_] := value;

(* Internal: prepend key to nested keys *)
listKey[key_, assoc_Association] := 
  AssociationThread[Prepend[#, key] & /@ Keys[assoc], Values[assoc]];
listKey[key_, value_] := Association[{key} -> value];

(* Public flatten function *)
AssociationKeyFlatten[assoc_Association, f_ : Identity] := 
  KeyMap[f, associationFlatten[assoc]];
AssociationKeyFlatten[value_, f_ : Identity] := value;

(* KeyGroupBy - multiple dispatch forms *)
Clear[KeyGroupBy];

KeyGroupBy[asc_?AssociationQ, f_List /; Length[f] > 0, red_] := 
  GroupBy[Normal @ asc, RightComposition[First, #] & /@ f, Association /* red];

KeyGroupBy[f_List /; Length[f] > 0, red_] := 
  Function[{asc}, KeyGroupBy[asc, f, red]];

KeyGroupBy[f_List /; Length[f] > 0] := KeyGroupBy[f, Identity];

KeyGroupBy[f : (_Symbol | _Function)] := KeyGroupBy[{f}];

KeyGroupBy[f : (_Symbol | _Function), red_] := KeyGroupBy[{f}, red];

KeyGroupBy[asc_?AssociationQ, f_, red_] := KeyGroupBy[f, red][asc];

KeyGroupBy[asc_?AssociationQ, f_] := KeyGroupBy[f][asc];

(* GroupFlatten *)
GroupFlatten[group_] := Module[{flattenedgroup},
  flattenedgroup = Flatten /@ GroupBy[#, First] & /@ Values @ Values @ group;
  Association[Association /@ Flatten[Normal /@ flattenedgroup, 1]]
];

(* Merge functions for combining ngram data with psycholinguistic constants *)
SameHeadMerge[association1_, association2_] := 
  AssociationMap[
    If[KeyExistsQ[association2, #],
      Join[association1[#], association2[#]],
      Join[association1[#], 
        AssociationThread[
          Keys[First[Values[association2]]], 
          Table[Missing["NotAvailable"], {Length @ Keys[First[Values[association2]]]}]
        ]
      ]
    ] &,
    Keys[association1]
  ];




(* === Core Lexeme Functions === *)

ObservedInflectionTotal[wordlist_List, tsORtotal_String, dates_] := 
Quiet @ Module[
  {specialcases, filteredwords, assoc, wordfreqposassoc, grouppos,
   cleanedgrouppos, untotaled, textelements, grouped1, grouped2, totaled},
  
  specialcases = $pronounSpecialCases;
  
  (* Convert all words to base forms *)
  filteredwords = If[
    WordData[#, "BaseForm", "List"] === {},
    #,
    First @ WordData[#, "BaseForm", "List"]
  ] & /@ wordlist;
  
  (* Create association of base words -> inflections *)
  assoc = DeleteDuplicates /@ AssociationMap[
    Join[{#}, WordData[#, "InflectedForms", "List"]] &, 
    filteredwords
  ];
  
  (* Add accusative cases to pronoun inflections *)
  assoc = ReplacePart[assoc, #] & @ specialcases;
  
  (* Drop accusative case pronouns as lemmas *)
  assoc = KeyDrop[assoc, $pronounDropKeys];
  
  (* Get frequency data with POS variants *)
  wordfreqposassoc = WordFrequencyData[
    #, 
    {"TimeSeries", "PartsOfSpeechVariants"}, 
    dates, 
    IgnoreCase -> True
  ] & /@ assoc;
  
  (* Select TextElement entries *)
  textelements = KeySelect[#, Head @ # === TextElement &] & /@ wordfreqposassoc;
  
  (* Group by grammatical unit *)
  grouppos = KeyGroupBy[#, Lookup[Last @ #, "GrammaticalUnit"] &] & /@ textelements;
  
  (* Remove missing POS entries *)
  cleanedgrouppos = KeyDrop[#, Missing["NotAvailable"]] & /@ grouppos;
  
  (* Flatten and regroup *)
  untotaled = AssociationKeyFlatten[cleanedgrouppos];
  grouped1 = KeyGroupBy[untotaled, 
    TextElement[Take[#, {1}], <|"GrammaticalUnit" -> Take[#, {2}]|>] &
  ];
  grouped2 = AssociationThread[Keys @ grouped1 -> Values @ Values @ grouped1];
  
  (* Sum inflection frequencies for each POS-specific lexeme *)
  totaled = TimeSeriesThread[Total, #] & /@ grouped2
];


CanonicalInflectionTotal[wordlist_List, tsORtotal_String, dates_] := 
Quiet @ Module[
  {specialcases, filteredwords, grouppos, textelements, flatassoc,
   assoc, flatinflectassoc, flattenedgroup, wordfreq, totaled},
  
  specialcases = $pronounSpecialCases;
  
  (* Convert to base forms *)
  filteredwords = If[
    WordData[#, "BaseForm", "List"] === {},
    #,
    First @ WordData[#, "BaseForm", "List"]
  ] & /@ wordlist;
  
  (* Build inflection association *)
  assoc = DeleteDuplicates /@ AssociationMap[
    Join[{#}, WordData[#, "InflectedForms", "List"]] &, 
    filteredwords
  ];
  
  assoc = ReplacePart[assoc, #] & @ specialcases;
  assoc = KeyDrop[assoc, $pronounDropKeys];
  
  (* Map parts of speech to inflections using PartOfSpeech[] *)
  textelements = Map[
    Function[word,
      Module[{pos},
        pos = PartOfSpeech[word];
        Map[TextElement[word, "GrammaticalUnit" -> #] &, pos]
      ]
    ],
    assoc,
    {2}
  ];
  
  flatassoc = Map[Flatten, textelements];
  
  (* Group inflections by POS *)
  grouppos = GroupBy[#, Lookup[Last @ #, "GrammaticalUnit"] &] & /@ flatassoc;
  
  flattenedgroup = Flatten /@ GroupBy[#, First] & /@ Values @ Values @ grouppos;
  flattenedgroup = Association[Association /@ Flatten[Normal /@ flattenedgroup, 1]];
  
  (* Get frequencies *)
  wordfreq = WordFrequencyData[#, tsORtotal, dates, IgnoreCase -> True] & /@ flattenedgroup;
  wordfreq = Select[DeleteMissing /@ wordfreq, # =!= <||> &];
  
  (* Sum inflection frequencies *)
  totaled = TimeSeriesThread[Total, Values @ #] & /@ wordfreq
];


WordInflectAssociation[wordlist_List] := 
Quiet @ Module[
  {specialcases, filteredwords, grouppos, textelements, flatassoc, assoc},
  
  specialcases = $pronounSpecialCases;
  
  filteredwords = If[
    WordData[#, "BaseForm", "List"] === {},
    #,
    First @ WordData[#, "BaseForm", "List"]
  ] & /@ wordlist;
  
  assoc = DeleteDuplicates /@ AssociationMap[
    Join[{#}, WordData[#, "InflectedForms", "List"]] &, 
    filteredwords
  ];
  
  assoc = ReplacePart[assoc, #] & @ specialcases;
  assoc = KeyDrop[assoc, $pronounDropKeys];
  
  textelements = Map[
    Function[word,
      Module[{pos},
        pos = PartOfSpeech[word];
        Map[TextElement[word, "GrammaticalUnit" -> #] &, pos]
      ]
    ],
    assoc,
    {2}
  ];
  
  flatassoc = Map[Flatten, textelements];
  GroupBy[#, Lookup[Last @ #, "GrammaticalUnit"] &] & /@ flatassoc
];


ConvertToTextElement[word_, pos_] := 
  TextElement[word, <|"GrammaticalUnit" -> Entity["GrammaticalUnit", pos]|>];


End[] (* `Private` *)

EndPackage[]
