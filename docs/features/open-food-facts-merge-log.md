# Open Food Facts merge log

Written by `tools/openfoodfacts` (`python3 -m almanac_off build`); do not edit by hand.
Export: `en.openfoodfacts.org.products.csv.gz`, SHA-256 `f72687ee8bc6522054fe69dbfda6b91902c16af1ec2e043cde27bc6c29ad8176`.

Rule (owner, 2026-10-19): one record per real product. Same barcode without leading zeros is **same**; same brand and name with nutrition within 10 % (or 1 unit) is **same**; same brand, names overlapping 0.75 or more, matching nutrition is **unsure** and merged too. Every member's barcode and values are kept; disagreements keep both values and are listed under Conflicts. The record shows its most recently edited member.

| | Count |
|---|---:|
| Gulf products in the export | 33938 |
| excluded (see below) | 30390 |
| records shipped | 3514 |
| records with more than one member | 29 |
| merges, same | 22 |
| merges, unsure | 12 |
| records with a conflict | 9 |

## Excluded

| Reason | Products |
|---|---:|
| no energy | 26924 |
| no name | 3416 |
| no proteins_100g | 19 |
| energy above 900 kcal | 14 |
| no fat_100g | 5 |
| no carbohydrates_100g | 4 |
| proteins_100g above 100 g | 2 |
| fat_100g above 100 g | 2 |
| carbohydrates_100g above 100 g | 1 |
| protein + fat + carbohydrate is 107.21 g per 100 | 1 |
| protein + fat + carbohydrate is 114.27 g per 100 | 1 |
| protein + fat + carbohydrate is 106.4 g per 100 | 1 |

## Conflicts

| Record | Field | Values (barcodes) |
|---|---|---|
| `off:0012000051692` Mountain Dew | energy_kcal | 47 (0012000052590); 48 (0012000051692, 0012000002977) |
| `off:0269040016208` Beef Dry Wors | carbohydrate_available | 11 (0269040016208); 11.11 (0268843017658) |
| `off:0269040016208` Beef Dry Wors | energy_kcal | 308 (0269040016208); 308.33 (0268843017658) |
| `off:0269040016208` Beef Dry Wors | fat_total | 4.44 (0268843017658); 4.5 (0269040016208) |
| `off:0269040016208` Beef Dry Wors | protein | 52.78 (0268843017658); 54 (0269040016208) |
| `off:0628011283092` organic overnight muesli | energy_kcal | 388.89 (0628011283085); 400 (0628011283092) |
| `off:0628011283092` organic overnight muesli | fat_total | 12.22 (0628011283085); 13.33 (0628011283092) |
| `off:0628011283092` organic overnight muesli | fibre_total_dietary | 12.22 (0628011283085); 13.33 (0628011283092) |
| `off:0628678203501` goodprotein All-in-One Shake | energy_kcal | 386.36 (0628678203501, 0628678203655); 395.35 (0628678203617) |
| `off:3451790196447` La Crème Entière Liquide 35% MG | carbohydrate_available | 2.9 (30028777); 3.3 (3451790196447) |
| `off:3451790196447` La Crème Entière Liquide 35% MG | energy_kcal | 335 (30028777); 337 (3451790196447) |
| `off:3451790196447` La Crème Entière Liquide 35% MG | protein | 2.1 (30028777); 2.2 (3451790196447) |
| `off:6281007070058` Almarai fresh milk full fat | carbohydrate_available | 4.8 (6281007070058); 5.12 (6281007032261) |
| `off:6281007070058` Almarai fresh milk full fat | energy_kcal | 60.8 (6281007070058); 62 (6281007032261) |
| `off:6281007070058` Almarai fresh milk full fat | fat_total | 3.2 (6281007070058); 3.28 (6281007032261) |
| `off:6281007070058` Almarai fresh milk full fat | protein | 3.04 (6281007032261); 3.12 (6281007070058) |
| `off:6281050707666` Chicken Breast Fillet | fat_total | 5 (6281050707666); 6 (6281050130518) |
| `off:6300900234197` Fresh Yoghurt (Full Fat) | carbohydrate_available | 5.8 (6300900234197); 6 (6291107050362) |
| `off:6300900234197` Fresh Yoghurt (Full Fat) | energy_kcal | 65 (6300900234197); 67 (6291107050362) |
| `off:6300900234197` Fresh Yoghurt (Full Fat) | protein | 3.7 (6300900234197); 4 (6291107050362) |
| `off:80177173` nutella | energy_kcal | 533 (8000500193389); 539 (80177173) |

## Merges

| Record | Members | How |
|---|---|---|
| `off:0012000004070` | `0012000004070` Pepsi<br>`0012000057212` Pepsi | same: brand + name + nutrition |
| `off:0012000051692` | `0012000051692` Mountain Dew<br>`0012000052590` Mountain dew<br>`0012000002977` Mountain dew | same: brand + name + nutrition<br>same: brand + name + nutrition |
| `off:0098000010112` | `0098000010112` Lipton tropical passionfruit and mango ice tea<br>`0098000010099` Tropical Passionfruit & Mango Ice Tea | unsure: brand + name overlap 0.83 + nutrition |
| `off:0269040016208` | `0269040016208` Beef Dry Wors<br>`0268843017658` Beef Dry Wors | same: brand + name + nutrition |
| `off:0628011283092` | `0628011283092` organic overnight muesli<br>`0628011283085` organic overnight muesli | same: brand + name + nutrition |
| `off:0628678203501` | `0628678203501` goodprotein All-in-One Shake<br>`0628678203655` All-in-One Shake<br>`0628678203617` All-in-One Shake | unsure: brand + name overlap 0.75 + nutrition<br>unsure: brand + name overlap 0.75 + nutrition |
| `off:0628678203679` | `0628678203679` All-in-One Shake<br>`0628678203518` All-in-One Shake | same: brand + name + nutrition |
| `off:0684500704523` | `0684500704523` Premium Fava Beans<br>`0032894075116` Premium fava beans | same: brand + name + nutrition |
| `off:0818094006965` | `0818094006965` Rockstar energy drink original<br>`0818094006972` Rockstar energy drink original | same: brand + name + nutrition |
| `off:3073781157031` | `3073781157031` La vache qui rit creamy taste<br>`3073781157048` La vache qui rit creamy taste | same: brand + name + nutrition |
| `off:3451790196447` | `3451790196447` La Crème Entière Liquide 35% MG<br>`30028777` La Crème Entière 35% MG | unsure: brand + name overlap 0.83 + nutrition |
| `off:3451790833212` | `3451790833212` Lait Bio demi-écrémé stérilisé UHT - Longue conservation<br>`3451790930058` Lait demi-écrémé stérilisé UHT - Longue conservation<br>`3451791340412` Lait demi-écrémé stérilisé UHT - Longue conservation | unsure: brand + name overlap 0.88 + nutrition<br>unsure: brand + name overlap 0.88 + nutrition |
| `off:54492004` | `54492004` Cocacola original taste<br>`5449000043382` Cocacola original taste | same: brand + name + nutrition |
| `off:54492820` | `54492820` Cocacola light<br>`5449000043399` Cocacola light | same: brand + name + nutrition |
| `off:5740900404700` | `5740900404700` Unsalted Butter<br>`5740900864405` Butter (Unsalted) | same: brand + name + nutrition |
| `off:6073000051727` | `6073000051727` مزون أب<br>`6073000050171` مزون أب | same: brand + name + nutrition |
| `off:6221134031225` | `6221134031225` Galaxy jewels<br>`6221134009453` Galaxy jewels | same: brand + name + nutrition |
| `off:6260418702420` | `6260418702420` Cerelac Wheat<br>`6260418702451` Cerelac Wheat | same: brand + name + nutrition |
| `off:6281007034043` | `6281007034043` المراعي حليب<br>`6281007120807` حليب المراعي<br>`6281007120401` المراعي حليب | same: brand + name + nutrition<br>same: brand + name + nutrition |
| `off:6281007070058` | `6281007070058` Almarai fresh milk full fat<br>`6281007032261` Almarai milk full fat | unsure: brand + name overlap 0.80 + nutrition |
| `off:6281007168205` | `6281007168205` Almarai cheddar cheese full fat<br>`6281007167826` Almarai cheddar cheese full fat | same: brand + name + nutrition |
| `off:6281014800419` | `6281014800419` Goody original light meat tuna in sunflower oil<br>`6281014800426` Goody original light meat tuna in sunflower oil | same: brand + name + nutrition |
| `off:6281050707666` | `6281050707666` Chicken Breast Fillet<br>`6281050130518` Zingz Chicken Breast Fillet | unsure: brand + name overlap 0.75 + nutrition |
| `off:6281063453499` | `6281063453499` Freshly chili flavor cooking spray non stick<br>`6281063453475` Freshly lemon flavor cooking spray non stick | unsure: brand + name overlap 0.75 + nutrition |
| `off:6287034101130` | `6287034101130` Kinza zero sugar<br>`6287034101055` Kinza lemon zero sugar | unsure: brand + name overlap 0.75 + nutrition |
| `off:6291052000252` | `6291052000252` frozen chicken breast<br>`6291052005462` Frozen Tender Chicken Breast | unsure: brand + name overlap 0.75 + nutrition |
| `off:6298044151770` | `6298044151770` protein gummies<br>`6298044151787` Protein Gummies<br>`6298044151794` protein gummies | same: brand + name + nutrition<br>same: brand + name + nutrition |
| `off:6300900234197` | `6300900234197` Fresh Yoghurt (Full Fat)<br>`6291107050362` Fresh Yoghurt (Full Fat) (Discontinued) | unsure: brand + name overlap 0.80 + nutrition |
| `off:80177173` | `80177173` nutella<br>`8000500193389` Nutella | same: brand + name + nutrition |
