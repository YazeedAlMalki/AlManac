export const meta = {
  name: 'nutrition-sources',
  description: 'Implement CIQUAL, CoFID and AFCD extract+canonicalise modules, adversarially verify each against the raw files, fix confirmed defects',
  phases: [
    { title: 'Implement', detail: 'one agent per source, following the USDA reference module' },
    { title: 'Verify', detail: 'two independent adversarial verifiers per source: raw-file fidelity, contract and code' },
    { title: 'Fix', detail: 'confirm and fix blocker/major findings, re-run tests' },
  ],
}

const SCRATCH = '/tmp/claude-1000/-home-yamal-projects-almanac/aa1cb92c-f3e8-40ca-88a0-fe292dbd0474/scratchpad/agents'

const COMMON = [
  'You are working in the Almanac repository at /home/yamal/projects/almanac, on the nutrition pipeline in tools/nutrition (Python 3.14, standard library plus openpyxl 3.1 and lxml 6 only - do not install anything). The food-data lake is /home/yamal/ALManac-food-data; its raw/ directory is immutable and must never be written.',
  'Read first, fully: tools/nutrition/README.md (the contract every source module honours), then almanac_nutrition/lake.py, dictionary.py, values.py, model.py, canonical_io.py, the reference source module almanac_nutrition/sources/usda.py, and tests/support.py plus tests/test_usda.py for test style. dictionary/*.csv already holds the mappings, tokens and derivation codes for every source.',
  'Hard rules:',
  '- Every mapped cell goes through values.qualify(...). Never parse numbers or tokens yourself. Tr, N, "-" and "traces" must never become 0. Blank cells produce no row. values.NegativeAmount means no row plus an entry in the canonical manifest notes["rejected_values"] (same shape as usda.py). Any other UnrecognisedValue in a mapped column must fail the stage with CanonicalError.',
  '- source_value is the original cell text (trimmed; numeric XLSX cells as repr(float) / str(int)); source_nutrient_id and source_unit verbatim from the source; licence_group from dictionary.group_of(NAMESPACE).',
  '- extract verifies every raw input with lake.verify_inputs(<manifest name>, <filenames relative to the manifest local_path>) before reading anything, and writes processed/extracted/<namespace>/ through lake.staged_directory with a manifest.json recording inputs and output sha256s. canonicalise reads only the extracted files, checks their sha256 against the extract manifest (as usda.canonicalise does) and writes through canonical_io.write_canonical.',
  '- Output is deterministic: running canonicalise twice gives identical output sha256s.',
  '- Other agents are editing other files concurrently. Do NOT edit README.md, anything in dictionary/, any almanac_nutrition/*.py outside your own sources/<namespace>.py, sources/__init__.py, sources/usda.py, tests/support.py, another source\'s module or tests, or anything under Sources/, Tests/ or Native/ (Swift). If you believe a shared file needs a change, do not make it: describe the exact change and why in shared_changes_needed.',
  '- Do NOT run the union, bundle, all or fixture commands (they write shared outputs).',
  '- Scratch files go under ' + SCRATCH + '/<your label>/ (create it).',
].join('\n')

const SOURCES = [
  {
    ns: 'ciqual',
    rawFiles: 'raw/ciqual/2025/*.xml',
    tokens: '"-" (not_analysed), "traces" (trace), "< x" bounds (below_loq, amount = x)',
    basisRule: 'every CIQUAL value is per_100g',
    brief: [
      'Source: ANSES-CIQUAL 2025. Namespace "ciqual", licence group B, collection manifest manifests/ciqual.json (local_path raw/ciqual/2025). Module file: almanac_nutrition/sources/ciqual.py; tests: tests/test_ciqual.py.',
      'Raw inputs, all UTF-8 with BOM and CRLF: alim_2025_11_03.xml (3,484 <ALIM> with alim_code, alim_nom_fr, alim_nom_eng, alim_nom_sci, alim_grp_code, alim_ssgrp_code, alim_ssssgrp_code, facteur_Jones), alim_grp_2025_11_03.xml (group names), const_2025_11_03.xml (74 <CONST>: const_code, const_nom_fr, const_nom_eng, code_INFOODS), compo_2025_11_03.xml (69 MB, 257,816 <COMPO>: alim_code, const_code, teneur, min, max, code_confiance, source_code - use lxml.etree.iterparse and clear elements), sources_2025_11_03.xml. Element text is padded with spaces; an element carrying the attribute missing=" " is an absent value. Extract each XML file to a CSV with one column per child element (trimmed text, missing -> empty string).',
      'Foods: every alim_code (3,484). local_id = alim_code. Names: en = alim_nom_eng (primary) and fr = alim_nom_fr. food_group_code = the most specific meaningful group code (sub-sub-group, else sub-group, else group - inspect alim_grp.xml for placeholder codes that mean "none"); food_group_name = its English name from alim_grp.xml. source_record like "alim_2025_11_03.xml alim_code=1000".',
      'Values: teneur for the const_codes mapped in dictionary/nutrient_map.csv (328 energy kcal, 25000 protein, 40000 fat, 31000 available carbohydrate, 34100 fibre, 60000 alcohol), basis per_100g. Measured profile of teneur: decimal comma ("59,7"), integers, "-" (83,246 rows overall, always with no code_confiance), "traces" (2,514), and "< x" bounds ("< 0,5", "< 20", ...). Call qualify(teneur, tokens=dictionary.tokens_for("ciqual"), decimal_comma=True, bound_prefix="<", numeric_override=mapping.numeric_qualifier_override). confidence = code_confiance (A-D) or "". source_unit = the mapping source_unit (kcal or g); verify it agrees with the unit written in const_nom_eng and fail if not. There are no duplicate (alim_code, const_code) pairs; fail loudly if one appears.',
      'Expected: 3,484 foods; every food has a compo row for every mapped const, so exactly 3,484 value rows per mapped nutrient (20,904 in total), "-" rows included as not_analysed.',
    ].join('\n'),
  },
  {
    ns: 'cofid',
    rawFiles: 'raw/cofid/2021/McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021.xlsx',
    tokens: '"Tr" (trace) and "N" (not_analysed)',
    basisRule: 'per_100ml for food group codes starting with Q (alcoholic beverages), per_100g otherwise',
    brief: [
      'Source: McCance and Widdowson CoFID 2021. Namespace "cofid", licence group B, collection manifest manifests/cofid.json (local_path raw/cofid/2021). Module file: almanac_nutrition/sources/cofid.py; tests: tests/test_cofid.py.',
      'Raw inputs: McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021.xlsx (sheets "List of tables", "1.1 Notes", "1.2 Factors", "1.3 Proximates", "1.4 Inorganics" ... "1.14 Organic Acids") and CoFID_oldFoods.xlsx (extract only, not canonicalised). The user guide PDF is in the same folder (pdftotext is installed) but is not a pipeline input. Extract every sheet of both workbooks to CSV verbatim with openpyxl (read_only=True, data_only=True): text cells as-is, floats as repr(float), ints as str(int), None as "". Keep all three header rows of each nutrient sheet. Name files unambiguously (for example "<workbook stem>__<sanitised sheet title>.csv").',
      'Foods: "1.3 Proximates" rows from spreadsheet row 4 that have a Food Code: 2,887 rows, 2,886 distinct codes. Code 13-669 is used for two different foods ("Aubergine, flesh and skin, roasted in rapeseed oil" and "Watercress, raw"). Per the README, every occurrence of a repeated code becomes local_id "{code}@row{n}" (n = spreadsheet row number); list collisions in notes. Name en = Food Name; food_group_code = Group; food_group_name from Appendix B of the user guide if you can extract it reliably with pdftotext (else ""). source_record "1.3 Proximates!row <n>".',
      'Values: columns identified by the code row (spreadsheet row 2): KCALS, PROT, FAT, CHO, AOACFIB, ALCO. Cells are text ("2.9", "Tr", "N"), floats or ints. Measured profile of 1.3 Proximates: 4,546 "Tr", 3,284 "N", 68,209 blank; mapped columns hold no other tokens (bracketed values like "(0.07)" occur only in fatty-acid sheets - one in a mapped column must fail the stage). Blank -> no row. qualify(cell_text, tokens=dictionary.tokens_for("cofid"), numeric_override=mapping.numeric_qualifier_override). confidence = "". source_unit from nutrient_map (kcal or g).',
      'Basis: the CoFID notes say values are per 100 g except alcoholic beverages, which are per 100 ml. Alcoholic beverages are the food groups starting with Q (QA beer, QC cider, QE wine, QF fortified wine, QG vermouth, QI liqueurs, QK spirits, Q pre-mixed drinks) -> basis per_100ml; everything else per_100g. Check the data and guide for anything that contradicts this and report it in notes_for_reviewer.',
      'Expected: 2,887 foods.',
    ].join('\n'),
  },
  {
    ns: 'afcd',
    rawFiles: 'raw/ausnut/release-3/AFCD Release 3 - Nutrient profiles.xlsx (and the other five workbooks)',
    tokens: 'none expected in Release 3 (all mapped cells numeric) - any token must fail',
    basisRule: 'per_100g from sheet "All solids & liquids per 100 g", per_100ml from sheet "Liquids only per 100 mL"',
    brief: [
      'Source: Australian Food Composition Database Release 3 (FSANZ). Namespace "afcd", licence group B, collection manifest manifests/ausnut.json (local_path raw/ausnut/release-3). Module file: almanac_nutrition/sources/afcd.py; tests: tests/test_afcd.py.',
      'Raw inputs: six workbooks "AFCD Release 3 - Food Details.xlsx", "- Nutrient profiles.xlsx", "- Nutrient details.xlsx", "- Recipes.xlsx", "- Food group information.xlsx", "- Reference List.xlsx". Extract every sheet of every workbook to CSV verbatim with openpyxl (read_only=True, data_only=True): text as-is, floats as repr(float), ints as str(int), None as "".',
      'Foods: workbook "Nutrient profiles", sheet "All solids & liquids per 100 g": title in row 1, header in row 3 (Public Food Key, Classification, Derivation, Food Name, then the nutrient columns), 1,588 foods from row 4. local_id = Public Food Key (e.g. F002258). Name en = Food Name. food_group_code = Classification as text (a numeric cell becomes str(int)); food_group_name from the "Food group information" workbook if it maps classification codes to names, else "". source_record "<sheet title>!row <n>".',
      'Values: nutrient columns are identified by header text with every whitespace run collapsed to one space and trimmed (headers contain newlines, e.g. "Protein \\n(g)" -> "Protein (g)"); the mapped headers are the source_nutrient_id values in dictionary/nutrient_map.csv (energy with dietary fibre kJ, protein, fat total, available carbohydrate without sugar alcohols, total dietary fibre, alcohol). per_100g values come from "All solids & liquids per 100 g"; per_100ml values from "Liquids only per 100 mL" (213 liquids, all also present in the per-100 g sheet; header whitespace differs slightly between the two sheets). Every mapped cell is numeric in Release 3, but still route each through qualify(str-form, tokens=dictionary.tokens_for("afcd"), numeric_override=mapping.numeric_qualifier_override, derivation_qualifier=dictionary.derivations_for("afcd")[Derivation]) and fail if a Derivation value has no mapping (values seen: Analysed 1,047, Recipe 416, Borrowed 78, Imputed 28, Label Data 10, Estimated 9). confidence = the Derivation text. Energy uses the mapping unit_conversion kj_to_kcal through values.convert; source_value stays the kJ cell and source_unit "kJ". A food in the mL sheet that is missing from the g sheet must fail loudly.',
      'Expected: 1,588 foods; per_100ml values for 213 of them.',
    ].join('\n'),
  },
]

const IMPL_SCHEMA = {
  type: 'object',
  properties: {
    files_written: { type: 'array', items: { type: 'string' } },
    commands_run: { type: 'array', items: { type: 'string' }, description: 'each command with its final result line' },
    tests_result: { type: 'string', description: 'tail of the full unittest run with ALMANAC_NUTRITION_INTEGRATION=1' },
    canonical_summary: { type: 'string', description: 'foods, names, values; values by nutrient, by qualifier and by basis, copied from processed/canonical/<ns>/manifest.json' },
    notes_for_reviewer: { type: 'array', items: { type: 'string' }, description: 'collisions, rejected values, anomalies, judgement calls, anything contradicting the brief' },
    shared_changes_needed: { type: 'array', items: { type: 'string' } },
  },
  required: ['files_written', 'commands_run', 'tests_result', 'canonical_summary', 'notes_for_reviewer', 'shared_changes_needed'],
}

const VERIFY_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['pass', 'fail'] },
    checks_performed: { type: 'array', items: { type: 'string' } },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
          title: { type: 'string' },
          evidence: { type: 'string' },
          suggested_fix: { type: 'string' },
        },
        required: ['severity', 'title', 'evidence', 'suggested_fix'],
      },
    },
  },
  required: ['verdict', 'checks_performed', 'findings'],
}

const FIX_SCHEMA = {
  type: 'object',
  properties: {
    ...IMPL_SCHEMA.properties,
    findings_fixed: { type: 'array', items: { type: 'string' } },
    findings_rejected: { type: 'array', items: { type: 'string' }, description: 'finding title and the evidence that it is not a defect' },
  },
  required: [...IMPL_SCHEMA.required, 'findings_fixed', 'findings_rejected'],
}

const READ_ONLY = 'You are read-only: do not edit any repository file and do not write into the lake. If you need to re-run the pipeline, do it in a scratch Lake whose manifests/ and raw data paths are symlinks to the real ones, exactly as tests/test_usda.py AgainstTheRealLake does.'

function implementPrompt(s) {
  return [
    COMMON, '',
    'TASK: implement the "' + s.ns + '" source module and its tests, following sources/usda.py as the reference.',
    s.brief, '',
    'Module contract: NAMESPACE = "' + s.ns + '"; extract(lake) -> Path; canonicalise(lake, dictionary) -> manifest dict. It is discovered automatically by sources/load_sources(), so the CLI picks it up without edits.',
    'Tests (tests/test_' + s.ns + '.py): at the module seam (extract and canonicalise) with small synthetic raw files built in a temp lake (tests.support.temp_lake, register, write_table; build XML with lxml or XLSX with openpyxl in the test). They must fail if a token became 0, if a blank produced a row, if the basis were wrong, if an unknown token were accepted, if inputs were not checksum-verified. Add an @integration test (tests.support.integration) that runs extract and canonicalise on the real lake through a scratch lake of symlinks and checks the expected food count and the absence of zero amounts from token cells.',
    'Then run against the real lake: cd /home/yamal/projects/almanac/tools/nutrition && python3 -m almanac_nutrition extract ' + s.ns + ' && python3 -m almanac_nutrition canonicalise ' + s.ns + ' ; then the whole suite: ALMANAC_NUTRITION_INTEGRATION=1 python3 -m unittest discover -s tests -t . (other agents are adding their own tests concurrently; if a failure is in their files, say so rather than touching them).',
    'Iterate until your tests and the real run pass. If the real data contradicts the brief, the data wins: handle it inside the contract or fail loudly, and report it.',
  ].join('\n')
}

function fidelityPrompt(s, impl) {
  return [
    COMMON, READ_ONLY, '',
    'You are an ADVERSARIAL VERIFIER for the "' + s.ns + '" source. Another agent wrote almanac_nutrition/sources/' + s.ns + '.py and produced /home/yamal/ALManac-food-data/processed/canonical/' + s.ns + '/. Your job is to find defects, not to confirm success; assume some exist.',
    'The source brief the implementer worked from:', s.brief, '',
    'The implementer\'s report: ' + JSON.stringify(impl), '',
    'LENS: FIDELITY TO THE RAW FILE. Write your own independent reader of the RAW file(s) (' + s.rawFiles + ') - do not import the implementation or read the extracted CSVs for this - and compare with processed/canonical/' + s.ns + '/foods.csv and values.csv:',
    '1. Every non-blank raw cell in a mapped column produces exactly one value row (or appears in the manifest notes.rejected_values) with the right food_ref, nutrient_id and basis, and no value row exists without a raw cell.',
    '2. Token cells - ' + s.tokens + ' - become their qualifier with an EMPTY amount and source_value equal to the raw token. Count tokens per mapped nutrient in raw and per qualifier in canonical: the counts must match exactly.',
    '3. amount 0 appears only where the raw cell is an explicit zero, and zero_reported exactly there.',
    '4. Numeric amounts equal the raw number (decimal comma handled; AFCD energy kJ / 4.184) to 1e-9 relative, and source_value equals the raw cell text.',
    '5. Every food in the raw table is present exactly once (identifier collisions handled per the README), with correct names and languages.',
    '6. Basis rule holds for every row: ' + s.basisRule + '.',
    'Also look for anything in the raw data nobody anticipated: new tokens, header units disagreeing with source_unit, duplicate keys, rows silently skipped.',
    'Report each defect with concrete evidence (food_ref, column, raw cell, canonical row). Severity: blocker = wrong or missing data would ship; major = contract violation; minor = cosmetic. verdict "fail" if any blocker or major.',
  ].join('\n')
}

function contractPrompt(s, impl) {
  return [
    COMMON, READ_ONLY, '',
    'You are an ADVERSARIAL REVIEWER for the "' + s.ns + '" source module. Your job is to find defects, not to confirm success.',
    'The source brief:', s.brief, '',
    'The implementer\'s report: ' + JSON.stringify(impl), '',
    'LENS: CONTRACT AND CODE. Review almanac_nutrition/sources/' + s.ns + '.py and tests/test_' + s.ns + '.py against tools/nutrition/README.md and the reference sources/usda.py:',
    '- raw inputs checksum-verified against the collection manifest before being read; staged writes; extract manifest with output sha256s; canonicalise checks extracted sha256s.',
    '- every mapped cell through values.qualify; NegativeAmount handled as in usda.py; unknown tokens fail; no private number or token parsing anywhere.',
    '- determinism: run extract + canonicalise twice into a scratch lake and compare output sha256s.',
    '- identifier, name, language, food group and source_record rules; notes record exclusions, collisions and rejections.',
    '- tests sit at the module seam, use synthetic fixtures that would actually catch Tr/N -> 0, blank -> row, wrong basis, collisions and unverified inputs; no tautological assertions; an integration test against the real lake exists. Run the whole suite: cd /home/yamal/projects/almanac/tools/nutrition && ALMANAC_NUTRITION_INTEGRATION=1 python3 -m unittest discover -s tests -t .',
    '- code reads like usda.py (naming, comment density, no dead code, no speculative options).',
    'Severity: blocker = wrong or missing data could ship; major = contract violation or a hard rule with no test; minor = style. verdict "fail" if any blocker or major.',
  ].join('\n')
}

function fixPrompt(s, impl, serious, minor) {
  return [
    COMMON, '',
    'TASK: another agent implemented almanac_nutrition/sources/' + s.ns + '.py and tests/test_' + s.ns + '.py; independent verifiers reported the findings below. Check each finding yourself against the code and the raw data - verifiers can be wrong. Fix every confirmed blocker and major (and minors that are cheap and clearly right), add or adjust tests so each fixed defect would have been caught, re-run python3 -m almanac_nutrition extract ' + s.ns + ' (if extraction changed) and canonicalise ' + s.ns + ' against the real lake, and run the whole suite with ALMANAC_NUTRITION_INTEGRATION=1.',
    'The source brief:', s.brief, '',
    'Implementation report: ' + JSON.stringify(impl), '',
    'Blocker/major findings: ' + JSON.stringify(serious), '',
    'Minor findings: ' + JSON.stringify(minor),
  ].join('\n')
}

const results = await pipeline(
  SOURCES,
  (s) => agent(implementPrompt(s), { label: 'implement:' + s.ns, phase: 'Implement', schema: IMPL_SCHEMA }),
  async (impl, s) => {
    if (!impl) return null
    const lenses = [
      { key: 'fidelity', prompt: fidelityPrompt(s, impl) },
      { key: 'contract', prompt: contractPrompt(s, impl) },
    ]
    const verdicts = await parallel(lenses.map((l) => () =>
      agent(l.prompt, { label: 'verify:' + s.ns + ':' + l.key, phase: 'Verify', schema: VERIFY_SCHEMA })
        .then((v) => (v ? { ...v, lens: l.key } : null))))
    return { impl, verdicts: verdicts.filter(Boolean) }
  },
  async (r, s) => {
    if (!r) return null
    const tagged = r.verdicts.flatMap((v) => v.findings.map((f) => ({ ...f, lens: v.lens })))
    const serious = tagged.filter((f) => f.severity !== 'minor')
    const minor = tagged.filter((f) => f.severity === 'minor')
    log(s.ns + ': ' + serious.length + ' blocker/major and ' + minor.length + ' minor findings')
    if (serious.length === 0) return { source: s.ns, impl: r.impl, verdicts: r.verdicts, fix: null }
    const fix = await agent(fixPrompt(s, r.impl, serious, minor), { label: 'fix:' + s.ns, phase: 'Fix', schema: FIX_SCHEMA })
    return { source: s.ns, impl: r.impl, verdicts: r.verdicts, fix }
  },
)
return results
