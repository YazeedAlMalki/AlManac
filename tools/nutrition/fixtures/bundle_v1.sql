PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE bundle_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
) STRICT;
INSERT INTO "bundle_meta" VALUES('built_at','fixture');
INSERT INTO "bundle_meta" VALUES('dictionary_sha256','6f6960fe5ee93e1ee4f586cf4143b3b57c09e3f5736bd21328a542d11874af1d');
INSERT INTO "bundle_meta" VALUES('schema_version','1');
INSERT INTO "bundle_meta" VALUES('sources','{"afcd": "Release 3", "almanac": "", "ciqual": "2025", "cofid": "2021", "usda": "2026-04-30"}');
INSERT INTO "bundle_meta" VALUES('tool_revision','fixture');
INSERT INTO "bundle_meta" VALUES('union_manifest_sha256','fixture');
CREATE TABLE nutrition_food (
    food_ref        TEXT PRIMARY KEY,
    namespace       TEXT NOT NULL REFERENCES nutrition_source (namespace),
    local_id        TEXT NOT NULL,
    licence_group   TEXT NOT NULL CHECK (licence_group IN ('A', 'B', 'N')),
    food_group_code TEXT NOT NULL,
    food_group_name TEXT NOT NULL,
    source_record   TEXT NOT NULL,
    UNIQUE (namespace, local_id),
    CHECK (food_ref = namespace || ':' || local_id)
) STRICT;
INSERT INTO "nutrition_food" VALUES('afcd:F900001','afcd','F900001','B','31304','','fixture');
INSERT INTO "nutrition_food" VALUES('almanac:fixture-dish','almanac','fixture-dish','N','native','Almanac native','fixture');
INSERT INTO "nutrition_food" VALUES('ciqual:900001','ciqual','900001','B','0701','breads and similar','fixture');
INSERT INTO "nutrition_food" VALUES('cofid:900-001','cofid','900-001','B','F','','fixture');
INSERT INTO "nutrition_food" VALUES('cofid:900-002','cofid','900-002','B','QE','','fixture');
INSERT INTO "nutrition_food" VALUES('cofid:900-003','cofid','900-003','B','MAA','','fixture');
INSERT INTO "nutrition_food" VALUES('cofid:900-004@row9','cofid','900-004@row9','B','DG','','fixture');
INSERT INTO "nutrition_food" VALUES('usda:900001','usda','900001','A','0800','Cereal Grains and Pasta','fixture');
CREATE TABLE nutrition_food_name (
    food_ref   TEXT NOT NULL REFERENCES nutrition_food (food_ref),
    language   TEXT NOT NULL,
    name       TEXT NOT NULL CHECK (name <> ''),
    is_primary INTEGER NOT NULL CHECK (is_primary IN (0, 1)),
    PRIMARY KEY (food_ref, language)
) STRICT;
INSERT INTO "nutrition_food_name" VALUES('afcd:F900001','en','Fixture stock, liquid',1);
INSERT INTO "nutrition_food_name" VALUES('almanac:fixture-dish','ar','طبق تجريبي',0);
INSERT INTO "nutrition_food_name" VALUES('almanac:fixture-dish','en','Fixture dish',1);
INSERT INTO "nutrition_food_name" VALUES('ciqual:900001','en','Fixture bread, white',1);
INSERT INTO "nutrition_food_name" VALUES('ciqual:900001','fr','Pain blanc (fixture)',0);
INSERT INTO "nutrition_food_name" VALUES('cofid:900-001','en','Fixture fruit, canned',1);
INSERT INTO "nutrition_food_name" VALUES('cofid:900-002','en','Fixture wine, red',1);
INSERT INTO "nutrition_food_name" VALUES('cofid:900-003','en','Fixture meat, lean',1);
INSERT INTO "nutrition_food_name" VALUES('cofid:900-004@row9','en','Fixture vegetable, repeated publisher code',1);
INSERT INTO "nutrition_food_name" VALUES('usda:900001','en','Fixture cereal, raw',1);
CREATE TABLE nutrition_nutrient (
    nutrient_id TEXT PRIMARY KEY,
    infoods_tag TEXT NOT NULL,
    name        TEXT NOT NULL,
    unit        TEXT NOT NULL,
    description TEXT NOT NULL
) STRICT;
INSERT INTO "nutrition_nutrient" VALUES('energy_kcal','ENERC_KCAL','Energy, as published','kcal','The publisher''s headline energy value, calculated by the publisher with its own conversion factors (USDA Energy or Atwater specific; CIQUAL EU 1169/2011; CoFID UK factors 4/9/3.75/7; AFCD equated with fibre). Not comparable across publishers.');
INSERT INTO "nutrition_nutrient" VALUES('energy_general_atwater_kcal','ENERC_KCAL','Energy, general Atwater factors, as published','kcal','Energy calculated by the publisher with general Atwater factors (4/4/9/7 kcal/g on total carbohydrate by difference). Published by USDA only (nutrient 2047).');
INSERT INTO "nutrition_nutrient" VALUES('protein','PROCNT','Protein','g','Protein: total nitrogen multiplied by the publisher''s nitrogen conversion factor.');
INSERT INTO "nutrition_nutrient" VALUES('fat_total','FAT','Fat, total','g','Total fat (total lipid) by the publisher''s extraction method. USDA ''Total fat (NLEA)'', a sum of fatty acids as triglycerides, is a different quantity and is not mapped.');
INSERT INTO "nutrition_nutrient" VALUES('carbohydrate_by_difference','CHOCDF','Carbohydrate, total, by difference','g','100 minus water, protein, fat, ash and alcohol. Includes dietary fibre.');
INSERT INTO "nutrition_nutrient" VALUES('carbohydrate_available','CHOAVL','Carbohydrate, available','g','Available carbohydrate by weight as EU Regulation 1169/2011 defines carbohydrate: sugars, starch and, where present, oligosaccharides, dextrins, glycogen and sugar alcohols (polyols). Excludes dietary fibre.');
INSERT INTO "nutrition_nutrient" VALUES('carbohydrate_available_monosaccharide','CHOAVLM','Carbohydrate, available, as monosaccharide equivalents','g','Available carbohydrate expressed as monosaccharide equivalents (CoFID convention): starch and disaccharides carry hydration factors of about 1.10 and 1.05 relative to carbohydrate_available.');
INSERT INTO "nutrition_nutrient" VALUES('fibre_total_dietary','FIBTG','Dietary fibre, total','g','Total dietary fibre by AOAC methods, including resistant starch and lignin. Englyst non-starch polysaccharide is a different quantity and is not mapped.');
INSERT INTO "nutrition_nutrient" VALUES('alcohol','ALC','Alcohol','g','Ethyl alcohol.');
CREATE TABLE nutrition_portion (
    food_ref      TEXT NOT NULL REFERENCES nutrition_food (food_ref),
    kind          TEXT NOT NULL CHECK (kind IN ('edible_proportion', 'household_measure', 'specific_gravity')),
    unit          TEXT NOT NULL,
    amount        REAL CHECK (amount IS NULL OR amount > 0),
    value         REAL CHECK (value IS NULL OR value >= 0),
    qualifier     TEXT NOT NULL REFERENCES nutrition_qualifier (qualifier),
    confidence    TEXT,
    source_value  TEXT NOT NULL CHECK (source_value <> ''),
    source_unit   TEXT NOT NULL,
    description   TEXT NOT NULL,
    modifier      TEXT NOT NULL,
    source_record TEXT NOT NULL,
    licence_group TEXT NOT NULL CHECK (licence_group IN ('A', 'B', 'N')),
    PRIMARY KEY (food_ref, kind, source_record),
    CHECK ((qualifier IN ('not_analysed', 'trace')) = (value IS NULL)),
    CHECK (qualifier <> 'zero_reported' OR value = 0),
    CHECK (kind = 'household_measure' OR amount IS NULL)
) STRICT;
INSERT INTO "nutrition_portion" VALUES('cofid:900-001','edible_proportion','fraction',NULL,0.65,'measured',NULL,'0.65','','','','1.2 Factors!row 4','B');
INSERT INTO "nutrition_portion" VALUES('usda:900001','household_measure','cup',1.0,156.0,'measured','21','156','g','','','food_portion.csv id=1','A');
INSERT INTO "nutrition_portion" VALUES('usda:900001','household_measure','tablespoon',2.0,33.9,'measured','21','33.9','g','','chopped','food_portion.csv id=2','A');
CREATE TABLE nutrition_qualifier (
    qualifier         TEXT PRIMARY KEY,
    has_quantity      INTEGER NOT NULL CHECK (has_quantity IN (0, 1)),
    directly_observed INTEGER NOT NULL CHECK (directly_observed IN (0, 1)),
    amount_rule       TEXT NOT NULL CHECK (amount_rule IN ('null', 'required')),
    description       TEXT NOT NULL
) STRICT;
INSERT INTO "nutrition_qualifier" VALUES('measured',1,1,'required','A number the source reports as determined for this food.');
INSERT INTO "nutrition_qualifier" VALUES('trace',1,0,'null','Present in trace amounts. No source publishes a number for a trace, so amount is empty; it is never 0. Arithmetic may treat it as negligible, and must say so.');
INSERT INTO "nutrition_qualifier" VALUES('not_analysed',0,0,'null','No usable number: not analysed, missing (CIQUAL ''-''), or present in significant quantities with no reliable amount (CoFID ''N''). Amount is empty; it is never 0.');
INSERT INTO "nutrition_qualifier" VALUES('below_loq',1,0,'required','Below a limit the source states; amount is that limit, an upper bound (CIQUAL ''< x'').');
INSERT INTO "nutrition_qualifier" VALUES('borrowed',1,0,'required','Taken from another food or another database, or from a label or manufacturer (USDA B*/C*/T/LC*/M* codes; AFCD Borrowed, Imputed, Label Data, Estimated).');
INSERT INTO "nutrition_qualifier" VALUES('calculated_recipe',1,0,'required','Calculated from a recipe or from the food''s physical composition.');
INSERT INTO "nutrition_qualifier" VALUES('calculated_factor',1,0,'required','Calculated from other components with conversion factors, by difference or by concentration adjustment. Every published energy value.');
INSERT INTO "nutrition_qualifier" VALUES('zero_reported',1,1,'required','The source published an explicit zero. Distinct from trace and from not_analysed.');
CREATE TABLE nutrition_source (
    namespace     TEXT PRIMARY KEY,
    dataset_id    TEXT NOT NULL,
    name          TEXT NOT NULL,
    release       TEXT NOT NULL,
    licence       TEXT NOT NULL,
    licence_group TEXT NOT NULL CHECK (licence_group IN ('A', 'B', 'N')),
    attribution   TEXT NOT NULL,
    url           TEXT NOT NULL
) STRICT;
INSERT INTO "nutrition_source" VALUES('afcd','afcd_release3','Australian Food Composition Database, Release 3','Release 3','CC BY 4.0','B','Food Standards Australia New Zealand. Australian Food Composition Database, Release 3. Licensed under CC BY 4.0. FSANZ does not endorse Almanac or its use of the work.','https://www.foodstandards.gov.au/science-data/food-nutrient-databases/afcd');
INSERT INTO "nutrition_source" VALUES('almanac','almanac_native','Almanac native foods','','Almanac proprietary','N','Almanac.','https://almanac.invalid/');
INSERT INTO "nutrition_source" VALUES('ciqual','ciqual_2025','ANSES-CIQUAL French food composition table 2025','2025','CC BY 4.0 and Etalab Open Licence 2.0','B','ANSES. Table de composition nutritionnelle des aliments Ciqual 2025. Licensed under CC BY 4.0.','https://doi.org/10.5281/zenodo.17550133');
INSERT INTO "nutrition_source" VALUES('cofid','cofid_2021','McCance and Widdowson''s Composition of Foods Integrated Dataset 2021','2021','Open Government Licence v3.0','B','Contains public sector information licensed under the Open Government Licence v3.0. Source: McCance and Widdowson''s The Composition of Foods Integrated Dataset 2021, Public Health England.','https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid');
INSERT INTO "nutrition_source" VALUES('usda','usda_fdc','USDA FoodData Central, Foundation Foods','2026-04-30','CC0 1.0 Universal','A','U.S. Department of Agriculture, Agricultural Research Service. FoodData Central, 2019. fdc.nal.usda.gov.','https://fdc.nal.usda.gov/');
CREATE TABLE nutrition_value (
    food_ref           TEXT NOT NULL REFERENCES nutrition_food (food_ref),
    nutrient_id        TEXT NOT NULL REFERENCES nutrition_nutrient (nutrient_id),
    basis              TEXT NOT NULL CHECK (basis IN ('per_100g', 'per_100ml')),
    amount             REAL CHECK (amount IS NULL OR amount >= 0),
    qualifier          TEXT NOT NULL REFERENCES nutrition_qualifier (qualifier),
    confidence         TEXT,
    source_value       TEXT NOT NULL CHECK (source_value <> ''),
    source_nutrient_id TEXT NOT NULL,
    source_unit        TEXT NOT NULL,
    licence_group      TEXT NOT NULL CHECK (licence_group IN ('A', 'B', 'N')),
    PRIMARY KEY (food_ref, nutrient_id, basis),
    CHECK ((qualifier IN ('not_analysed', 'trace')) = (amount IS NULL)),
    CHECK (qualifier <> 'zero_reported' OR amount = 0)
) STRICT;
INSERT INTO "nutrition_value" VALUES('afcd:F900001','alcohol','per_100g',0.0,'zero_reported','Recipe','0','Alcohol (g)','g','B');
INSERT INTO "nutrition_value" VALUES('afcd:F900001','alcohol','per_100ml',0.0,'zero_reported','Recipe','0','Alcohol (g)','g','B');
INSERT INTO "nutrition_value" VALUES('afcd:F900001','carbohydrate_available','per_100g',0.4,'calculated_recipe','Recipe','0.4','Available carbohydrate, with sugar alcohols (g)','g','B');
INSERT INTO "nutrition_value" VALUES('afcd:F900001','carbohydrate_available','per_100ml',0.42,'calculated_recipe','Recipe','0.42','Available carbohydrate, with sugar alcohols (g)','g','B');
INSERT INTO "nutrition_value" VALUES('afcd:F900001','energy_kcal','per_100g',4.30210325047801145e+00,'calculated_factor','Recipe','18','Energy with dietary fibre, equated (kJ)','kJ','B');
INSERT INTO "nutrition_value" VALUES('afcd:F900001','energy_kcal','per_100ml',4.54110898661567841e+00,'calculated_factor','Recipe','19','Energy with dietary fibre, equated (kJ)','kJ','B');
INSERT INTO "nutrition_value" VALUES('afcd:F900001','fat_total','per_100g',0.2,'calculated_recipe','Recipe','0.2','Fat, total (g)','g','B');
INSERT INTO "nutrition_value" VALUES('afcd:F900001','fat_total','per_100ml',0.21,'calculated_recipe','Recipe','0.21','Fat, total (g)','g','B');
INSERT INTO "nutrition_value" VALUES('afcd:F900001','fibre_total_dietary','per_100g',0.0,'zero_reported','Recipe','0','Total dietary fibre (g)','g','B');
INSERT INTO "nutrition_value" VALUES('afcd:F900001','fibre_total_dietary','per_100ml',0.0,'zero_reported','Recipe','0','Total dietary fibre (g)','g','B');
INSERT INTO "nutrition_value" VALUES('afcd:F900001','protein','per_100g',0.2,'calculated_recipe','Recipe','0.2','Protein (g)','g','B');
INSERT INTO "nutrition_value" VALUES('afcd:F900001','protein','per_100ml',0.21,'calculated_recipe','Recipe','0.21','Protein (g)','g','B');
INSERT INTO "nutrition_value" VALUES('almanac:fixture-dish','carbohydrate_available','per_100g',20.0,'calculated_recipe',NULL,'20','carbohydrate_available','g','N');
INSERT INTO "nutrition_value" VALUES('almanac:fixture-dish','fat_total','per_100g',8.0,'calculated_recipe',NULL,'8','fat_total','g','N');
INSERT INTO "nutrition_value" VALUES('almanac:fixture-dish','fibre_total_dietary','per_100g',2.0,'calculated_recipe',NULL,'2','fibre_total_dietary','g','N');
INSERT INTO "nutrition_value" VALUES('almanac:fixture-dish','protein','per_100g',10.0,'calculated_recipe',NULL,'10','protein','g','N');
INSERT INTO "nutrition_value" VALUES('ciqual:900001','alcohol','per_100g',NULL,'not_analysed',NULL,'-','60000','g','B');
INSERT INTO "nutrition_value" VALUES('ciqual:900001','carbohydrate_available','per_100g',50.3,'measured','B','50,3','31000','g','B');
INSERT INTO "nutrition_value" VALUES('ciqual:900001','energy_kcal','per_100g',250.0,'calculated_factor','D','250','328','kcal','B');
INSERT INTO "nutrition_value" VALUES('ciqual:900001','fat_total','per_100g',0.5,'below_loq','A','< 0,5','40000','g','B');
INSERT INTO "nutrition_value" VALUES('ciqual:900001','fibre_total_dietary','per_100g',3.1,'measured','B','3,1','34100','g','B');
INSERT INTO "nutrition_value" VALUES('ciqual:900001','protein','per_100g',9.01,'measured','A','9,01','25000','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-001','carbohydrate_available_monosaccharide','per_100g',0.8,'measured',NULL,'0.8','CHO','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-001','energy_kcal','per_100g',151.0,'calculated_factor',NULL,'151','KCALS','kcal','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-001','fat_total','per_100g',15.2,'measured',NULL,'15.2','FAT','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-001','protein','per_100g',2.9,'measured',NULL,'2.9','PROT','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-002','alcohol','per_100ml',10.7,'measured',NULL,'10.7','ALCO','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-002','carbohydrate_available_monosaccharide','per_100ml',0.2,'measured',NULL,'0.2','CHO','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-002','energy_kcal','per_100ml',76.0,'calculated_factor',NULL,'76','KCALS','kcal','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-002','fat_total','per_100ml',0.0,'zero_reported',NULL,'0','FAT','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-002','fibre_total_dietary','per_100ml',0.0,'zero_reported',NULL,'0','AOACFIB','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-002','protein','per_100ml',NULL,'trace',NULL,'Tr','PROT','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-003','carbohydrate_available_monosaccharide','per_100g',NULL,'not_analysed',NULL,'N','CHO','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-003','energy_kcal','per_100g',125.0,'calculated_factor',NULL,'125','KCALS','kcal','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-003','fat_total','per_100g',5.0,'measured',NULL,'5.0','FAT','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-003','protein','per_100g',20.0,'measured',NULL,'20.0','PROT','g','B');
INSERT INTO "nutrition_value" VALUES('cofid:900-004@row9','energy_kcal','per_100g',62.0,'calculated_factor',NULL,'62','KCALS','kcal','B');
INSERT INTO "nutrition_value" VALUES('usda:900001','alcohol','per_100g',0.0,'zero_reported','A','0.0','1018','G','A');
INSERT INTO "nutrition_value" VALUES('usda:900001','carbohydrate_by_difference','per_100g',67.7,'calculated_factor','NC','67.7','1005','G','A');
INSERT INTO "nutrition_value" VALUES('usda:900001','energy_general_atwater_kcal','per_100g',382.0,'calculated_factor','NC','382','2047','KCAL','A');
INSERT INTO "nutrition_value" VALUES('usda:900001','energy_kcal','per_100g',379.0,'calculated_factor','NC','379','2048','KCAL','A');
INSERT INTO "nutrition_value" VALUES('usda:900001','fat_total','per_100g',6.5,'measured','A','6.5','1004','G','A');
INSERT INTO "nutrition_value" VALUES('usda:900001','fibre_total_dietary','per_100g',10.1,'measured','A','10.1','1079','G','A');
INSERT INTO "nutrition_value" VALUES('usda:900001','protein','per_100g',13.2,'calculated_factor','NC','13.2','1003','G','A');
COMMIT;
