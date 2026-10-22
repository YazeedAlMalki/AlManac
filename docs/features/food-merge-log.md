# Food merge log

Written by `python3 -m almanac_nutrition merge`; do not edit by hand. Bundle: `almanac.sqlite` sha256 `a3c57b806f12`.

Rule (owner, 2026-10-19): one record per real food across every source. Foods are matched on USDA's own codes (**code**: a Foundation and an SR Legacy food with one NDB number, an FNDDS food whose only ingredient is an SR Legacy food), on equal normalised English names (**same**), or on names that differ only by words naming nothing about the food (*all*, *average*, *commercial*, *fresh*, *generic*, *mean*, *plain*, *regular*, *standard*, *type*, *typical*, *variety*) and whose nutrient profiles agree (**unsure**; energy within 25 kcal or 12 %, protein, fat and carbohydrate within 1.5–2 g or 15 %, per 100 g). Every member keeps its own rows and licence; the search shows the record (USDA first, then CoFID, CIQUAL). Almanac's own dishes are never merged.

| | Count |
|---|---:|
| foods read (almanac: excluded) | 19991 |
| records with more than one source row | 1359 |
| foods merged into another food's record | 1993 |
| matches: code | 1613 |
| matches: same name | 342 |
| matches: unsure | 38 |
| records with a conflict | 156 |

## Conflicts

Members whose values differ by more than the tolerance. Both values are kept, each on its own source's row; nothing is picked. Carbohydrate is compared as a total (by difference, or available plus fibre) and is not a stored value.

| Record | Nutrient | Values per 100 g |
|---|---|---|
| `usda:171978` Mollusks, oyster, eastern, wild, raw | protein | 8.64 (`ciqual:10011`); 10.8 (`cofid:16-260`); 5.71 (`usda:171978`); 5.71 (`usda:2706351`); 7.23 (`usda:2706353`) |
| `usda:174214` Mollusks, clam, mixed species, raw | energy_kcal | 80.5 (`ciqual:10017`); 86 (`usda:174214`); 86 (`usda:2706338`); 109 (`usda:2706342`); 108 (`usda:2706343`) |
| `usda:174214` Mollusks, clam, mixed species, raw | protein | 11.5 (`ciqual:10017`); 14.67 (`usda:174214`); 14.67 (`usda:2706338`); 18.57 (`usda:2706342`); 18.34 (`usda:2706343`) |
| `usda:174214` Mollusks, clam, mixed species, raw | fat_total | 2.65 (`ciqual:10017`); 0.96 (`usda:174214`); 0.96 (`usda:2706338`); 1.22 (`usda:2706342`); 1.2 (`usda:2706343`) |
| `usda:174815` Alcoholic beverage, distilled, all (gin, rum, vodka, whiskey) 80 proof | energy_kcal | 265 (`ciqual:1002`); 234 (`ciqual:1004`); 250 (`ciqual:1008`); 231 (`usda:174815`); 231 (`usda:2710699`); 231 (`usda:2710700`); 231 (`usda:2710701`); 231 (`usda:2710702`); 231 (`usda:2710703`); 231 (`usda:2710704`); 231 (`usda:2710705`) |
| `usda:2710623` Liqueur | energy_kcal | 225 (`ciqual:1003`); 279 (`usda:2710623`) |
| `usda:2710623` Liqueur | carbohydrate | 25.4 (`ciqual:1003`); 33.2 (`usda:2710623`) |
| `usda:174206` Crustaceans, crayfish, mixed species, wild, raw | protein | 16.3 (`ciqual:10031`); 15.97 (`usda:174206`); 20.22 (`usda:2706348`) |
| `cofid:13-811` Chervil, dried | energy_kcal | 302 (`ciqual:10999`); 237 (`cofid:13-811`) |
| `usda:1104647` Garlic, raw | energy_kcal | 109 (`ciqual:11000`); 98 (`cofid:13-244`); 143 (`usda:1104647`); 149 (`usda:169230`); 143 (`usda:2709786`) |
| `usda:1104647` Garlic, raw | protein | 5.31 (`ciqual:11000`); 7.9 (`cofid:13-244`); 6.62 (`usda:1104647`); 6.36 (`usda:169230`); 6.62 (`usda:2709786`) |
| `usda:1104647` Garlic, raw | carbohydrate | 24.4 (`ciqual:11000`); 28.2 (`usda:1104647`); 33.06 (`usda:169230`); 28.2 (`usda:2709786`) |
| `usda:326698` Mustard, prepared, yellow | energy_kcal | 151 (`ciqual:11013`); 60 (`usda:172234`); 69 (`usda:2710085`); 61 (`usda:326698`) |
| `usda:326698` Mustard, prepared, yellow | protein | 6.92 (`ciqual:11013`); 3.74 (`usda:172234`); 4.25 (`usda:2710085`); 4.25 (`usda:326698`) |
| `usda:326698` Mustard, prepared, yellow | fat_total | 11.2 (`ciqual:11013`); 3.34 (`usda:172234`); 3.38 (`usda:2710085`); 3.38 (`usda:326698`) |
| `usda:170416` Parsley, fresh | carbohydrate | 8.4 (`ciqual:11014`); 6.33 (`usda:170416`); 6.33 (`usda:2709796`) |
| `cofid:13-845` Parsley, dried | energy_kcal | 291 (`ciqual:11024`); 181 (`cofid:13-845`) |
| `cofid:13-845` Parsley, dried | protein | 29 (`ciqual:11024`); 15.8 (`cofid:13-845`) |
| `cofid:13-845` Parsley, dried | fat_total | 5.34 (`ciqual:11024`); 7 (`cofid:13-845`) |
| `cofid:13-837` Mint, dried | protein | 19.9 (`ciqual:11029`); 24.8 (`cofid:13-837`) |
| `usda:172232` Basil, fresh | carbohydrate | 5 (`ciqual:11033`); 2.65 (`usda:172232`); 2.65 (`usda:2709780`) |
| `cofid:13-882` Rosemary, dried | carbohydrate | 64.1 (`ciqual:11036`); 86.79 (`cofid:13-882`) |
| `cofid:13-825` Dill, dried | energy_kcal | 315 (`ciqual:11063`); 253 (`cofid:13-825`) |
| `usda:173473` Rosemary, fresh | energy_kcal | 121 (`ciqual:11068`); 99 (`cofid:13-892`); 131 (`usda:173473`) |
| `usda:173473` Rosemary, fresh | protein | 3.31 (`ciqual:11068`); 1.4 (`cofid:13-892`); 3.31 (`usda:173473`) |
| `usda:173473` Rosemary, fresh | carbohydrate | 20.7 (`ciqual:11068`); 25.257 (`cofid:13-892`); 20.7 (`usda:173473`) |
| `cofid:13-853` Sage, fresh | energy_kcal | 34.9 (`ciqual:11069`); 119 (`cofid:13-853`) |
| `cofid:13-853` Sage, fresh | fat_total | 0.5 (`ciqual:11069`); 4.6 (`cofid:13-853`) |
| `usda:173470` Thyme, fresh | protein | 5.56 (`ciqual:11070`); 3 (`cofid:13-893`); 5.56 (`usda:173470`) |
| `usda:2710177` Sauce, NFS | energy_kcal | 246 (`ciqual:11184`); 109 (`usda:2710177`) |
| `usda:2710177` Sauce, NFS | fat_total | 23.3 (`ciqual:11184`); 5.67 (`usda:2710177`) |
| `usda:2710177` Sauce, NFS | carbohydrate | 7.92 (`ciqual:11184`); 12.72 (`usda:2710177`) |
| `usda:167717` Yeast extract spread | protein | 42.4 (`ciqual:11221`); 23.88 (`usda:167717`); 23.88 (`usda:2710006`) |
| `usda:2705704` Cheese, NFS | energy_kcal | 324 (`ciqual:12999`); 381 (`usda:2705704`) |
| `usda:2705704` Cheese, NFS | fat_total | 26.3 (`ciqual:12999`); 31.26 (`usda:2705704`) |
| `usda:2705704` Cheese, NFS | carbohydrate | 0.725 (`ciqual:12999`); 4.33 (`usda:2705704`) |
| `usda:2346409` Strawberries, raw | carbohydrate | 9.83 (`ciqual:13014`); 9.61 (`cofid:14-324`); 7.68 (`usda:167762`); 7.964 (`usda:2346409`); 7.96 (`usda:2709283`) |
| `usda:2346410` Raspberries, raw | energy_kcal | 47.9 (`ciqual:13015`); 25 (`cofid:14-375`); 52 (`usda:167755`); 51.4124 (`usda:2346410`); 57 (`usda:2709281`); 57 (`usda:2709282`) |
| `usda:2346410` Raspberries, raw | carbohydrate | 10.13 (`ciqual:13015`); 8.557 (`cofid:14-375`); 11.94 (`usda:167755`); 12.904 (`usda:2346410`); 12.9 (`usda:2709281`); 12.9 (`usda:2709282`) |
| `usda:2727581` Blackberries, raw | carbohydrate | 11.73 (`ciqual:13029`); 8.733 (`cofid:14-388`); 9.61 (`usda:173946`); 9.61 (`usda:2709273`) |
| `ciqual:13161` Dairy and cereal-based beverage for baby's dinner, with vegetables, from 4/6 months | fat_total | 2.83 (`ciqual:13161`); 8.93 (`ciqual:13172`) |
| `ciqual:13161` Dairy and cereal-based beverage for baby's dinner, with vegetables, from 4/6 months | carbohydrate | 12.5 (`ciqual:13161`); 25.05 (`ciqual:13172`) |
| `usda:173032` Goji berries, dried | energy_kcal | 300 (`ciqual:13183`); 349 (`usda:173032`) |
| `usda:173032` Goji berries, dried | protein | 12.1 (`ciqual:13183`); 14.26 (`usda:173032`) |
| `usda:173032` Goji berries, dried | fat_total | 2.9 (`ciqual:13183`); 0.39 (`usda:173032`) |
| `usda:173032` Goji berries, dried | carbohydrate | 60.8 (`ciqual:13183`); 77.06 (`usda:173032`) |
| `usda:169094` Olives, ripe, canned (small-extra large) | energy_kcal | 165 (`ciqual:13184`); 116 (`usda:169094`); 116 (`usda:2710088`); 116 (`usda:2710090`) |
| `usda:169094` Olives, ripe, canned (small-extra large) | fat_total | 16.6 (`ciqual:13184`); 10.9 (`usda:169094`); 10.9 (`usda:2710088`); 10.9 (`usda:2710090`) |
| `usda:169412` Seeds, sesame seed kernels, dried (decorticated) | fat_total | 49.7 (`ciqual:15010`); 58 (`cofid:14-844`); 61.21 (`usda:169412`); 61.21 (`usda:2707586`) |
| `usda:169412` Seeds, sesame seed kernels, dried (decorticated) | carbohydrate | 24.6 (`ciqual:15010`); 11.73 (`usda:169412`); 11.73 (`usda:2707586`) |
| `usda:2346392` Nuts, pine nuts, raw | carbohydrate | 12.93 (`ciqual:15025`); 13.08 (`usda:170591`); 18.592 (`usda:2346392`); 13.08 (`usda:2707526`) |
| `usda:2262075` Flaxseed, ground | carbohydrate | 30.89 (`ciqual:15034`); 28.88 (`usda:169414`); 34.355 (`usda:2262075`); 34.36 (`usda:2707588`) |
| `cofid:17-158` Coffee, powder, instant | energy_kcal | 291 (`ciqual:18005`); 75 (`cofid:17-158`) |
| `cofid:17-158` Coffee, powder, instant | protein | 18.5 (`ciqual:18005`); 14.6 (`cofid:17-158`) |
| `cofid:17-158` Coffee, powder, instant | carbohydrate | 61.9 (`ciqual:18005`); 4.286 (`cofid:17-158`) |
| `usda:174116` Beverages, coconut milk, sweetened, fortified with calcium, vitamins A, B12, D2 | energy_kcal | 199 (`ciqual:18041`); 22 (`cofid:14-820`); 31 (`usda:174116`); 31 (`usda:2705413`) |
| `usda:174116` Beverages, coconut milk, sweetened, fortified with calcium, vitamins A, B12, D2 | protein | 1.94 (`ciqual:18041`); 0.3 (`cofid:14-820`); 0.21 (`usda:174116`); 0.21 (`usda:2705413`) |
| `usda:174116` Beverages, coconut milk, sweetened, fortified with calcium, vitamins A, B12, D2 | fat_total | 19.2 (`ciqual:18041`); 0.3 (`cofid:14-820`); 2.08 (`usda:174116`); 2.08 (`usda:2705413`) |
| `usda:174116` Beverages, coconut milk, sweetened, fortified with calcium, vitamins A, B12, D2 | carbohydrate | 5.04 (`ciqual:18041`); 2.92 (`usda:174116`); 2.92 (`usda:2705413`) |
| `cofid:12-555` Yogurt, Greek style, plain | energy_kcal | 103 (`ciqual:19860`); 133 (`cofid:12-555`) |
| `cofid:12-555` Yogurt, Greek style, plain | protein | 3.02 (`ciqual:19860`); 5.7 (`cofid:12-555`) |
| `cofid:12-555` Yogurt, Greek style, plain | fat_total | 8.16 (`ciqual:19860`); 10.2 (`cofid:12-555`) |
| `usda:2258586` Carrots, mature, raw | carbohydrate | 8.06 (`ciqual:20009`); 9.58 (`usda:170393`); 10.268 (`usda:2258586`); 9.68 (`usda:2709660`); 10.7 (`usda:2710793`) |
| `usda:2710002` Turnip, cooked | energy_kcal | 25 (`ciqual:20033`); 54 (`usda:2710002`) |
| `usda:2710002` Turnip, cooked | fat_total | 0.2 (`ciqual:20033`); 2.84 (`usda:2710002`) |
| `usda:170000` Onions, raw | carbohydrate | 7.95 (`ciqual:20034`); 9.819 (`cofid:13-499`); 9.34 (`usda:170000`); 8.46 (`usda:2709795`); 10.99 (`usda:2710796`) |
| `usda:168448` Pumpkin, raw | carbohydrate | 4 (`ciqual:20044`); 6.5 (`usda:168448`); 6.5 (`usda:2709693`) |
| `usda:2709981` Salsify, cooked | fat_total | 0.17 (`ciqual:20046`); 2.71 (`usda:2709981`) |
| `cofid:13-153` Artichoke, globe, raw | energy_kcal | 45.4 (`ciqual:20052`); 18 (`cofid:13-153`) |
| `usda:1999633` Spinach, mature | carbohydrate | 5.66 (`ciqual:20059`); 3.63 (`usda:168462`); 2.641 (`usda:1999633`); 2.41 (`usda:2709614`); 3.11 (`usda:2710791`) |
| `usda:2709692` Pumpkin, cooked | energy_kcal | 26.1 (`ciqual:20096`); 52 (`usda:2709692`) |
| `usda:2709692` Pumpkin, cooked | fat_total | 0.07 (`ciqual:20096`); 2.84 (`usda:2709692`) |
| `usda:170499` Shallots, raw | energy_kcal | 61.7 (`ciqual:20097`); 20 (`cofid:13-342`); 72 (`usda:170499`) |
| `cofid:13-519` Tomatoes, cherry, raw | carbohydrate | 6.82 (`ciqual:20172`); 4.729 (`cofid:13-519`) |
| `usda:174272` Tempeh | energy_kcal | 157 (`ciqual:20917`); 166 (`cofid:13-118`); 192 (`usda:174272`) |
| `usda:174272` Tempeh | protein | 16.1 (`ciqual:20917`); 20.7 (`cofid:13-118`); 20.29 (`usda:174272`) |
| `usda:174272` Tempeh | fat_total | 4.7 (`ciqual:20917`); 6.4 (`cofid:13-118`); 10.8 (`usda:174272`) |
| `usda:174272` Tempeh | carbohydrate | 14.09 (`ciqual:20917`); 7.64 (`usda:174272`) |
| `cofid:12-946` Omelette, plain, homemade | protein | 13.8 (`ciqual:22500`); 10.9 (`cofid:12-946`) |
| `usda:2709342` Banana nectar | carbohydrate | 13.31 (`ciqual:2366`); 18.01 (`usda:2709342`) |
| `usda:168210` Guava nectar, with sucralose, canned | carbohydrate | 11.05 (`ciqual:2367`); 13.3 (`usda:168210`); 13.3 (`usda:2709344`) |
| `usda:2707297` Meringues | energy_kcal | 396 (`ciqual:24520`); 324 (`usda:2707297`) |
| `usda:2707297` Meringues | protein | 4.82 (`ciqual:24520`); 7.17 (`usda:2707297`) |
| `usda:2707297` Meringues | carbohydrate | 93.45 (`ciqual:24520`); 75.34 (`usda:2707297`) |
| `usda:2705792` Cheese souffle | fat_total | 13.4 (`ciqual:25020`); 16.01 (`usda:2705792`) |
| `usda:2709144` Soup, NFS | protein | 1.42 (`ciqual:25969`); 3.51 (`usda:2709144`) |
| `cofid:16-416` Tuna, canned in brine, drained | energy_kcal | 143 (`ciqual:26039`); 109 (`cofid:16-416`) |
| `cofid:16-416` Tuna, canned in brine, drained | fat_total | 3.94 (`ciqual:26039`); 1 (`cofid:16-416`) |
| `cofid:16-142` Shark, raw | fat_total | 2.91 (`ciqual:26162`); 1.1 (`cofid:16-142`) |
| `ciqual:30150` Merguez sausage, raw | energy_kcal | 301 (`ciqual:30150`); 381 (`ciqual:30151`) |
| `ciqual:30150` Merguez sausage, raw | fat_total | 26.8 (`ciqual:30150`); 36.3 (`ciqual:30151`) |
| `cofid:19-106` Liver sausage | energy_kcal | 374 (`ciqual:30176`); 226 (`cofid:19-106`) |
| `cofid:19-106` Liver sausage | fat_total | 35.9 (`ciqual:30176`); 16.7 (`cofid:19-106`) |
| `usda:174582` Salami, dry or hard, pork, beef | energy_kcal | 457 (`ciqual:30350`); 438 (`cofid:19-517`); 378 (`usda:174582`); 378 (`usda:2706186`); 378 (`usda:2706195`) |
| `usda:174582` Salami, dry or hard, pork, beef | protein | 17.7 (`ciqual:30350`); 20.9 (`cofid:19-517`); 21.07 (`usda:174582`); 21.07 (`usda:2706186`); 21.07 (`usda:2706195`) |
| `usda:174582` Salami, dry or hard, pork, beef | fat_total | 41.8 (`ciqual:30350`); 39.2 (`cofid:19-517`); 31.65 (`usda:174582`); 31.65 (`usda:2706186`); 31.65 (`usda:2706195`) |
| `usda:174573` Mortadella, beef, pork | carbohydrate | 0.69 (`ciqual:30789`); 2.53 (`ciqual:30791`); 3.05 (`usda:174573`); 3.05 (`usda:2706182`) |
| `usda:169640` Honey | energy_kcal | 331 (`ciqual:31008`); 288 (`cofid:17-050`); 304 (`usda:169640`); 304 (`usda:2710281`) |
| `usda:2705641` Ice cream bar, chocolate | carbohydrate | 38.36 (`ciqual:31035`); 25.17 (`usda:2705641`) |
| `usda:169882` Chewing gum, sugarless | energy_kcal | 206 (`ciqual:31054`); 268 (`usda:169882`); 268 (`usda:2710372`) |
| `usda:169882` Chewing gum, sugarless | carbohydrate | 77.95 (`ciqual:31054`); 94.8 (`usda:169882`); 94.8 (`usda:2710372`) |
| `usda:2727569` Chicken, breast, meat and skin, raw | energy_kcal | 167 (`ciqual:36029`); 132.836 (`usda:2727569`) |
| `usda:2727569` Chicken, breast, meat and skin, raw | fat_total | 9.25 (`ciqual:36029`); 4.777 (`usda:2727569`) |
| `usda:172418` Quail, meat and skin, raw | energy_kcal | 140 (`ciqual:36100`); 192 (`usda:172418`) |
| `usda:172418` Quail, meat and skin, raw | fat_total | 6.8 (`ciqual:36100`); 12.05 (`usda:172418`) |
| `usda:2708331` French toast, NFS | energy_kcal | 226 (`ciqual:39236`); 273 (`usda:2708331`) |
| `usda:2708331` French toast, NFS | protein | 6 (`ciqual:39236`); 10.36 (`usda:2708331`) |
| `usda:2708331` French toast, NFS | fat_total | 8.45 (`ciqual:39236`); 11.38 (`usda:2708331`) |
| `usda:168105` Frozen yogurts, flavors other than chocolate | carbohydrate | 25.7 (`ciqual:39517`); 21.6 (`usda:168105`); 21.6 (`usda:2705451`); 21.6 (`usda:2705452`); 21.6 (`usda:2705457`) |
| `cofid:18-409` Liver, calf, raw | protein | 15.5 (`ciqual:40106`); 18.3 (`cofid:18-409`) |
| `cofid:18-411` Liver, chicken, raw | fat_total | 4.83 (`ciqual:40111`); 2.3 (`cofid:18-411`) |
| `cofid:18-423` Tongue, lamb, raw | energy_kcal | 167 (`ciqual:40207`); 193 (`cofid:18-423`) |
| `cofid:18-423` Tongue, lamb, raw | fat_total | 10.9 (`ciqual:40207`); 14.6 (`cofid:18-423`) |
| `cofid:18-421` Sweetbread, lamb, raw | fat_total | 9.82 (`ciqual:40302`); 7.8 (`cofid:18-421`) |
| `usda:171908` Alcoholic beverages, wine, rose | carbohydrate | 1.4 (`ciqual:5216`); 3.8 (`usda:171908`); 3.8 (`usda:2710690`) |
| `cofid:18-486` Veal, escalope, raw | fat_total | 3.28 (`ciqual:6521`); 1.7 (`cofid:18-486`) |
| `usda:174915` Bread, pita, white, enriched | protein | 7.48 (`ciqual:7180`); 9.1 (`usda:174915`); 9.1 (`usda:2707616`) |
| `cofid:11-940` Rusks | protein | 10 (`ciqual:7300`); 6.5 (`cofid:11-940`) |
| `cofid:11-940` Rusks | fat_total | 5.43 (`ciqual:7300`); 10.7 (`cofid:11-940`) |
| `usda:174987` Croissants, butter | protein | 6.56 (`ciqual:7603`); 8.3 (`cofid:11-988`); 8.2 (`usda:174987`); 8.2 (`usda:2707678`) |
| `usda:2707682` Brioche | energy_kcal | 363 (`ciqual:7746`); 427 (`usda:2707682`) |
| `usda:2707682` Brioche | fat_total | 13 (`ciqual:7746`); 27.46 (`usda:2707682`) |
| `usda:2707682` Brioche | carbohydrate | 54.04 (`ciqual:7746`); 36.31 (`usda:2707682`) |
| `usda:173904` Cereals, oats, regular and quick, not fortified, dry | protein | 16.9 (`ciqual:9310`); 13.15 (`usda:173904`); 13.15 (`usda:2708489`) |
| `cofid:14-843` Quinoa, raw | energy_kcal | 358 (`ciqual:9340`); 309 (`cofid:14-843`) |
| `usda:169722` Wheat bran, crude | energy_kcal | 270 (`ciqual:9621`); 216 (`usda:169722`); 216 (`usda:2708488`) |
| `usda:2758993` Bread, white, commercial | energy_kcal | 267 (`cofid:11-1001`); 236 (`cofid:11-1145`); 266 (`usda:174924`); 267 (`usda:2707591`); 267 (`usda:2707598`); 293 (`usda:2707599`); 267 (`usda:2707656`); 267 (`usda:2707657`) |
| `usda:2758993` Bread, white, commercial | protein | 9.7 (`cofid:11-1001`); 8.7 (`cofid:11-1145`); 8.85 (`usda:174924`); 9.43 (`usda:2707591`); 9.43 (`usda:2707598`); 10.36 (`usda:2707599`); 9.43 (`usda:2707656`); 9.43 (`usda:2707657`) |
| `usda:2758993` Bread, white, commercial | fat_total | 2 (`cofid:11-1001`); 2.1 (`cofid:11-1145`); 3.33 (`usda:174924`); 3.59 (`usda:2707591`); 3.59 (`usda:2707598`); 3.94 (`usda:2707599`); 3.59 (`usda:2707656`); 3.59 (`usda:2707657`) |
| `usda:2708441` Couscous, plain, cooked | energy_kcal | 178 (`cofid:11-902`); 111 (`usda:2708441`) |
| `usda:2708441` Couscous, plain, cooked | protein | 7.2 (`cofid:11-902`); 3.77 (`usda:2708441`) |
| `usda:2708441` Couscous, plain, cooked | carbohydrate | 37.914 (`cofid:11-902`); 23.11 (`usda:2708441`) |
| `usda:2259793` Yogurt, plain, whole milk | protein | 5.7 (`cofid:12-184`); 3.47 (`usda:171284`); 3.82417 (`usda:2259793`); 3.82 (`usda:2705418`) |
| `usda:2259793` Yogurt, plain, whole milk | carbohydrate | 7.429 (`cofid:12-184`); 4.66 (`usda:171284`); 5.575 (`usda:2259793`); 5.57 (`usda:2705418`) |
| `usda:2705702` Tiramisu | energy_kcal | 244 (`cofid:12-476`); 353 (`usda:2705702`) |
| `usda:2705702` Tiramisu | fat_total | 14 (`cofid:12-476`); 23.86 (`usda:2705702`) |
| `usda:2705740` Cheese, paneer | protein | 26 (`cofid:12-495`); 15.86 (`usda:2705740`) |
| `usda:2705740` Cheese, paneer | fat_total | 24.5 (`cofid:12-495`); 15.52 (`usda:2705740`) |
| `usda:2705740` Cheese, paneer | carbohydrate | 0.857 (`cofid:12-495`); 22.46 (`usda:2705740`) |
| `usda:171276` Milk, canned, evaporated, with added vitamin D and without added vitamin A | energy_kcal | 166 (`cofid:12-522`); 134 (`usda:171276`); 134 (`usda:2705398`); 134 (`usda:2705399`) |
| `usda:171276` Milk, canned, evaporated, with added vitamin D and without added vitamin A | protein | 8.4 (`cofid:12-522`); 6.81 (`usda:171276`); 6.81 (`usda:2705398`); 6.81 (`usda:2705399`) |
| `usda:171276` Milk, canned, evaporated, with added vitamin D and without added vitamin A | fat_total | 9.4 (`cofid:12-522`); 7.56 (`usda:171276`); 7.56 (`usda:2705398`); 7.56 (`usda:2705399`) |
| `usda:171276` Milk, canned, evaporated, with added vitamin D and without added vitamin A | carbohydrate | 12.095 (`cofid:12-522`); 10.04 (`usda:171276`); 10.04 (`usda:2705398`); 10.04 (`usda:2705399`) |
| `usda:2259796` Cheese, feta, whole milk, crumbled | protein | 15.6 (`cofid:12-525`); 14.21 (`usda:173420`); 19.7078 (`usda:2259796`); 19.71 (`usda:2705714`) |
| `usda:2259796` Cheese, feta, whole milk, crumbled | carbohydrate | 1.429 (`cofid:12-525`); 3.88 (`usda:173420`); 5.583 (`usda:2259796`); 5.58 (`usda:2705714`) |
| `usda:168416` Drumstick leaves, raw | protein | 7.4 (`cofid:13-236`); 9.4 (`usda:168416`) |
| `usda:1999627` Mushroom, oyster | energy_kcal | 8 (`cofid:13-293`); 33 (`usda:168580`); 33.3197 (`usda:1999627`) |
| `usda:1999627` Mushroom, oyster | protein | 1.6 (`cofid:13-293`); 3.31 (`usda:168580`); 2.89875 (`usda:1999627`) |
| `usda:2709982` Sauerkraut | energy_kcal | 9 (`cofid:13-336`); 40 (`usda:2709982`) |
| `usda:1999629` Mushrooms, white button | protein | 1 (`cofid:13-505`); 3.09 (`usda:169251`); 2.89062 (`usda:1999629`) |
| `usda:1999629` Mushrooms, white button | carbohydrate | 0.986 (`cofid:13-505`); 3.26 (`usda:169251`); 4.079 (`usda:1999629`) |
| `usda:2346407` Cabbage, green, raw | carbohydrate | 8.005 (`cofid:13-510`); 7.69 (`cofid:13-582`); 5.8 (`usda:169975`); 6.384 (`usda:2346407`); 6.38 (`usda:2709773`); 6.65 (`usda:2710800`) |
| `usda:173941` Apricots, dried, sulfured, uncooked | energy_kcal | 188 (`cofid:14-031`); 241 (`usda:173941`); 241 (`usda:2709197`) |
| `usda:169121` Pears, dried, sulfured, uncooked | energy_kcal | 207 (`cofid:14-196`); 262 (`usda:169121`); 262 (`usda:2709208`) |
| `usda:2709210` Pineapple, dried | energy_kcal | 303 (`cofid:14-396`); 347 (`usda:2709210`) |
| `usda:2709210` Pineapple, dried | protein | 3.3 (`cofid:14-396`); 1.22 (`usda:2709210`) |
| `usda:170557` Seeds, pumpkin and squash seed kernels, roasted, without salt | protein | 24.4 (`cofid:14-842`); 29.84 (`usda:170557`); 29.84 (`usda:2707579`); 29.84 (`usda:2707581`) |
| `usda:2707574` Trail mix, NFS | protein | 9.1 (`cofid:14-849`); 10.9 (`usda:2707574`) |
| `usda:2707574` Trail mix, NFS | carbohydrate | 40.529 (`cofid:14-849`); 51.06 (`usda:2707574`) |
| `cofid:15-776` Curry, pea and potato, homemade | energy_kcal | 147 (`cofid:15-776`); 92 (`cofid:15-781`) |
| `cofid:15-776` Curry, pea and potato, homemade | fat_total | 11 (`cofid:15-776`); 3.7 (`cofid:15-781`) |
| `cofid:15-776` Curry, pea and potato, homemade | carbohydrate | 12.514 (`cofid:15-776`); 15.481 (`cofid:15-781`) |
| `cofid:16-127` Red snapper, flesh only, fried in blended oil, weighed with bones and skin | energy_kcal | 126 (`cofid:16-127`); 64 (`cofid:16-128`) |
| `cofid:16-127` Red snapper, flesh only, fried in blended oil, weighed with bones and skin | protein | 24.5 (`cofid:16-127`); 12.5 (`cofid:16-128`) |
| `usda:171972` Crustaceans, shrimp, mixed species, canned | energy_kcal | 245 (`cofid:16-249`); 100 (`usda:171972`); 250 (`usda:2706366`); 100 (`usda:2706367`) |
| `usda:171972` Crustaceans, shrimp, mixed species, canned | protein | 55.8 (`cofid:16-249`); 20.42 (`usda:171972`); 51.05 (`usda:2706366`); 20.42 (`usda:2706367`) |
| `usda:171972` Crustaceans, shrimp, mixed species, canned | fat_total | 2.4 (`cofid:16-249`); 1.36 (`usda:171972`); 3.4 (`usda:2706366`); 1.36 (`usda:2706367`) |
| `usda:171833` Sauce, horseradish | energy_kcal | 153 (`cofid:17-314`); 503 (`usda:171833`); 503 (`usda:2710174`) |
| `usda:171833` Sauce, horseradish | fat_total | 8.4 (`cofid:17-314`); 50.89 (`usda:171833`); 50.89 (`usda:2710174`) |
| `usda:171833` Sauce, horseradish | carbohydrate | 19.548 (`cofid:17-314`); 10.05 (`usda:171833`); 10.05 (`usda:2710174`) |
| `usda:174523` Sauce, barbecue | energy_kcal | 140 (`cofid:17-705`); 172 (`usda:174523`); 172 (`usda:2709750`) |
| `usda:169378` Pickles, cucumber, sweet (includes bread and butter pickles) | carbohydrate | 27.867 (`cofid:17-718`); 21.15 (`usda:169378`); 21.15 (`usda:2710080`) |
| `usda:171610` Sauce, worcestershire | energy_kcal | 113 (`cofid:17-723`); 77 (`usda:171610`); 77 (`usda:2707447`) |
| `cofid:18-470` Beef, mince, stewed | energy_kcal | 209 (`cofid:18-470`); 139 (`cofid:19-607`) |
| `cofid:18-470` Beef, mince, stewed | protein | 21.8 (`cofid:18-470`); 10.9 (`cofid:19-607`) |
| `cofid:18-470` Beef, mince, stewed | fat_total | 13.5 (`cofid:18-470`); 9.9 (`cofid:19-607`) |
| `cofid:18-470` Beef, mince, stewed | carbohydrate | 0 (`cofid:18-470`); 2.681 (`cofid:19-607`) |
| `usda:2706179` Chorizo | energy_kcal | 395 (`cofid:19-516`); 341 (`usda:2706179`) |
| `usda:2706179` Chorizo | protein | 24 (`cofid:19-516`); 19.3 (`usda:2706179`) |
| `usda:1104705` Flour, soy, defatted | fat_total | 3.33 (`usda:1104705`); 1.22 (`usda:174275`); 3.33 (`usda:2707451`) |
| `usda:167533` Bagels, wheat | fat_total | 1.53 (`usda:167533`); 1.24 (`usda:171852`); 1.2 (`usda:172666`); 0 (`usda:174092`); 1.53 (`usda:2707708`); 1.53 (`usda:2707732`); 1.53 (`usda:2707733`); 1.53 (`usda:2707737`); 1.53 (`usda:2707762`); 1.53 (`usda:2707772`); 1.53 (`usda:2707785`) |
| `usda:167585` Ice creams, chocolate, light | energy_kcal | 187 (`usda:167585`); 222 (`usda:173465`); 187 (`usda:2705635`) |
| `usda:167585` Ice creams, chocolate, light | fat_total | 7.19 (`usda:167585`); 13 (`usda:173465`); 7.19 (`usda:2705635`) |
| `usda:2514745` Pork, ground, raw | fat_total | 21.19 (`usda:167902`); 17.49 (`usda:2514745`) |
| `usda:167974` Candies, caramels | fat_total | 8.1 (`usda:167974`); 5.7 (`usda:2710354`) |
| `usda:2003594` Cranberry juice, not fortified, from concentrate, shelf stable | carbohydrate | 12.2 (`usda:168117`); 7.264 (`usda:2003594`); 7.26 (`usda:2709324`) |
| `usda:168126` Rolls, pumpernickel | protein | 10.8 (`usda:168126`); 8.7 (`usda:174918`); 8.7 (`usda:2707760`); 9.56 (`usda:2707761`); 8.7 (`usda:2707763`); 8.7 (`usda:2707764`); 9.56 (`usda:2707765`); 8.7 (`usda:2707767`) |
| `usda:323294` Nuts, almonds, dry roasted, with salt added | carbohydrate | 21.01 (`usda:168596`); 16.2 (`usda:323294`) |
| `usda:790146` Flour, bread, white, enriched, unbleached | protein | 11.98 (`usda:168896`); 14.3 (`usda:790146`) |
| `usda:789951` Flour, wheat, all-purpose, enriched, unbleached | protein | 10.33 (`usda:168936`); 13.1 (`usda:789951`) |
| `usda:169078` Cheese, cottage, with vegetables | fat_total | 4.2 (`usda:169078`); 1.98 (`usda:2705752`) |
| `usda:169078` Cheese, cottage, with vegetables | carbohydrate | 3 (`usda:169078`); 5.63 (`usda:2705752`) |
| `usda:169392` Broccoli, chinese, cooked | energy_kcal | 22 (`usda:169392`); 50 (`usda:2709658`) |
| `usda:169392` Broccoli, chinese, cooked | fat_total | 0.72 (`usda:169392`); 3.42 (`usda:2709658`) |
| `usda:325524` Seeds, sunflower seed kernels, dry roasted, with salt added | carbohydrate | 24.07 (`usda:169418`); 17.1 (`usda:325524`) |
| `usda:2346396` Oats, whole grain, rolled, old fashioned | protein | 16.89 (`usda:169705`); 13.4964 (`usda:2346396`) |
| `usda:2512376` Flour, barley | protein | 10.5 (`usda:169739`); 8.72168 (`usda:2512376`) |
| `usda:169773` Potsticker or wonton, pork and vegetable, frozen, unprepared | carbohydrate | 13.28 (`usda:169773`); 11.07 (`usda:2708708`) |
| `usda:170067` Waterchestnuts, chinese, canned, solids and liquids | energy_kcal | 50 (`usda:170067`); 78 (`usda:2710003`) |
| `usda:170067` Waterchestnuts, chinese, canned, solids and liquids | carbohydrate | 12.3 (`usda:170067`); 19.22 (`usda:2710003`) |
| `usda:170092` Potato pancakes | energy_kcal | 268 (`usda:170092`); 196 (`usda:2709552`) |
| `usda:170092` Potato pancakes | protein | 6.08 (`usda:170092`); 4.47 (`usda:2709552`) |
| `usda:170092` Potato pancakes | fat_total | 14.76 (`usda:170092`); 10.8 (`usda:2709552`) |
| `usda:170092` Potato pancakes | carbohydrate | 27.81 (`usda:170092`); 20.64 (`usda:2709552`) |
| `usda:170103` Peas, green, canned, no salt added, solids and liquids | carbohydrate | 9.75 (`usda:170103`); 12.19 (`usda:2709972`) |
| `usda:2515374` Nuts, cashew nuts, raw | carbohydrate | 30.19 (`usda:170162`); 36.289 (`usda:2515374`) |
| `usda:2515378` Nuts, macadamia nuts, raw | carbohydrate | 13.82 (`usda:170178`); 24.094 (`usda:2515378`) |
| `usda:2346394` Nuts, walnuts, English, halves, raw | carbohydrate | 13.71 (`usda:170187`); 10.91 (`usda:2346394`); 10.91 (`usda:2707531`) |
| `usda:2512378` Buckwheat, whole grain | protein | 13.25 (`usda:170286`); 11.0653 (`usda:2512378`) |
| `usda:170382` Broccoli raab, cooked | fat_total | 0.52 (`usda:170382`); 3.15 (`usda:2709573`) |
| `usda:170494` Spinach souffle | energy_kcal | 172 (`usda:170494`); 128 (`usda:2709629`) |
| `usda:170494` Spinach souffle | protein | 7.89 (`usda:170494`); 5.72 (`usda:2709629`) |
| `usda:170494` Spinach souffle | fat_total | 12.95 (`usda:170494`); 8.64 (`usda:2709629`) |
| `usda:2515380` Seeds, pumpkin seeds (pepitas), raw | fat_total | 49.05 (`usda:170556`); 40.03 (`usda:2515380`) |
| `usda:2515380` Seeds, pumpkin seeds (pepitas), raw | carbohydrate | 10.71 (`usda:170556`); 18.675 (`usda:2515380`) |
| `usda:2515381` Seeds, sunflower seed, kernel, raw | carbohydrate | 20 (`usda:170562`); 24.501 (`usda:2515381`) |
| `usda:2515375` Nuts, hazelnuts or filberts, raw | carbohydrate | 16.7 (`usda:170581`); 26.501 (`usda:2515375`); 16.7 (`usda:2707502`) |
| `usda:2512374` Flour, buckwheat | protein | 12.62 (`usda:170687`); 8.88492 (`usda:2512374`) |
| `usda:170848` Cheese, parmesan, hard | protein | 35.75 (`usda:170848`); 29.87 (`usda:2705730`) |
| `usda:170848` Cheese, parmesan, hard | carbohydrate | 3.22 (`usda:170848`); 8.36 (`usda:2705730`) |
| `usda:171288` Cheese, Mexican blend | carbohydrate | 0.13 (`usda:171288`); 2.4 (`usda:2705741`) |
| `usda:171853` Pancakes, whole wheat, dry mix, incomplete | protein | 10.53 (`usda:171853`); 12.8 (`usda:172776`) |
| `usda:171897` Beverages, coffee, instant, with chicory | energy_kcal | 355 (`usda:171897`); 3 (`usda:174134`) |
| `usda:171897` Beverages, coffee, instant, with chicory | protein | 9.3 (`usda:171897`); 0.09 (`usda:174134`) |
| `usda:171897` Beverages, coffee, instant, with chicory | carbohydrate | 78.9 (`usda:171897`); 0.75 (`usda:174134`) |
| `usda:172035` Fast foods, french toast sticks | energy_kcal | 340 (`usda:172035`); 400 (`usda:2708339`) |
| `usda:172094` Tortellini, pasta with cheese filling, fresh-refrigerated, as purchased | energy_kcal | 307 (`usda:172094`); 236 (`usda:2708792`) |
| `usda:172094` Tortellini, pasta with cheese filling, fresh-refrigerated, as purchased | protein | 13.5 (`usda:172094`); 10.38 (`usda:2708792`) |
| `usda:172094` Tortellini, pasta with cheese filling, fresh-refrigerated, as purchased | fat_total | 7.23 (`usda:172094`); 5.56 (`usda:2708792`) |
| `usda:172094` Tortellini, pasta with cheese filling, fresh-refrigerated, as purchased | carbohydrate | 47 (`usda:172094`); 36.15 (`usda:2708792`) |
| `usda:748236` Eggs, Grade A, Large, egg yolk | carbohydrate | 3.59 (`usda:172184`); 1.02 (`usda:2707172`); 1.02 (`usda:748236`) |
| `usda:172227` Ice cream cookie sandwich | energy_kcal | 240 (`usda:172227`); 317 (`usda:2705644`) |
| `usda:172227` Ice cream cookie sandwich | fat_total | 7.4 (`usda:172227`); 14.11 (`usda:2705644`) |
| `usda:2515376` Peanuts, raw | carbohydrate | 16.13 (`usda:172430`); 26.498 (`usda:2515376`); 16.13 (`usda:2707514`) |
| `usda:172672` Bread, cracked-wheat | energy_kcal | 260 (`usda:172672`); 274 (`usda:172686`); 274 (`usda:2707720`); 301 (`usda:2707721`); 274 (`usda:2707788`); 274 (`usda:2707847`) |
| `usda:172672` Bread, cracked-wheat | protein | 8.7 (`usda:172672`); 10.67 (`usda:172686`); 10.67 (`usda:2707720`); 11.72 (`usda:2707721`); 10.67 (`usda:2707788`); 10.67 (`usda:2707847`) |
| `usda:172676` Bread, oat bran | energy_kcal | 236 (`usda:172676`); 259 (`usda:172677`); 269 (`usda:172678`); 292 (`usda:172679`); 269 (`usda:2707768`); 296 (`usda:2707769`); 299 (`usda:2707770`); 296 (`usda:2707771`); 269 (`usda:2707773`); 269 (`usda:2707774`) |
| `usda:172676` Bread, oat bran | protein | 10.4 (`usda:172676`); 11.4 (`usda:172677`); 8.4 (`usda:172678`); 9.2 (`usda:172679`); 8.4 (`usda:2707768`); 9.23 (`usda:2707769`); 9.33 (`usda:2707770`); 9.23 (`usda:2707771`); 8.4 (`usda:2707773`); 8.4 (`usda:2707774`) |
| `usda:172676` Bread, oat bran | carbohydrate | 39.8 (`usda:172676`); 43.7 (`usda:172677`); 48.5 (`usda:172678`); 52.7 (`usda:172679`); 48.5 (`usda:2707768`); 53.3 (`usda:2707769`); 53.89 (`usda:2707770`); 53.3 (`usda:2707771`); 48.5 (`usda:2707773`); 48.5 (`usda:2707774`) |
| `usda:173452` Cheese, parmesan, dry grated, reduced fat | energy_kcal | 265 (`usda:173452`); 395 (`usda:2705729`) |
| `usda:173452` Cheese, parmesan, dry grated, reduced fat | protein | 20 (`usda:173452`); 34.8 (`usda:2705729`) |
| `usda:173452` Cheese, parmesan, dry grated, reduced fat | fat_total | 20 (`usda:173452`); 16.5 (`usda:2705729`) |
| `usda:173452` Cheese, parmesan, dry grated, reduced fat | carbohydrate | 1.37 (`usda:173452`); 26.2 (`usda:2705729`) |
| `usda:2514743` Beef, ground, 90% lean meat / 10% fat, raw | fat_total | 10 (`usda:174030`); 12.85 (`usda:2514743`) |
| `usda:174086` Pancakes, plain, reduced fat | protein | 5.71 (`usda:174086`); 7.57 (`usda:2708305`) |
| `usda:174086` Pancakes, plain, reduced fat | fat_total | 1.9 (`usda:174086`); 9.74 (`usda:2708305`) |
| `usda:174086` Pancakes, plain, reduced fat | carbohydrate | 57.32 (`usda:174086`); 36.1 (`usda:2708305`) |
| `usda:174208` Crustaceans, lobster, northern, raw | protein | 16.52 (`usda:174208`); 20.91 (`usda:2706349`) |
| `usda:174216` Mollusks, mussel, blue, raw | protein | 11.9 (`usda:174216`); 15.06 (`usda:2706350`) |
| `usda:2727570` Lamb, ground, raw | energy_kcal | 282 (`usda:174370`); 241.727 (`usda:2727570`) |
| `usda:2727570` Lamb, ground, raw | fat_total | 23.41 (`usda:174370`); 18.64 (`usda:2727570`) |
| `usda:746783` Sausage, turkey, breakfast links, mild, raw | protein | 15.91 (`usda:174600`); 19.65 (`usda:2706200`); 16.7 (`usda:746783`) |
| `usda:746783` Sausage, turkey, breakfast links, mild, raw | fat_total | 10.39 (`usda:174600`); 12.24 (`usda:2706200`); 10.4 (`usda:746783`) |
| `usda:746783` Sausage, turkey, breakfast links, mild, raw | carbohydrate | 3.18 (`usda:174600`); 1.09 (`usda:2706200`); 0.93 (`usda:746783`) |
| `usda:175020` Pie, peach | energy_kcal | 224 (`usda:175020`); 296 (`usda:2708002`) |
| `usda:175020` Pie, peach | fat_total | 10 (`usda:175020`); 15.28 (`usda:2708002`) |
| `usda:175032` Strudel, apple | fat_total | 11.2 (`usda:175032`); 14.08 (`usda:2708039`) |
| `usda:2705929` Chicken, NS as to part and cooking method, NS as to skin eaten | energy_kcal | 164 (`usda:2705929`); 196 (`usda:2705930`) |
| `usda:2705929` Chicken, NS as to part and cooking method, NS as to skin eaten | fat_total | 6.36 (`usda:2705929`); 10.65 (`usda:2705930`) |
| `usda:2705932` Chicken, NS as to part, baked, broiled, or roasted, NS as to skin eaten | energy_kcal | 165 (`usda:2705932`); 203 (`usda:2705933`) |
| `usda:2705932` Chicken, NS as to part, baked, broiled, or roasted, NS as to skin eaten | fat_total | 5.32 (`usda:2705932`); 10.8 (`usda:2705933`) |
| `usda:2705935` Chicken, NS as to part, rotisserie, NS as to skin eaten | energy_kcal | 164 (`usda:2705935`); 196 (`usda:2705936`) |
| `usda:2705935` Chicken, NS as to part, rotisserie, NS as to skin eaten | fat_total | 6.36 (`usda:2705935`); 10.65 (`usda:2705936`) |
| `usda:2705938` Chicken, NS as to part, stewed, NS as to skin eaten | energy_kcal | 156 (`usda:2705938`); 196 (`usda:2705939`) |
| `usda:2705938` Chicken, NS as to part, stewed, NS as to skin eaten | fat_total | 5.38 (`usda:2705938`); 10.86 (`usda:2705939`) |
| `usda:2705941` Chicken, NS as to part, grilled without sauce, NS as to skin eaten | energy_kcal | 179 (`usda:2705941`); 217 (`usda:2705942`) |
| `usda:2705941` Chicken, NS as to part, grilled without sauce, NS as to skin eaten | fat_total | 7.2 (`usda:2705941`); 12.57 (`usda:2705942`) |
| `usda:2705944` Chicken, NS as to part, grilled with sauce, NS as to skin eaten | energy_kcal | 180 (`usda:2705944`); 211 (`usda:2705945`) |
| `usda:2705944` Chicken, NS as to part, grilled with sauce, NS as to skin eaten | fat_total | 6.36 (`usda:2705944`); 10.74 (`usda:2705945`) |

## Merges

| Record | Members | Matches |
|---|---|---|
| `cofid:16-263` | `ciqual:10001` Squid, raw<br>`cofid:16-263` Squid, raw | same 1.0: `ciqual:10001` ~ `cofid:16-263` |
| `usda:171978` | `ciqual:10011` Oyster, raw<br>`cofid:16-260` Oysters, raw<br>`usda:171978` Mollusks, oyster, eastern, wild, raw<br>`usda:2706351` Oysters, raw<br>`usda:2706353` Oysters, steamed | same 1.0: `ciqual:10011` ~ `cofid:16-260`<br>same 1.0: `ciqual:10011` ~ `usda:2706351`<br>code 1.0: `usda:2706351` ~ `usda:171978`<br>code 1.0: `usda:2706353` ~ `usda:171978` |
| `cofid:16-254` | `ciqual:10016` Cuttlefish, raw<br>`cofid:16-254` Cuttlefish, raw | same 1.0: `ciqual:10016` ~ `cofid:16-254` |
| `usda:174214` | `ciqual:10017` Clam, raw<br>`usda:174214` Mollusks, clam, mixed species, raw<br>`usda:2706338` Clams, raw<br>`usda:2706342` Clams, steamed or boiled<br>`usda:2706343` Clams, canned | same 1.0: `ciqual:10017` ~ `usda:2706338`<br>code 1.0: `usda:2706338` ~ `usda:174214`<br>code 1.0: `usda:2706342` ~ `usda:174214`<br>code 1.0: `usda:2706343` ~ `usda:174214` |
| `usda:174815` | `ciqual:1002` Gin<br>`ciqual:1004` Rum<br>`ciqual:1008` Vodka<br>`usda:174815` Alcoholic beverage, distilled, all (gin, rum, vodka, whiskey) 80 proof<br>`usda:2710699` Brandy<br>`usda:2710700` Whiskey<br>`usda:2710701` Scotch<br>`usda:2710702` Gin<br>`usda:2710703` Rum<br>`usda:2710704` Vodka<br>`usda:2710705` Tequila | same 1.0: `ciqual:1002` ~ `usda:2710702`<br>same 1.0: `ciqual:1004` ~ `usda:2710703`<br>same 1.0: `ciqual:1008` ~ `usda:2710704`<br>code 1.0: `usda:2710699` ~ `usda:174815`<br>code 1.0: `usda:2710700` ~ `usda:174815`<br>code 1.0: `usda:2710701` ~ `usda:174815`<br>code 1.0: `usda:2710702` ~ `usda:174815`<br>code 1.0: `usda:2710703` ~ `usda:174815`<br>code 1.0: `usda:2710704` ~ `usda:174815`<br>code 1.0: `usda:2710705` ~ `usda:174815` |
| `usda:2710623` | `ciqual:1003` Liqueur<br>`usda:2710623` Liqueur | same 1.0: `ciqual:1003` ~ `usda:2710623` |
| `cofid:16-235` | `ciqual:10030` Crayfish, raw<br>`cofid:16-235` Crayfish, raw | same 1.0: `ciqual:10030` ~ `cofid:16-235` |
| `usda:174206` | `ciqual:10031` Crayfish, cooked<br>`usda:174206` Crustaceans, crayfish, mixed species, wild, raw<br>`usda:2706348` Crayfish, cooked | same 1.0: `ciqual:10031` ~ `usda:2706348`<br>code 1.0: `usda:2706348` ~ `usda:174206` |
| `cofid:13-811` | `ciqual:10999` Chervil, dried<br>`cofid:13-811` Chervil, dried | same 1.0: `ciqual:10999` ~ `cofid:13-811` |
| `usda:1104647` | `ciqual:11000` Garlic, raw<br>`cofid:13-244` Garlic, raw<br>`usda:1104647` Garlic, raw<br>`usda:169230` Garlic, raw<br>`usda:2709786` Garlic, raw | same 1.0: `ciqual:11000` ~ `cofid:13-244`<br>same 1.0: `ciqual:11000` ~ `usda:1104647`<br>code 1.0: `usda:1104647` ~ `usda:169230`<br>code 1.0: `usda:2709786` ~ `usda:169230` |
| `usda:326698` | `ciqual:11013` Mustard<br>`usda:172234` Mustard, prepared, yellow<br>`usda:2710085` Mustard<br>`usda:326698` Mustard, prepared, yellow | same 1.0: `ciqual:11013` ~ `usda:2710085`<br>code 1.0: `usda:326698` ~ `usda:172234`<br>code 1.0: `usda:2710085` ~ `usda:172234` |
| `usda:170416` | `ciqual:11014` Parsley, fresh<br>`cofid:13-844` Parsley, fresh<br>`usda:170416` Parsley, fresh<br>`usda:2709796` Parsley, raw | same 1.0: `ciqual:11014` ~ `cofid:13-844`<br>same 1.0: `ciqual:11014` ~ `usda:170416`<br>code 1.0: `usda:2709796` ~ `usda:170416` |
| `cofid:13-258` | `ciqual:11016` Horseradish, raw<br>`cofid:13-258` Horseradish, raw | same 1.0: `ciqual:11016` ~ `cofid:13-258` |
| `usda:173469` | `ciqual:11018` Vinegar<br>`ciqual:11090` Vinegar, cider<br>`cofid:17-339` Vinegar<br>`usda:173469` Vinegar, cider<br>`usda:2709351` Vinegar | same 1.0: `ciqual:11018` ~ `cofid:17-339`<br>same 1.0: `ciqual:11018` ~ `usda:2709351`<br>same 1.0: `ciqual:11090` ~ `usda:173469`<br>code 1.0: `usda:2709351` ~ `usda:173469` |
| `cofid:13-845` | `ciqual:11024` Parsley, dried<br>`cofid:13-845` Parsley, dried | same 1.0: `ciqual:11024` ~ `cofid:13-845` |
| `cofid:13-836` | `ciqual:11027` Mint, fresh<br>`cofid:13-836` Mint, fresh | same 1.0: `ciqual:11027` ~ `cofid:13-836` |
| `cofid:13-837` | `ciqual:11029` Mint, dried<br>`cofid:13-837` Mint, dried | same 1.0: `ciqual:11029` ~ `cofid:13-837` |
| `usda:172232` | `ciqual:11033` Basil, fresh<br>`cofid:13-804` Basil, fresh<br>`usda:172232` Basil, fresh<br>`usda:2709780` Basil, raw | same 1.0: `ciqual:11033` ~ `cofid:13-804`<br>same 1.0: `ciqual:11033` ~ `usda:172232`<br>code 1.0: `usda:2709780` ~ `usda:172232` |
| `cofid:13-835` | `ciqual:11034` Marjoram, dried<br>`cofid:13-835` Marjoram, dried | same 1.0: `ciqual:11034` ~ `cofid:13-835` |
| `cofid:13-882` | `ciqual:11036` Rosemary, dried<br>`cofid:13-882` Rosemary, dried | same 1.0: `ciqual:11036` ~ `cofid:13-882` |
| `cofid:13-852` | `ciqual:11039` Saffron<br>`cofid:13-852` Saffron | same 1.0: `ciqual:11039` ~ `cofid:13-852` |
| `cofid:13-825` | `ciqual:11063` Dill, dried<br>`cofid:13-825` Dill, dried | same 1.0: `ciqual:11063` ~ `cofid:13-825` |
| `usda:173473` | `ciqual:11068` Rosemary, fresh<br>`cofid:13-892` Rosemary, fresh<br>`usda:173473` Rosemary, fresh | same 1.0: `ciqual:11068` ~ `cofid:13-892`<br>same 1.0: `ciqual:11068` ~ `usda:173473` |
| `cofid:13-853` | `ciqual:11069` Sage, fresh<br>`cofid:13-853` Sage, fresh | same 1.0: `ciqual:11069` ~ `cofid:13-853` |
| `usda:173470` | `ciqual:11070` Thyme, fresh<br>`cofid:13-893` Thyme, fresh<br>`usda:173470` Thyme, fresh | same 1.0: `ciqual:11070` ~ `cofid:13-893`<br>same 1.0: `ciqual:11070` ~ `usda:173470` |
| `usda:169280` | `ciqual:11084` Seaweed, agar, raw<br>`usda:169280` Seaweed, agar, raw | same 1.0: `ciqual:11084` ~ `usda:169280` |
| `usda:170090` | `ciqual:11085` Seaweed, agar, dried<br>`usda:170090` Seaweed, agar, dried | same 1.0: `ciqual:11085` ~ `usda:170090` |
| `usda:172241` | `ciqual:11091` Vinegar, balsamic<br>`usda:172241` Vinegar, balsamic | same 1.0: `ciqual:11091` ~ `usda:172241` |
| `cofid:13-857` | `ciqual:11092` Tarragon, fresh<br>`cofid:13-857` Tarragon, fresh | same 1.0: `ciqual:11092` ~ `cofid:13-857` |
| `cofid:13-824` | `ciqual:11093` Dill, fresh<br>`cofid:13-824` Dill, fresh | same 1.0: `ciqual:11093` ~ `cofid:13-824` |
| `usda:2710177` | `ciqual:11184` Sauce (average)<br>`usda:2710177` Sauce, NFS | same 1.0: `ciqual:11184` ~ `usda:2710177` |
| `usda:172240` | `ciqual:11220` Vinegar, red wine<br>`usda:172240` Vinegar, red wine | same 1.0: `ciqual:11220` ~ `usda:172240` |
| `usda:167717` | `ciqual:11221` Yeast extract spread<br>`usda:167717` Yeast extract spread<br>`usda:2710006` Yeast extract spread | same 1.0: `ciqual:11221` ~ `usda:167717`<br>code 1.0: `usda:2710006` ~ `usda:167717` |
| `usda:2705704` | `ciqual:12999` Cheese (average)<br>`usda:2705704` Cheese, NFS | same 1.0: `ciqual:12999` ~ `usda:2705704` |
| `usda:168163` | `ciqual:13010` Quince, raw<br>`usda:168163` Quinces, raw | same 1.0: `ciqual:13010` ~ `usda:168163` |
| `usda:173021` | `ciqual:13012` Fig, raw<br>`usda:173021` Figs, raw<br>`usda:2709235` Fig, raw | same 1.0: `ciqual:13012` ~ `usda:173021`<br>code 1.0: `usda:2709235` ~ `usda:173021` |
| `usda:746768` | `ciqual:13013` Fig, dried<br>`usda:174665` Figs, dried, uncooked<br>`usda:2709204` Fig, dried<br>`usda:746768` Figs, dried, uncooked | same 1.0: `ciqual:13013` ~ `usda:2709204`<br>code 1.0: `usda:746768` ~ `usda:174665`<br>code 1.0: `usda:2709204` ~ `usda:174665` |
| `usda:2346409` | `ciqual:13014` Strawberry, raw<br>`cofid:14-324` Strawberries, raw<br>`usda:167762` Strawberries, raw<br>`usda:2346409` Strawberries, raw<br>`usda:2709283` Strawberries, raw | same 1.0: `ciqual:13014` ~ `cofid:14-324`<br>same 1.0: `ciqual:13014` ~ `usda:167762`<br>code 1.0: `usda:2346409` ~ `usda:167762`<br>code 1.0: `usda:2709283` ~ `usda:167762` |
| `usda:2346410` | `ciqual:13015` Raspberry, raw<br>`cofid:14-375` Raspberries, raw<br>`usda:167755` Raspberries, raw<br>`usda:2346410` Raspberries, raw<br>`usda:2709281` Raspberries, raw<br>`usda:2709282` Raspberries, frozen | same 1.0: `ciqual:13015` ~ `cofid:14-375`<br>same 1.0: `ciqual:13015` ~ `usda:167755`<br>code 1.0: `usda:2346410` ~ `usda:167755`<br>code 1.0: `usda:2709281` ~ `usda:167755`<br>code 1.0: `usda:2709282` ~ `usda:167755` |
| `usda:173030` | `ciqual:13020` Gooseberry, raw<br>`usda:173030` Gooseberries, raw | same 1.0: `ciqual:13020` ~ `usda:173030` |
| `usda:2346411` | `ciqual:13028` Blueberry, raw<br>`usda:171711` Blueberries, raw<br>`usda:2346411` Blueberries, raw<br>`usda:2709275` Blueberries, raw | same 1.0: `ciqual:13028` ~ `usda:171711`<br>code 1.0: `usda:2346411` ~ `usda:171711`<br>code 1.0: `usda:2709275` ~ `usda:171711` |
| `usda:2727581` | `ciqual:13029` Blackberry, raw<br>`cofid:14-388` Blackberries, raw<br>`usda:173946` Blackberries, raw<br>`usda:2709273` Blackberries, raw<br>`usda:2727581` Blackberries, raw | same 1.0: `ciqual:13029` ~ `cofid:14-388`<br>same 1.0: `ciqual:13029` ~ `usda:173946`<br>code 1.0: `usda:2727581` ~ `usda:173946`<br>code 1.0: `usda:2709273` ~ `usda:173946` |
| `cofid:14-321` | `ciqual:13037` Pear, flesh and skin, raw<br>`cofid:14-321` Pears, raw, flesh and skin | same 1.0: `ciqual:13037` ~ `cofid:14-321` |
| `usda:2758980` | `ciqual:13046` Raisin<br>`usda:168165` Raisins, dark, seedless (Includes foods for USDA's Food Distribution Program)<br>`usda:2709212` Raisins<br>`usda:2758980` Raisins, dark, seedless | same 1.0: `ciqual:13046` ~ `usda:2709212`<br>code 1.0: `usda:2758980` ~ `usda:168165`<br>code 1.0: `usda:2709212` ~ `usda:168165` |
| `usda:2758975` | `ciqual:13047` Rhubarb, stalk, raw<br>`usda:2758975` Rhubarb, stalk, raw | same 1.0: `ciqual:13047` ~ `usda:2758975` |
| `usda:171691` | `ciqual:13111` Apple, dried<br>`usda:171691` Apples, dried, sulfured, uncooked<br>`usda:2709196` Apple, dried | same 1.0: `ciqual:13111` ~ `usda:2709196`<br>code 1.0: `usda:2709196` ~ `usda:171691` |
| `usda:171722` | `ciqual:13113` Cranberry, raw<br>`usda:171722` Cranberries, raw<br>`usda:2709279` Cranberries, raw | same 1.0: `ciqual:13113` ~ `usda:171722`<br>code 1.0: `usda:2709279` ~ `usda:171722` |
| `ciqual:13161` | `ciqual:13161` Dairy and cereal-based beverage for baby's dinner, with vegetables, from 4/6 months<br>`ciqual:13172` Dairy and cereal-based beverage for baby's dinner, with vegetables, from 4/6 months | same 1.0: `ciqual:13161` ~ `ciqual:13172` |
| `usda:173032` | `ciqual:13183` Goji berry, dried<br>`usda:173032` Goji berries, dried | same 1.0: `ciqual:13183` ~ `usda:173032` |
| `usda:169094` | `ciqual:13184` Olive (average)<br>`usda:169094` Olives, ripe, canned (small-extra large)<br>`usda:2710088` Olives, NFS<br>`usda:2710090` Olives, black | same 1.0: `ciqual:13184` ~ `usda:2710088`<br>code 1.0: `usda:2710088` ~ `usda:169094`<br>code 1.0: `usda:2710090` ~ `usda:169094` |
| `usda:2709237` | `ciqual:13395` Grape, raw (average)<br>`usda:2709237` Grapes, raw | same 1.0: `ciqual:13395` ~ `usda:2709237` |
| `usda:2709195` | `ciqual:13996` Fruit, dried (average)<br>`usda:2709195` Dried, fruit, NFS | same 1.0: `ciqual:13996` ~ `usda:2709195` |
| `usda:169412` | `ciqual:15010` Sesame seed<br>`cofid:14-844` Sesame seeds<br>`usda:169412` Seeds, sesame seed kernels, dried (decorticated)<br>`usda:2707586` Sesame seeds | same 1.0: `ciqual:15010` ~ `cofid:14-844`<br>same 1.0: `ciqual:15010` ~ `usda:2707586`<br>code 1.0: `usda:2707586` ~ `usda:169412` |
| `usda:2346392` | `ciqual:15025` Pine nut<br>`usda:170591` Nuts, pine nuts, dried<br>`usda:2346392` Nuts, pine nuts, raw<br>`usda:2707526` Pine nuts | same 1.0: `ciqual:15025` ~ `usda:2707526`<br>code 1.0: `usda:2346392` ~ `usda:170591`<br>code 1.0: `usda:2707526` ~ `usda:170591` |
| `usda:2262075` | `ciqual:15034` Flaxseed, seed<br>`usda:169414` Seeds, flaxseed<br>`usda:2262075` Flaxseed, ground<br>`usda:2707588` Flax seeds | same 1.0: `ciqual:15034` ~ `usda:169414`<br>code 1.0: `usda:2262075` ~ `usda:169414`<br>code 1.0: `usda:2707588` ~ `usda:169414` |
| `cofid:17-002` | `ciqual:16030` Cocoa butter<br>`cofid:17-002` Cocoa butter | same 1.0: `ciqual:16030` ~ `cofid:17-002` |
| `usda:2710180` | `ciqual:17001` Vegetable oil (average)<br>`usda:2710180` Vegetable oil, NFS | same 1.0: `ciqual:17001` ~ `usda:2710180` |
| `usda:171031` | `ciqual:17030` Almond oil<br>`usda:171031` Oil, almond<br>`usda:2710181` Almond oil | same 1.0: `ciqual:17030` ~ `usda:2710181`<br>code 1.0: `usda:2710181` ~ `usda:171031` |
| `usda:1750348` | `ciqual:17040` Peanut oil<br>`usda:171410` Oil, peanut, salad or cooking<br>`usda:1750348` Oil, peanut<br>`usda:2710187` Peanut oil | same 1.0: `ciqual:17040` ~ `usda:2710187`<br>code 1.0: `usda:1750348` ~ `usda:171410`<br>code 1.0: `usda:2710187` ~ `usda:171410` |
| `usda:171014` | `ciqual:17110` Wheat germ oil<br>`usda:171014` Oil, wheat germ<br>`usda:2710194` Wheat germ oil | same 1.0: `ciqual:17110` ~ `usda:2710194`<br>code 1.0: `usda:2710194` ~ `usda:171014` |
| `usda:171024` | `ciqual:17170` Cottonseed oil<br>`usda:171024` Oil, cottonseed, salad or cooking<br>`usda:2710184` Cottonseed oil | same 1.0: `ciqual:17170` ~ `usda:2710184`<br>code 1.0: `usda:2710184` ~ `usda:171024` |
| `usda:171030` | `ciqual:17220` Walnut oil<br>`cofid:17-047` Oil, walnut<br>`usda:171030` Oil, walnut<br>`usda:2710193` Walnut oil | same 1.0: `ciqual:17220` ~ `usda:2710193`<br>same 1.0: `cofid:17-047` ~ `usda:171030`<br>code 1.0: `usda:2710193` ~ `usda:171030` |
| `usda:171016` | `ciqual:17400` Sesame oil<br>`usda:171016` Oil, sesame, salad or cooking<br>`usda:2710190` Sesame oil | same 1.0: `ciqual:17400` ~ `usda:2710190`<br>code 1.0: `usda:2710190` ~ `usda:171016` |
| `usda:2710192` | `ciqual:17440` Sunflower oil<br>`usda:2710192` Sunflower oil | same 1.0: `ciqual:17440` ~ `usda:2710192` |
| `cofid:17-158` | `ciqual:18005` Coffee, powder, instant<br>`cofid:17-158` Coffee, powder, instant | same 1.0: `ciqual:18005` ~ `cofid:17-158` |
| `ciqual:18028` | `ciqual:18028` Bottled water, flavoured, no added sugars and no sweetener(s)<br>`ciqual:18030` Bottled water, flavoured, no added sugars and with sweetener(s) | same 1.0: `ciqual:18028` ~ `ciqual:18030` |
| `usda:174116` | `ciqual:18041` Coconut milk<br>`cofid:14-820` Coconut milk<br>`usda:174116` Beverages, coconut milk, sweetened, fortified with calcium, vitamins A, B12, D2<br>`usda:2705413` Coconut milk | same 1.0: `ciqual:18041` ~ `cofid:14-820`<br>same 1.0: `ciqual:18041` ~ `usda:2705413`<br>code 1.0: `usda:2705413` ~ `usda:174116` |
| `ciqual:18340` | `ciqual:18340` Carbonated beverage or fruit soft drink, fruit content < 10% , no added sugars and with sweetener(s)<br>`ciqual:18345` Carbonated beverage or fruit soft drink, fruit content < 10% , no added sugars and no sweetener(s) | same 1.0: `ciqual:18340` ~ `ciqual:18345` |
| `usda:746782` | `ciqual:19016` Milk, whole (average)<br>`usda:171265` Milk, whole, 3.25% milkfat, with added vitamin D<br>`usda:2705385` Milk, whole<br>`usda:2705392` Milk, lactose free, whole<br>`usda:746782` Milk, whole, 3.25% milkfat, with added vitamin D | same 1.0: `ciqual:19016` ~ `usda:2705385`<br>code 1.0: `usda:746782` ~ `usda:171265`<br>code 1.0: `usda:2705385` ~ `usda:171265`<br>code 1.0: `usda:2705392` ~ `usda:171265` |
| `cofid:12-320` | `ciqual:19023` Milk, whole, UHT<br>`cofid:12-320` Milk, whole, UHT | same 1.0: `ciqual:19023` ~ `cofid:12-320` |
| `cofid:12-596` | `ciqual:19024` Milk, whole, pasteurised<br>`cofid:12-596` Milk, whole, pasteurised, average | same 1.0: `ciqual:19024` ~ `cofid:12-596` |
| `cofid:12-314` | `ciqual:19041` Milk, semi-skimmed, UHT<br>`cofid:12-314` Milk, semi-skimmed, UHT | same 1.0: `ciqual:19041` ~ `cofid:12-314` |
| `cofid:12-313` | `ciqual:19042` Milk, semi-skimmed, pasteurised<br>`cofid:12-313` Milk, semi-skimmed, pasteurised, average | same 1.0: `ciqual:19042` ~ `cofid:12-313` |
| `cofid:12-554` | `ciqual:19050` Milk, skimmed, UHT<br>`cofid:12-554` Milk, skimmed, UHT | same 1.0: `ciqual:19050` ~ `cofid:12-554` |
| `cofid:12-307` | `ciqual:19051` Milk, skimmed, pasteurised<br>`cofid:12-307` Milk, skimmed, pasteurised, average | same 1.0: `ciqual:19051` ~ `cofid:12-307` |
| `ciqual:19593` | `ciqual:19593` Yogurt or fermented milk, plain<br>`ciqual:19600` Yoghurt or fermented milk, plain (average) | same 1.0: `ciqual:19593` ~ `ciqual:19600` |
| `cofid:12-555` | `ciqual:19860` Yogurt, Greek-style, plain<br>`cofid:12-555` Yogurt, Greek style, plain | same 1.0: `ciqual:19860` ~ `cofid:12-555` |
| `usda:2258586` | `ciqual:20009` Carrot, raw<br>`usda:170393` Carrots, raw<br>`usda:2258586` Carrots, mature, raw<br>`usda:2709660` Carrots, raw<br>`usda:2710793` Carrots, cooked, as ingredient | same 1.0: `ciqual:20009` ~ `usda:170393`<br>same 1.0: `ciqual:20009` ~ `usda:2709660`<br>code 1.0: `usda:2258586` ~ `usda:170393`<br>code 1.0: `usda:2710793` ~ `usda:170393` |
| `usda:2709793` | `ciqual:20010` Mushroom, all types, raw<br>`usda:2709793` Mushrooms, raw | unsure 0.5: `ciqual:20010` ~ `usda:2709793` |
| `usda:2685573` | `ciqual:20016` Cauliflower, raw<br>`cofid:13-512` Cauliflower, raw<br>`usda:169986` Cauliflower, raw<br>`usda:2685573` Cauliflower, raw<br>`usda:2709777` Cauliflower, raw<br>`usda:2710801` Cauliflower, cooked, as ingredient | same 1.0: `ciqual:20016` ~ `cofid:13-512`<br>same 1.0: `ciqual:20016` ~ `usda:169986`<br>code 1.0: `usda:2685573` ~ `usda:169986`<br>code 1.0: `usda:2709777` ~ `usda:169986`<br>code 1.0: `usda:2710801` ~ `usda:169986` |
| `cofid:13-523` | `ciqual:20019` Cucumber, flesh and skin, raw<br>`cofid:13-523` Cucumber, raw, flesh and skin | same 1.0: `ciqual:20019` ~ `cofid:13-523` |
| `usda:170068` | `ciqual:20022` Watercress, raw<br>`cofid:13-669@row2827` Watercress, raw<br>`usda:170068` Watercress, raw<br>`usda:2709639` Watercress, raw | same 1.0: `ciqual:20022` ~ `cofid:13-669@row2827`<br>same 1.0: `ciqual:20022` ~ `usda:170068`<br>code 1.0: `usda:2709639` ~ `usda:170068` |
| `usda:2709789` | `ciqual:20031` Lettuce, raw<br>`cofid:13-520` Lettuce, average, raw<br>`usda:2709789` Lettuce, raw | same 1.0: `ciqual:20031` ~ `cofid:13-520`<br>same 1.0: `ciqual:20031` ~ `usda:2709789` |
| `usda:2710002` | `ciqual:20033` Turnip, cooked<br>`usda:2710002` Turnip, cooked | same 1.0: `ciqual:20033` ~ `usda:2710002` |
| `usda:170000` | `ciqual:20034` Onion, raw<br>`cofid:13-499` Onions, raw<br>`usda:170000` Onions, raw<br>`usda:2709795` Onions, raw<br>`usda:2710796` Onions, cooked, as ingredient | same 1.0: `ciqual:20034` ~ `cofid:13-499`<br>same 1.0: `ciqual:20034` ~ `usda:170000`<br>same 1.0: `ciqual:20034` ~ `usda:2709795`<br>code 1.0: `usda:2710796` ~ `usda:170000` |
| `cofid:13-624` | `ciqual:20039` Leek, raw<br>`cofid:13-624` Leeks, raw | same 1.0: `ciqual:20039` ~ `cofid:13-624` |
| `usda:2709315` | `ciqual:2004` Fruit juice (average)<br>`usda:2709315` Fruit juice, NFS | same 1.0: `ciqual:2004` ~ `usda:2709315` |
| `usda:168448` | `ciqual:20044` Pumpkin, raw<br>`usda:168448` Pumpkin, raw<br>`usda:2709693` Winter squash, raw | same 1.0: `ciqual:20044` ~ `usda:168448`<br>code 1.0: `usda:2709693` ~ `usda:168448` |
| `usda:169276` | `ciqual:20045` Radish, raw<br>`usda:169276` Radishes, raw<br>`usda:2709803` Radish | same 1.0: `ciqual:20045` ~ `usda:169276`<br>code 1.0: `usda:2709803` ~ `usda:169276` |
| `usda:2709981` | `ciqual:20046` Salsify, cooked<br>`usda:2709981` Salsify, cooked | same 1.0: `ciqual:20046` ~ `usda:2709981` |
| `cofid:13-153` | `ciqual:20052` Artichoke, globe, raw<br>`cofid:13-153` Artichoke, globe, raw | same 1.0: `ciqual:20052` ~ `cofid:13-153` |
| `usda:2685577` | `ciqual:20053` Eggplant, raw<br>`usda:169228` Eggplant, raw<br>`usda:2685577` Eggplant, raw<br>`usda:2709785` Eggplant, raw<br>`usda:2710802` Eggplant, cooked, as ingredient | same 1.0: `ciqual:20053` ~ `usda:169228`<br>code 1.0: `usda:2685577` ~ `usda:169228`<br>code 1.0: `usda:2709785` ~ `usda:169228`<br>code 1.0: `usda:2710802` ~ `usda:169228` |
| `usda:169981` | `ciqual:20054` Cardoon, raw<br>`usda:169981` Cardoon, raw | same 1.0: `ciqual:20054` ~ `usda:169981` |
| `usda:170400` | `ciqual:20055` Celeriac, raw<br>`cofid:13-219` Celeriac, raw<br>`usda:170400` Celeriac, raw | same 1.0: `ciqual:20055` ~ `cofid:13-219`<br>same 1.0: `ciqual:20055` ~ `usda:170400` |
| `usda:747447` | `ciqual:20057` Broccoli, raw<br>`usda:170379` Broccoli, raw<br>`usda:2709643` Broccoli, raw<br>`usda:2710792` Broccoli, cooked, as ingredient<br>`usda:747447` Broccoli, raw | same 1.0: `ciqual:20057` ~ `usda:170379`<br>code 1.0: `usda:747447` ~ `usda:170379`<br>code 1.0: `usda:2709643` ~ `usda:170379`<br>code 1.0: `usda:2710792` ~ `usda:170379` |
| `usda:2685575` | `ciqual:20058` Brussels sprout, raw<br>`cofid:13-177` Brussels sprouts, raw<br>`usda:170383` Brussels sprouts, raw<br>`usda:2685575` Brussels sprouts, raw<br>`usda:2709772` Brussels sprouts, raw | same 1.0: `ciqual:20058` ~ `cofid:13-177`<br>same 1.0: `ciqual:20058` ~ `usda:170383`<br>code 1.0: `usda:2685575` ~ `usda:170383`<br>code 1.0: `usda:2709772` ~ `usda:170383` |
| `usda:1999633` | `ciqual:20059` Spinach, raw<br>`usda:168462` Spinach, raw<br>`usda:1999633` Spinach, mature<br>`usda:2709614` Spinach, raw<br>`usda:2710791` Spinach, cooked, as ingredient | same 1.0: `ciqual:20059` ~ `usda:168462`<br>same 1.0: `ciqual:20059` ~ `usda:2709614`<br>code 1.0: `usda:1999633` ~ `usda:168462`<br>code 1.0: `usda:2710791` ~ `usda:168462` |
| `usda:168424` | `ciqual:20065` Kohlrabi, raw<br>`usda:168424` Kohlrabi, raw<br>`usda:2709788` Kohlrabi, raw | same 1.0: `ciqual:20065` ~ `usda:168424`<br>code 1.0: `usda:2709788` ~ `usda:168424` |
| `cofid:13-164` | `ciqual:20091` Beetroot, raw<br>`cofid:13-164` Beetroot, raw | same 1.0: `ciqual:20091` ~ `cofid:13-164` |
| `usda:170500` | `ciqual:20092` Carrot, dehydrated<br>`usda:170500` Carrot, dehydrated | same 1.0: `ciqual:20092` ~ `usda:170500` |
| `usda:2709692` | `ciqual:20096` Pumpkin, cooked<br>`usda:2709692` Pumpkin, cooked | same 1.0: `ciqual:20096` ~ `usda:2709692` |
| `usda:170499` | `ciqual:20097` Shallot, raw<br>`cofid:13-342` Shallots, raw<br>`usda:170499` Shallots, raw | same 1.0: `ciqual:20097` ~ `cofid:13-342`<br>same 1.0: `ciqual:20097` ~ `usda:170499` |
| `usda:170456` | `ciqual:20119` Tomato, green, raw<br>`usda:170456` Tomatoes, green, raw | same 1.0: `ciqual:20119` ~ `usda:170456` |
| `usda:2685582` | `ciqual:20170` Tomato puree, canned<br>`usda:2685582` Tomato, puree, canned | unsure 1.0: `ciqual:20170` ~ `usda:2685582` |
| `cofid:13-519` | `ciqual:20172` Tomato, cherry, raw<br>`cofid:13-519` Tomatoes, cherry, raw | same 1.0: `ciqual:20172` ~ `cofid:13-519` |
| `cofid:14-289` | `ciqual:2018` Prune juice<br>`cofid:14-289` Prune juice | same 1.0: `ciqual:2018` ~ `cofid:14-289` |
| `usda:2747659` | `ciqual:20181` Parsnip, raw<br>`cofid:13-312` Parsnip, raw<br>`usda:170417` Parsnips, raw<br>`usda:2747659` Parsnips, raw | same 1.0: `ciqual:20181` ~ `cofid:13-312`<br>same 1.0: `ciqual:20181` ~ `usda:170417`<br>code 1.0: `usda:2747659` ~ `usda:170417` |
| `usda:169236` | `ciqual:20196` Jerusalem artichoke, raw<br>`usda:169236` Jerusalem-artichokes, raw | same 1.0: `ciqual:20196` ~ `usda:169236` |
| `usda:169210` | `ciqual:20198` Bamboo shoots, raw<br>`usda:169210` Bamboo shoots, raw | same 1.0: `ciqual:20198` ~ `usda:169210` |
| `cofid:13-234` | `ciqual:20218` Curly kale, raw<br>`cofid:13-234` Curly kale, raw | same 1.0: `ciqual:20218` ~ `cofid:13-234` |
| `cofid:14-285` | `ciqual:2024` Passion fruit juice, fresh<br>`cofid:14-285` Passion fruit juice | unsure 0.75: `ciqual:2024` ~ `cofid:14-285` |
| `usda:2710823` | `ciqual:20279` Asparagus, green, raw<br>`usda:2710823` Asparagus, green, raw | same 1.0: `ciqual:20279` ~ `usda:2710823` |
| `cofid:14-279` | `ciqual:2030` Lime juice, fresh<br>`cofid:14-279` Lime juice, fresh | same 1.0: `ciqual:2030` ~ `cofid:14-279` |
| `usda:323505` | `ciqual:20346` Kale, raw<br>`usda:168421` Kale, raw<br>`usda:2709599` Kale, raw<br>`usda:323505` Kale, raw | same 1.0: `ciqual:20346` ~ `usda:168421`<br>code 1.0: `usda:323505` ~ `usda:168421`<br>code 1.0: `usda:2709599` ~ `usda:168421` |
| `usda:2709719` | `ciqual:20385` Tomato, raw (average)<br>`cofid:13-517` Tomatoes, standard, raw<br>`usda:2709719` Tomatoes, raw | same 1.0: `ciqual:20385` ~ `usda:2709719`<br>unsure 0.67: `ciqual:20385` ~ `cofid:13-517` |
| `usda:171704` | `ciqual:2043` Apricot nectar<br>`usda:171704` Apricot nectar, canned, with added ascorbic acid<br>`usda:2709341` Apricot nectar | same 1.0: `ciqual:2043` ~ `usda:2709341`<br>code 1.0: `usda:2709341` ~ `usda:171704` |
| `usda:169107` | `ciqual:2045` Papaya nectar<br>`usda:169107` Papaya nectar, canned<br>`usda:2709327` Papaya juice, 100%<br>`usda:2709347` Papaya nectar | same 1.0: `ciqual:2045` ~ `usda:2709347`<br>code 1.0: `usda:2709327` ~ `usda:169107`<br>code 1.0: `usda:2709347` ~ `usda:169107` |
| `usda:169940` | `ciqual:2054` Pear nectar<br>`usda:169940` Pear nectar, canned, without added ascorbic acid<br>`usda:2709349` Pear nectar | same 1.0: `ciqual:2054` ~ `usda:2709349`<br>code 1.0: `usda:2709349` ~ `usda:169940` |
| `usda:172442` | `ciqual:20916` Miso<br>`usda:172442` Miso<br>`usda:2707439` Miso | same 1.0: `ciqual:20916` ~ `usda:172442`<br>code 1.0: `usda:2707439` ~ `usda:172442` |
| `usda:174272` | `ciqual:20917` Tempeh<br>`cofid:13-118` Tempeh<br>`usda:174272` Tempeh | same 1.0: `ciqual:20917` ~ `cofid:13-118`<br>same 1.0: `ciqual:20917` ~ `usda:174272` |
| `usda:747997` | `ciqual:22001` Egg white, raw<br>`usda:172183` Egg, white, raw, fresh<br>`usda:2707168` Egg, white only, raw<br>`usda:747997` Eggs, Grade A, Large, egg white | unsure 0.75: `ciqual:22001` ~ `usda:172183`<br>code 1.0: `usda:747997` ~ `usda:172183`<br>code 1.0: `usda:2707168` ~ `usda:172183` |
| `cofid:12-946` | `ciqual:22500` Omelette, plain, homemade<br>`cofid:12-946` Omelette, plain, homemade | same 1.0: `ciqual:22500` ~ `cofid:12-946` |
| `cofid:12-947` | `ciqual:22506` Omelette with cheese, homemade<br>`cofid:12-947` Omelette, cheese, homemade | unsure 1.0: `ciqual:22506` ~ `cofid:12-947` |
| `usda:2709348` | `ciqual:2365` Passion fruit nectar<br>`usda:2709348` Passion fruit nectar | same 1.0: `ciqual:2365` ~ `usda:2709348` |
| `usda:2709342` | `ciqual:2366` Banana nectar<br>`usda:2709342` Banana nectar | same 1.0: `ciqual:2366` ~ `usda:2709342` |
| `usda:168210` | `ciqual:2367` Guava nectar<br>`usda:168210` Guava nectar, with sucralose, canned<br>`usda:2709344` Guava nectar | same 1.0: `ciqual:2367` ~ `usda:2709344`<br>code 1.0: `usda:2709344` ~ `usda:168210` |
| `usda:167785` | `ciqual:2370` Mango nectar<br>`usda:167785` Mango nectar, canned<br>`usda:2709340` Fruit nectar, NFS<br>`usda:2709345` Mango nectar | same 1.0: `ciqual:2370` ~ `usda:2709345`<br>code 1.0: `usda:2709340` ~ `usda:167785`<br>code 1.0: `usda:2709345` ~ `usda:167785` |
| `usda:169117` | `ciqual:2371` Peach nectar<br>`usda:169117` Peach nectar, canned, with sucralose, without added ascorbic acid<br>`usda:2709346` Peach nectar | same 1.0: `ciqual:2371` ~ `usda:2709346`<br>code 1.0: `usda:2709346` ~ `usda:169117` |
| `usda:2707297` | `ciqual:24520` Meringue<br>`usda:2707297` Meringues | same 1.0: `ciqual:24520` ~ `usda:2707297` |
| `usda:173329` | `ciqual:25019` Ravioli filled with meat, in tomato sauce, canned<br>`usda:173329` Ravioli, meat-filled, with tomato sauce or meat sauce, canned<br>`usda:2708751` Lasagna with meat, canned<br>`usda:2708765` Ravioli, meat-filled, with tomato sauce or meat sauce, canned | unsure 1.0: `ciqual:25019` ~ `usda:173329`<br>code 1.0: `usda:2708751` ~ `usda:173329`<br>code 1.0: `usda:2708765` ~ `usda:173329` |
| `usda:2705792` | `ciqual:25020` Cheese soufflé<br>`usda:2705792` Cheese souffle | same 1.0: `ciqual:25020` ~ `usda:2705792` |
| `usda:2706880` | `ciqual:25522` Sandwich (average)<br>`usda:2706880` Sandwich, NFS | same 1.0: `ciqual:25522` ~ `usda:2706880` |
| `usda:2709144` | `ciqual:25969` Soup (average)<br>`usda:2709144` Soup, NFS | same 1.0: `ciqual:25969` ~ `usda:2709144` |
| `usda:2768188` | `ciqual:26006` Alaska pollock, raw<br>`usda:173725` Fish, pollock, Alaska, raw<br>`usda:2768188` Alaska Pollock, raw | same 1.0: `ciqual:26006` ~ `usda:2768188`<br>code 1.0: `usda:2768188` ~ `usda:173725` |
| `cofid:16-416` | `ciqual:26039` Tuna,  canned in brine, drained<br>`cofid:16-416` Tuna, canned in brine, drained | same 1.0: `ciqual:26039` ~ `cofid:16-416` |
| `cofid:16-080` | `ciqual:26104` John dory, raw<br>`cofid:16-080` John Dory, raw | same 1.0: `ciqual:26104` ~ `cofid:16-080` |
| `cofid:16-091` | `ciqual:26130` Ling, raw<br>`cofid:16-091` Ling, raw | same 1.0: `ciqual:26130` ~ `cofid:16-091` |
| `cofid:16-142` | `ciqual:26162` Shark, raw<br>`cofid:16-142` Shark, raw | same 1.0: `ciqual:26162` ~ `cofid:16-142` |
| `cofid:16-154` | `ciqual:27019` Tilapia, raw<br>`cofid:16-154` Tilapia, raw | same 1.0: `ciqual:27019` ~ `cofid:16-154` |
| `cofid:19-128` | `ciqual:28505` Corned-beef, canned<br>`cofid:19-128` Corned beef, canned | same 1.0: `ciqual:28505` ~ `cofid:19-128` |
| `ciqual:30150` | `ciqual:30150` Merguez sausage, raw<br>`ciqual:30151` Merguez sausage, raw (average) | same 1.0: `ciqual:30150` ~ `ciqual:30151` |
| `cofid:19-106` | `ciqual:30176` Liver sausage<br>`cofid:19-106` Liver sausage | same 1.0: `ciqual:30176` ~ `cofid:19-106` |
| `usda:174582` | `ciqual:30350` Salami<br>`cofid:19-517` Salami<br>`usda:174582` Salami, dry or hard, pork, beef<br>`usda:2706186` Pepperoni, reduced fat<br>`usda:2706195` Salami, NFS | same 1.0: `ciqual:30350` ~ `cofid:19-517`<br>same 1.0: `ciqual:30350` ~ `usda:2706195`<br>code 1.0: `usda:2706186` ~ `usda:174582`<br>code 1.0: `usda:2706195` ~ `usda:174582` |
| `usda:174578` | `ciqual:30780` Sausage (average)<br>`usda:174578` Pork sausage, link/patty, cooked, pan-fried<br>`usda:2706190` Sausage, NFS<br>`usda:2706191` Pork sausage | same 1.0: `ciqual:30780` ~ `usda:2706190`<br>code 1.0: `usda:2706190` ~ `usda:174578`<br>code 1.0: `usda:2706191` ~ `usda:174578` |
| `usda:174573` | `ciqual:30789` Mortadella<br>`ciqual:30791` Mortadella, pork and beef<br>`usda:174573` Mortadella, beef, pork<br>`usda:2706182` Mortadella | same 1.0: `ciqual:30789` ~ `usda:2706182`<br>unsure 1.0: `ciqual:30791` ~ `usda:174573`<br>code 1.0: `usda:2706182` ~ `usda:174573` |
| `usda:169640` | `ciqual:31008` Honey<br>`cofid:17-050` Honey<br>`usda:169640` Honey<br>`usda:2710281` Honey | same 1.0: `ciqual:31008` ~ `cofid:17-050`<br>same 1.0: `ciqual:31008` ~ `usda:169640`<br>code 1.0: `usda:2710281` ~ `usda:169640` |
| `cofid:17-063` | `ciqual:31016` Sugar, white<br>`cofid:17-063` Sugar, white | same 1.0: `ciqual:31016` ~ `cofid:17-063` |
| `usda:168833` | `ciqual:31017` Sugar, brown<br>`cofid:17-060` Sugar, brown<br>`usda:168833` Sugars, brown<br>`usda:2710260` Sugar, brown | same 1.0: `ciqual:31017` ~ `cofid:17-060`<br>same 1.0: `ciqual:31017` ~ `usda:168833`<br>code 1.0: `usda:2710260` ~ `usda:168833` |
| `usda:167781` | `ciqual:31027` Candied fruit<br>`usda:167781` Candied fruit | same 1.0: `ciqual:31027` ~ `usda:167781` |
| `usda:168000` | `ciqual:31032` Chocolate spread with hazelnuts<br>`usda:168000` Chocolate-flavored hazelnut spread<br>`usda:2710289` Chocolate hazelnut spread | same 1.0: `ciqual:31032` ~ `usda:2710289`<br>code 1.0: `usda:2710289` ~ `usda:168000` |
| `usda:2705641` | `ciqual:31035` Ice cream bar, chocolate<br>`usda:2705641` Ice cream bar, chocolate | same 1.0: `ciqual:31035` ~ `usda:2705641` |
| `cofid:17-114` | `ciqual:31050` Marshmallow<br>`cofid:17-114` Marshmallows | same 1.0: `ciqual:31050` ~ `cofid:17-114` |
| `usda:169882` | `ciqual:31054` Chewing gum, sugar-free<br>`usda:169882` Chewing gum, sugarless<br>`usda:2710372` Chewing gum, sugar free | same 1.0: `ciqual:31054` ~ `usda:2710372`<br>code 1.0: `usda:2710372` ~ `usda:169882` |
| `usda:168148` | `ciqual:34500` Frog, leg, raw<br>`usda:168148` Frog legs, raw | unsure 1.0: `ciqual:34500` ~ `usda:168148` |
| `cofid:18-488` | `ciqual:36003` Chicken, meat, raw<br>`cofid:18-488` Chicken, meat, average, raw | same 1.0: `ciqual:36003` ~ `cofid:18-488` |
| `usda:2727568` | `ciqual:36023` Chicken, wing, meat and skin, raw<br>`usda:2727568` Chicken, wing, meat and skin, raw | same 1.0: `ciqual:36023` ~ `usda:2727568` |
| `usda:2727569` | `ciqual:36029` Chicken, breast, meat and skin, raw<br>`usda:2727569` Chicken, breast, meat and skin, raw | same 1.0: `ciqual:36029` ~ `usda:2727569` |
| `usda:172418` | `ciqual:36100` Quail, meat and skin, raw<br>`usda:172418` Quail, meat and skin, raw | same 1.0: `ciqual:36100` ~ `usda:172418` |
| `cofid:18-350` | `ciqual:36301` Turkey, meat, raw<br>`cofid:18-350` Turkey, meat, average, raw | same 1.0: `ciqual:36301` ~ `cofid:18-350` |
| `usda:174472` | `ciqual:36403` Pheasant, meat and skin, raw<br>`usda:174472` Pheasant, raw, meat and skin | same 1.0: `ciqual:36403` ~ `usda:174472` |
| `usda:2708331` | `ciqual:39236` French toast<br>`usda:2708331` French toast, NFS | same 1.0: `ciqual:39236` ~ `usda:2708331` |
| `usda:168105` | `ciqual:39517` Frozen yogurt<br>`usda:168105` Frozen yogurts, flavors other than chocolate<br>`usda:2705451` Frozen yogurt, NFS<br>`usda:2705452` Frozen yogurt, vanilla<br>`usda:2705457` Frozen yogurt bar, vanilla | same 1.0: `ciqual:39517` ~ `usda:2705451`<br>code 1.0: `usda:2705451` ~ `usda:168105`<br>code 1.0: `usda:2705452` ~ `usda:168105`<br>code 1.0: `usda:2705457` ~ `usda:168105` |
| `cofid:11-027` | `ciqual:4000` Tapioca, raw<br>`cofid:11-027` Tapioca, raw | same 1.0: `ciqual:4000` ~ `cofid:11-027` |
| `cofid:18-396` | `ciqual:40058` Heart, lamb, raw<br>`cofid:18-396` Heart, lamb, raw | same 1.0: `ciqual:40058` ~ `cofid:18-396` |
| `cofid:18-413` | `ciqual:40102` Liver, lamb, raw<br>`cofid:18-413` Liver, lamb, raw | same 1.0: `ciqual:40102` ~ `cofid:18-413` |
| `cofid:18-409` | `ciqual:40106` Liver, calf, raw<br>`cofid:18-409` Liver, calf, raw | same 1.0: `ciqual:40106` ~ `cofid:18-409` |
| `cofid:18-411` | `ciqual:40111` Liver, chicken, raw<br>`cofid:18-411` Liver, chicken, raw | same 1.0: `ciqual:40111` ~ `cofid:18-411` |
| `usda:172415` | `ciqual:40120` Liver, goose, raw<br>`usda:172415` Goose, liver, raw | same 1.0: `ciqual:40120` ~ `usda:172415` |
| `cofid:18-423` | `ciqual:40207` Tongue, lamb, raw<br>`cofid:18-423` Tongue, lamb, raw | same 1.0: `ciqual:40207` ~ `cofid:18-423` |
| `cofid:18-421` | `ciqual:40302` Sweetbread, lamb, raw<br>`cofid:18-421` Sweetbread, lamb, raw | same 1.0: `ciqual:40302` ~ `cofid:18-421` |
| `cofid:18-402` | `ciqual:40407` Kidney, lamb, raw<br>`cofid:18-402` Kidney, lamb, raw | same 1.0: `ciqual:40407` ~ `cofid:18-402` |
| `cofid:17-222` | `ciqual:5006` Cider, dry<br>`cofid:17-222` Cider, dry | same 1.0: `ciqual:5006` ~ `cofid:17-222` |
| `cofid:17-224` | `ciqual:5007` Cider, sweet<br>`cofid:17-224` Cider, sweet | same 1.0: `ciqual:5007` ~ `cofid:17-224` |
| `cofid:17-757` | `ciqual:5201` Wine, white, sparkling<br>`cofid:17-757` Wine, white, sparkling | same 1.0: `ciqual:5201` ~ `cofid:17-757` |
| `usda:173190` | `ciqual:5214` Wine, red<br>`cofid:17-752` Wine, red<br>`usda:173190` Alcoholic beverage, wine, table, red<br>`usda:2710688` Wine, red | same 1.0: `ciqual:5214` ~ `cofid:17-752`<br>same 1.0: `ciqual:5214` ~ `usda:2710688`<br>code 1.0: `usda:2710688` ~ `usda:173190` |
| `cofid:17-755` | `ciqual:5215` Wine, white, dry<br>`cofid:17-755` Wine, white, dry | same 1.0: `ciqual:5215` ~ `cofid:17-755` |
| `usda:171908` | `ciqual:5216` Wine, rose<br>`usda:171908` Alcoholic beverages, wine, rose<br>`usda:2710690` Wine, rose | same 1.0: `ciqual:5216` ~ `usda:2710690`<br>code 1.0: `usda:2710690` ~ `usda:171908` |
| `usda:170071` | `ciqual:53672` Yam, raw<br>`usda:170071` Yam, raw | same 1.0: `ciqual:53672` ~ `usda:170071` |
| `usda:171714` | `ciqual:54500` Breadfruit, raw<br>`cofid:13-167` Breadfruit, raw<br>`usda:171714` Breadfruit, raw | same 1.0: `ciqual:54500` ~ `cofid:13-167`<br>same 1.0: `ciqual:54500` ~ `usda:171714` |
| `usda:169260` | `ciqual:58100` Okra, raw<br>`cofid:13-300` Okra, raw<br>`usda:169260` Okra, raw | same 1.0: `ciqual:58100` ~ `cofid:13-300`<br>same 1.0: `ciqual:58100` ~ `usda:169260` |
| `cofid:18-486` | `ciqual:6521` Veal, escalope, raw<br>`cofid:18-486` Veal, escalope, raw | same 1.0: `ciqual:6521` ~ `cofid:18-486` |
| `usda:174915` | `ciqual:7180` Bread, pita<br>`usda:174915` Bread, pita, white, enriched<br>`usda:2707616` Bread, pita | same 1.0: `ciqual:7180` ~ `usda:2707616`<br>code 1.0: `usda:2707616` ~ `usda:174915` |
| `cofid:11-940` | `ciqual:7300` Rusk<br>`cofid:11-940` Rusks | same 1.0: `ciqual:7300` ~ `cofid:11-940` |
| `usda:174987` | `ciqual:7603` Croissant (average)<br>`cofid:11-988` Croissants<br>`usda:174987` Croissants, butter<br>`usda:2707678` Croissant | same 1.0: `ciqual:7603` ~ `cofid:11-988`<br>same 1.0: `ciqual:7603` ~ `usda:2707678`<br>code 1.0: `usda:2707678` ~ `usda:174987` |
| `usda:2707682` | `ciqual:7746` Brioche (average)<br>`usda:2707682` Brioche | same 1.0: `ciqual:7746` ~ `usda:2707682` |
| `cofid:11-872` | `ciqual:9108` Rice, wild, raw<br>`cofid:11-872` Rice, wild, raw | same 1.0: `ciqual:9108` ~ `cofid:11-872` |
| `cofid:11-876` | `ciqual:9109` Rice, red, raw<br>`cofid:11-876` Rice, red, raw | same 1.0: `ciqual:9109` ~ `cofid:11-876` |
| `usda:173904` | `ciqual:9310` Oat, raw<br>`usda:173904` Cereals, oats, regular and quick, not fortified, dry<br>`usda:2708489` Oats, raw | same 1.0: `ciqual:9310` ~ `usda:2708489`<br>code 1.0: `usda:2708489` ~ `usda:173904` |
| `cofid:14-843` | `ciqual:9340` Quinoa, raw<br>`cofid:14-843` Quinoa, raw | same 1.0: `ciqual:9340` ~ `cofid:14-843` |
| `usda:172023` | `ciqual:9555` Millet flour<br>`usda:172023` Millet flour | same 1.0: `ciqual:9555` ~ `usda:172023` |
| `usda:169722` | `ciqual:9621` Wheat bran<br>`usda:169722` Wheat bran, crude<br>`usda:2708488` Wheat bran | same 1.0: `ciqual:9621` ~ `usda:2708488`<br>code 1.0: `usda:2708488` ~ `usda:169722` |
| `usda:173896` | `ciqual:9660` Wheat germ<br>`usda:173896` Cereals ready-to-eat, wheat germ, toasted, plain<br>`usda:2708477` Wheat germ | same 1.0: `ciqual:9660` ~ `usda:2708477`<br>code 1.0: `usda:2708477` ~ `usda:173896` |
| `cofid:11-904` | `ciqual:9690` Wheat, bulgur, raw<br>`cofid:11-904` Wheat, bulgur, raw | same 1.0: `ciqual:9690` ~ `cofid:11-904` |
| `cofid:11-726` | `ciqual:9815` Pasta, fresh, with egg, raw<br>`cofid:11-726` Pasta, egg, fresh, raw | same 1.0: `ciqual:9815` ~ `cofid:11-726` |
| `usda:2758993` | `cofid:11-1001` Bread, white, toasted<br>`cofid:11-1145` Bread, white, average<br>`usda:174924` Bread, white, commercially prepared (includes soft bread crumbs)<br>`usda:2707591` Bread, NS as to major flour<br>`usda:2707598` Bread, white<br>`usda:2707599` Bread, white, toasted<br>`usda:2707656` Roll, white, hot dog bun<br>`usda:2707657` Roll, white, hamburger bun<br>`usda:2758993` Bread, white, commercial | same 1.0: `cofid:11-1001` ~ `usda:2707599`<br>same 1.0: `cofid:11-1145` ~ `usda:2707598`<br>code 1.0: `usda:2758993` ~ `usda:174924`<br>code 1.0: `usda:2707591` ~ `usda:174924`<br>code 1.0: `usda:2707598` ~ `usda:174924`<br>code 1.0: `usda:2707599` ~ `usda:174924`<br>code 1.0: `usda:2707656` ~ `usda:174924`<br>code 1.0: `usda:2707657` ~ `usda:174924` |
| `usda:2512375` | `cofid:11-897` Flour, rye<br>`usda:2512375` Flour, rye | same 1.0: `cofid:11-897` ~ `usda:2512375` |
| `usda:2708441` | `cofid:11-902` Couscous, plain, cooked<br>`usda:2708441` Couscous, plain, cooked | same 1.0: `cofid:11-902` ~ `usda:2708441` |
| `usda:174899` | `cofid:11-970` Bagels, plain<br>`usda:174899` Bagels, plain, enriched, with calcium propionate (includes onion, poppy, sesame)<br>`usda:2707684` Bagel | unsure 0.5: `cofid:11-970` ~ `usda:2707684`<br>code 1.0: `usda:2707684` ~ `usda:174899` |
| `usda:171255` | `cofid:12-112` Cream, half, fresh<br>`usda:171255` Cream, fluid, half and half<br>`usda:2705594` Cream, half and half | unsure 0.67: `cofid:12-112` ~ `usda:2705594`<br>code 1.0: `usda:2705594` ~ `usda:171255` |
| `usda:171242` | `cofid:12-164` Cheese, Gruyere<br>`usda:171242` Cheese, gruyere<br>`usda:2705718` Cheese, Gruyere | same 1.0: `cofid:12-164` ~ `usda:171242`<br>code 1.0: `usda:2705718` ~ `usda:171242` |
| `usda:2705750` | `cofid:12-176` Cheese, Ricotta<br>`usda:2705750` Cheese, Ricotta | same 1.0: `cofid:12-176` ~ `usda:2705750` |
| `usda:171250` | `cofid:12-177` Cheese, Roquefort<br>`usda:171250` Cheese, roquefort | same 1.0: `cofid:12-177` ~ `usda:171250` |
| `usda:2259793` | `cofid:12-184` Yogurt, whole milk, plain<br>`usda:171284` Yogurt, plain, whole milk<br>`usda:2259793` Yogurt, plain, whole milk<br>`usda:2705418` Yogurt, whole milk, plain | same 1.0: `cofid:12-184` ~ `usda:171284`<br>same 1.0: `cofid:12-184` ~ `usda:2705418`<br>code 1.0: `usda:2259793` ~ `usda:171284` |
| `usda:172178` | `cofid:12-345` Cheese, Camembert<br>`usda:172178` Cheese, camembert<br>`usda:2705707` Cheese, Camembert | same 1.0: `cofid:12-345` ~ `usda:172178`<br>code 1.0: `usda:2705707` ~ `usda:172178` |
| `usda:173419` | `cofid:12-355` Cheese, Edam<br>`usda:173419` Cheese, edam | same 1.0: `cofid:12-355` ~ `usda:173419` |
| `usda:171241` | `cofid:12-358` Cheese, Gouda<br>`usda:171241` Cheese, gouda<br>`usda:2705717` Cheese, Gouda or Edam<br>`usda:2705732` Cheese, Port du Salut | same 1.0: `cofid:12-358` ~ `usda:171241`<br>code 1.0: `usda:2705717` ~ `usda:171241`<br>code 1.0: `usda:2705732` ~ `usda:171241` |
| `usda:2705426` | `cofid:12-375` Yogurt, whole milk, fruit<br>`usda:2705426` Yogurt, whole milk, fruit | same 1.0: `cofid:12-375` ~ `usda:2705426` |
| `usda:170886` | `cofid:12-379` Yogurt, low fat, plain<br>`usda:170886` Yogurt, plain, low fat | same 1.0: `cofid:12-379` ~ `usda:170886` |
| `usda:2705702` | `cofid:12-476` Tiramisu<br>`usda:2705702` Tiramisu | same 1.0: `cofid:12-476` ~ `usda:2705702` |
| `usda:2705740` | `cofid:12-495` Cheese, Paneer<br>`usda:2705740` Cheese, paneer | same 1.0: `cofid:12-495` ~ `usda:2705740` |
| `usda:171276` | `cofid:12-522` Milk, evaporated, whole<br>`usda:171276` Milk, canned, evaporated, with added vitamin D and without added vitamin A<br>`usda:2705398` Milk, evaporated, NS as to fat content<br>`usda:2705399` Milk, evaporated, whole | same 1.0: `cofid:12-522` ~ `usda:2705399`<br>code 1.0: `usda:2705398` ~ `usda:171276`<br>code 1.0: `usda:2705399` ~ `usda:171276` |
| `usda:2259796` | `cofid:12-525` Cheese, Feta<br>`usda:173420` Cheese, feta<br>`usda:2259796` Cheese, feta, whole milk, crumbled<br>`usda:2705714` Cheese, Feta | same 1.0: `cofid:12-525` ~ `usda:173420`<br>code 1.0: `usda:2259796` ~ `usda:173420`<br>code 1.0: `usda:2705714` ~ `usda:173420` |
| `usda:172191` | `cofid:12-815` Eggs, quail, whole, raw<br>`usda:172191` Egg, quail, whole, fresh, raw | unsure 0.8: `cofid:12-815` ~ `usda:172191` |
| `usda:172192` | `cofid:12-816` Eggs, turkey, whole, raw<br>`usda:172192` Egg, turkey, whole, fresh, raw | unsure 0.8: `cofid:12-816` ~ `usda:172192` |
| `usda:172189` | `cofid:12-920` Eggs, duck, whole, raw<br>`usda:172189` Egg, duck, whole, fresh, raw | unsure 0.8: `cofid:12-920` ~ `usda:172189` |
| `usda:168384` | `cofid:13-148` Alfalfa sprouts, raw<br>`usda:168384` Alfalfa seeds, sprouted, raw<br>`usda:2709765` Alfalfa sprouts, raw | same 1.0: `cofid:13-148` ~ `usda:2709765`<br>code 1.0: `usda:2709765` ~ `usda:168384` |
| `usda:168385` | `cofid:13-149` Amaranth leaves, raw<br>`usda:168385` Amaranth leaves, raw | same 1.0: `cofid:13-149` ~ `usda:168385` |
| `usda:169203` | `cofid:13-151` Arrowhead, raw<br>`usda:169203` Arrowhead, raw | same 1.0: `cofid:13-151` ~ `usda:169203` |
| `usda:168389` | `cofid:13-157` Asparagus, raw<br>`usda:168389` Asparagus, raw<br>`usda:2709767` Asparagus, raw | same 1.0: `cofid:13-157` ~ `usda:168389`<br>code 1.0: `usda:2709767` ~ `usda:168389` |
| `usda:2685572` | `cofid:13-187` Cabbage, Chinese, raw<br>`usda:170390` Cabbage, chinese (pak-choi), raw<br>`usda:2685572` Cabbage, bok choy, raw<br>`usda:2709774` Cabbage, Chinese, raw | same 1.0: `cofid:13-187` ~ `usda:2709774`<br>code 1.0: `usda:2685572` ~ `usda:170390`<br>code 1.0: `usda:2709774` ~ `usda:170390` |
| `usda:2346408` | `cofid:13-190` Cabbage, red, raw<br>`usda:169977` Cabbage, red, raw<br>`usda:2346408` Cabbage, red, raw<br>`usda:2709775` Cabbage, red, raw | same 1.0: `cofid:13-190` ~ `usda:169977`<br>code 1.0: `usda:2346408` ~ `usda:169977`<br>code 1.0: `usda:2709775` ~ `usda:169977` |
| `usda:169985` | `cofid:13-208` Cassava, raw<br>`usda:169985` Cassava, raw | same 1.0: `cofid:13-208` ~ `usda:169985` |
| `usda:169991` | `cofid:13-223` Chard, Swiss, raw<br>`usda:169991` Chard, swiss, raw<br>`usda:2709574` Chard, raw | same 1.0: `cofid:13-223` ~ `usda:169991`<br>code 1.0: `usda:2709574` ~ `usda:169991` |
| `usda:168416` | `cofid:13-236` Drumstick leaves, raw<br>`usda:168416` Drumstick leaves, raw | same 1.0: `cofid:13-236` ~ `usda:168416` |
| `usda:170483` | `cofid:13-238` Drumstick pods, raw<br>`usda:170483` Drumstick pods, raw | same 1.0: `cofid:13-238` ~ `usda:170483` |
| `usda:168412` | `cofid:13-240` Endive, raw<br>`usda:168412` Endive, raw | same 1.0: `cofid:13-240` ~ `usda:168412` |
| `usda:174687` | `cofid:13-259` Jackfruit, raw<br>`usda:174687` Jackfruit, raw | same 1.0: `cofid:13-259` ~ `usda:174687` |
| `usda:1999627` | `cofid:13-293` Mushrooms, oyster, raw<br>`usda:168580` Mushrooms, oyster, raw<br>`usda:1999627` Mushroom, oyster | same 1.0: `cofid:13-293` ~ `usda:168580`<br>code 1.0: `usda:1999627` ~ `usda:168580` |
| `usda:2709982` | `cofid:13-336` Sauerkraut<br>`usda:2709982` Sauerkraut | same 1.0: `cofid:13-336` ~ `usda:2709982` |
| `usda:169308` | `cofid:13-376` Taro, raw<br>`usda:169308` Taro, raw | same 1.0: `cofid:13-376` ~ `usda:169308` |
| `usda:168487` | `cofid:13-380` Taro leaves, raw<br>`usda:168487` Taro leaves, raw | same 1.0: `cofid:13-380` ~ `usda:168487` |
| `usda:1999629` | `cofid:13-505` Mushrooms, white, raw<br>`usda:169251` Mushrooms, white, raw<br>`usda:1999629` Mushrooms, white button | same 1.0: `cofid:13-505` ~ `usda:169251`<br>code 1.0: `usda:1999629` ~ `usda:169251` |
| `usda:2346407` | `cofid:13-510` Cabbage, green, raw<br>`cofid:13-582` Cabbage, average, raw<br>`usda:169975` Cabbage, raw<br>`usda:2346407` Cabbage, green, raw<br>`usda:2709773` Cabbage, green, raw<br>`usda:2710800` Cabbage, cooked, as ingredient | same 1.0: `cofid:13-510` ~ `usda:2346407`<br>same 1.0: `cofid:13-582` ~ `usda:169975`<br>code 1.0: `usda:2346407` ~ `usda:169975`<br>code 1.0: `usda:2709773` ~ `usda:169975`<br>code 1.0: `usda:2710800` ~ `usda:169975` |
| `usda:2346405` | `cofid:13-636` Celery, raw<br>`usda:169988` Celery, raw<br>`usda:2346405` Celery, raw<br>`usda:2709778` Celery, raw<br>`usda:2709811` Celery juice<br>`usda:2710805` Celery, cooked, as ingredient | same 1.0: `cofid:13-636` ~ `usda:169988`<br>code 1.0: `usda:2346405` ~ `usda:169988`<br>code 1.0: `usda:2709778` ~ `usda:169988`<br>code 1.0: `usda:2709811` ~ `usda:169988`<br>code 1.0: `usda:2710805` ~ `usda:169988` |
| `usda:173941` | `cofid:14-031` Apricots, dried<br>`usda:173941` Apricots, dried, sulfured, uncooked<br>`usda:2709197` Apricot, dried | same 1.0: `cofid:14-031` ~ `usda:2709197`<br>code 1.0: `usda:2709197` ~ `usda:173941` |
| `usda:169121` | `cofid:14-196` Pears, dried<br>`usda:169121` Pears, dried, sulfured, uncooked<br>`usda:2709208` Pear, dried | same 1.0: `cofid:14-196` ~ `usda:2709208`<br>code 1.0: `usda:2709208` ~ `usda:169121` |
| `usda:167763` | `cofid:14-265` Tamarind<br>`usda:167763` Tamarinds, raw<br>`usda:2709269` Tamarind | same 1.0: `cofid:14-265` ~ `usda:2709269`<br>code 1.0: `usda:2709269` ~ `usda:167763` |
| `usda:2709210` | `cofid:14-396` Pineapple, dried<br>`usda:2709210` Pineapple, dried | same 1.0: `cofid:14-396` ~ `usda:2709210` |
| `usda:174261` | `cofid:14-834` Peanuts, roasted and salted<br>`usda:174261` Peanuts, all types, oil-roasted, with salt<br>`usda:2707515` Peanuts, roasted, salted | unsure 1.0: `cofid:14-834` ~ `usda:2707515`<br>code 1.0: `usda:2707515` ~ `usda:174261` |
| `usda:170557` | `cofid:14-842` Pumpkin seeds<br>`usda:170557` Seeds, pumpkin and squash seed kernels, roasted, without salt<br>`usda:2707579` Pumpkin seeds, NFS<br>`usda:2707581` Pumpkin seeds, unsalted | same 1.0: `cofid:14-842` ~ `usda:2707579`<br>code 1.0: `usda:2707579` ~ `usda:170557`<br>code 1.0: `usda:2707581` ~ `usda:170557` |
| `usda:170563` | `cofid:14-845` Sunflower seeds<br>`usda:170563` Seeds, sunflower seed kernels, dry roasted, without salt<br>`usda:2707582` Sunflower seeds, plain, unsalted<br>`usda:2707585` Sunflower seeds, NFS | same 1.0: `cofid:14-845` ~ `usda:2707585`<br>code 1.0: `usda:2707582` ~ `usda:170563`<br>code 1.0: `usda:2707585` ~ `usda:170563` |
| `usda:2707574` | `cofid:14-849` Trail mix<br>`usda:2707574` Trail mix, NFS | same 1.0: `cofid:14-849` ~ `usda:2707574` |
| `cofid:15-776` | `cofid:15-776` Curry, pea and potato, homemade<br>`cofid:15-781` Curry, potato and pea, homemade | same 1.0: `cofid:15-776` ~ `cofid:15-781` |
| `cofid:16-127` | `cofid:16-127` Red snapper, flesh only, fried in blended oil, weighed with bones and skin<br>`cofid:16-128` Red snapper, flesh only, fried in blended oil, weighed with bones and skin | same 1.0: `cofid:16-127` ~ `cofid:16-128` |
| `usda:171972` | `cofid:16-249` Shrimps, dried<br>`usda:171972` Crustaceans, shrimp, mixed species, canned<br>`usda:2706366` Shrimp, dried<br>`usda:2706367` Shrimp, canned | same 1.0: `cofid:16-249` ~ `usda:2706366`<br>code 1.0: `usda:2706366` ~ `usda:171972`<br>code 1.0: `usda:2706367` ~ `usda:171972` |
| `usda:171401` | `cofid:17-010` Lard<br>`usda:171401` Lard<br>`usda:2710166` Lard | same 1.0: `cofid:17-010` ~ `usda:171401`<br>code 1.0: `usda:2710166` ~ `usda:171401` |
| `usda:330458` | `cofid:17-031` Oil, coconut<br>`usda:171412` Oil, coconut<br>`usda:2710182` Coconut oil<br>`usda:330458` Oil, coconut | same 1.0: `cofid:17-031` ~ `usda:171412`<br>code 1.0: `usda:330458` ~ `usda:171412`<br>code 1.0: `usda:2710182` ~ `usda:171412` |
| `usda:748323` | `cofid:17-033` Oil, corn<br>`usda:171029` Oil, corn, industrial and retail, all purpose salad or cooking<br>`usda:2710183` Corn oil<br>`usda:748323` Oil, corn | same 1.0: `cofid:17-033` ~ `usda:748323`<br>code 1.0: `usda:748323` ~ `usda:171029`<br>code 1.0: `usda:2710183` ~ `usda:171029` |
| `usda:171028` | `cofid:17-036` Oil, grapeseed<br>`usda:171028` Oil, grapeseed | same 1.0: `cofid:17-036` ~ `usda:171028` |
| `usda:171427` | `cofid:17-037` Oil, hazelnut<br>`usda:171427` Oil, hazelnut | same 1.0: `cofid:17-037` ~ `usda:171427` |
| `usda:171015` | `cofid:17-039` Oil, palm<br>`usda:171015` Oil, palm | same 1.0: `cofid:17-039` ~ `usda:171015` |
| `usda:1750350` | `cofid:17-042` Oil, safflower<br>`usda:171027` Oil, safflower, salad or cooking, high oleic (primary safflower oil of commerce)<br>`usda:1750350` Oil, safflower<br>`usda:2710189` Safflower oil | same 1.0: `cofid:17-042` ~ `usda:1750350`<br>code 1.0: `usda:1750350` ~ `usda:171027`<br>code 1.0: `usda:2710189` ~ `usda:171027` |
| `usda:1750349` | `cofid:17-045` Oil, sunflower<br>`usda:1750349` Oil, sunflower | same 1.0: `cofid:17-045` ~ `usda:1750349` |
| `usda:168820` | `cofid:17-059` Molasses<br>`usda:168820` Molasses<br>`usda:2710283` Molasses | same 1.0: `cofid:17-059` ~ `usda:168820`<br>code 1.0: `usda:2710283` ~ `usda:168820` |
| `usda:168836` | `cofid:17-064` Syrup, corn, dark<br>`usda:168836` Syrups, corn, dark | same 1.0: `cofid:17-064` ~ `usda:168836` |
| `usda:168819` | `cofid:17-078` Marmalade<br>`usda:168819` Marmalade, orange<br>`usda:2710303` Marmalade | same 1.0: `cofid:17-078` ~ `usda:2710303`<br>code 1.0: `usda:2710303` ~ `usda:168819` |
| `usda:171833` | `cofid:17-314` Horseradish sauce<br>`usda:171833` Sauce, horseradish<br>`usda:2710174` Horseradish sauce | same 1.0: `cofid:17-314` ~ `usda:2710174`<br>code 1.0: `usda:2710174` ~ `usda:171833` |
| `usda:790508` | `cofid:17-685` Butter, salted<br>`usda:173410` Butter, salted<br>`usda:2710155` Butter, stick<br>`usda:790508` Butter, stick, salted | same 1.0: `cofid:17-685` ~ `usda:173410`<br>code 1.0: `usda:790508` ~ `usda:173410`<br>code 1.0: `usda:2710155` ~ `usda:173410` |
| `usda:171146` | `cofid:17-696` Soup, chicken, cream of, canned, condensed<br>`usda:171146` Soup, cream of chicken, canned, condensed | unsure 1.0: `cofid:17-696` ~ `usda:171146` |
| `usda:2707460` | `cofid:17-698` Soup, lentil, canned<br>`usda:2707460` Soup, lentil, canned | same 1.0: `cofid:17-698` ~ `usda:2707460` |
| `usda:174523` | `cofid:17-705` Barbecue sauce<br>`usda:174523` Sauce, barbecue<br>`usda:2709750` Barbecue sauce | same 1.0: `cofid:17-705` ~ `usda:2709750`<br>code 1.0: `usda:2709750` ~ `usda:174523` |
| `usda:2710111` | `cofid:17-712` Soup, vegetable, canned<br>`usda:2710111` Soup, vegetable, canned | same 1.0: `cofid:17-712` ~ `usda:2710111` |
| `usda:169378` | `cofid:17-718` Pickle, sweet<br>`usda:169378` Pickles, cucumber, sweet (includes bread and butter pickles)<br>`usda:2710080` Pickles, sweet | same 1.0: `cofid:17-718` ~ `usda:2710080`<br>code 1.0: `usda:2710080` ~ `usda:169378` |
| `usda:171610` | `cofid:17-723` Worcestershire sauce<br>`usda:171610` Sauce, worcestershire<br>`usda:2707447` Worcestershire sauce | same 1.0: `cofid:17-723` ~ `usda:2707447`<br>code 1.0: `usda:2707447` ~ `usda:171610` |
| `usda:2710624` | `cofid:17-768` Liqueurs, cream<br>`usda:2710624` Liqueur, cream | same 1.0: `cofid:17-768` ~ `usda:2710624` |
| `cofid:18-470` | `cofid:18-470` Beef, mince, stewed<br>`cofid:19-607` Beef, mince, stewed | same 1.0: `cofid:18-470` ~ `cofid:19-607` |
| `usda:2705878` | `cofid:19-496` Ham<br>`usda:2705878` Ham | same 1.0: `cofid:19-496` ~ `usda:2705878` |
| `usda:2706179` | `cofid:19-516` Chorizo<br>`usda:2706179` Chorizo | same 1.0: `cofid:19-516` ~ `usda:2706179` |
| `usda:1104705` | `usda:1104705` Flour, soy, defatted<br>`usda:174275` Soy flour, defatted<br>`usda:2707451` Textured vegetable protein, dry | code 1.0: `usda:1104705` ~ `usda:174275`<br>code 1.0: `usda:2707451` ~ `usda:174275` |
| `usda:1104766` | `usda:1104766` Flour, soy, full-fat<br>`usda:174273` Soy flour, full-fat, raw | code 1.0: `usda:1104766` ~ `usda:174273` |
| `usda:1104812` | `usda:1104812` Flour, rice, brown<br>`usda:168898` Rice flour, brown | code 1.0: `usda:1104812` ~ `usda:168898` |
| `usda:1105314` | `usda:1105314` Bananas, ripe and slightly ripe, raw<br>`usda:173944` Bananas, raw<br>`usda:2709224` Banana, raw | code 1.0: `usda:1105314` ~ `usda:173944`<br>same 1.0: `usda:173944` ~ `usda:2709224` |
| `usda:167517` | `usda:167517` Waffle, buttermilk, frozen, ready-to-heat, toasted<br>`usda:2708313` Waffle, plain, frozen | code 1.0: `usda:2708313` ~ `usda:167517` |
| `usda:167520` | `usda:167520` Pie Crust, Cookie-type, Graham Cracker, Ready Crust<br>`usda:2708018` Pie shell, graham cracker | code 1.0: `usda:2708018` ~ `usda:167520` |
| `usda:167532` | `usda:167532` Bread, white wheat<br>`usda:2707639` Bread, white, special formula, added fiber<br>`usda:2707706` Bread, whole grain white<br>`usda:2707707` Bread, whole grain white, toasted | code 1.0: `usda:2707639` ~ `usda:167532`<br>code 1.0: `usda:2707706` ~ `usda:167532`<br>code 1.0: `usda:2707707` ~ `usda:167532` |
| `usda:167533` | `usda:167533` Bagels, wheat<br>`usda:171852` Bagels, multigrain<br>`usda:172666` Bagels, oat bran<br>`usda:174092` Bagels, whole grain white<br>`usda:2707708` Bagel, whole grain white<br>`usda:2707732` Bagel, wheat<br>`usda:2707733` Bagel, whole wheat<br>`usda:2707737` Bagel, wheat bran<br>`usda:2707762` Bagel, pumpernickel<br>`usda:2707772` Bagel, oat bran<br>`usda:2707785` Bagel, multigrain | code 1.0: `usda:2707708` ~ `usda:167533`<br>code 1.0: `usda:2707732` ~ `usda:167533`<br>code 1.0: `usda:2707733` ~ `usda:167533`<br>code 1.0: `usda:2707737` ~ `usda:167533`<br>code 1.0: `usda:2707762` ~ `usda:167533`<br>code 1.0: `usda:2707772` ~ `usda:167533`<br>code 1.0: `usda:2707785` ~ `usda:167533`<br>same 1.0: `usda:171852` ~ `usda:2707785`<br>same 1.0: `usda:172666` ~ `usda:2707772`<br>same 1.0: `usda:174092` ~ `usda:2707708` |
| `usda:167534` | `usda:167534` Cream puff, eclair, custard or cream filled, iced<br>`usda:2708031` Cream puff, eclair, custard or cream filled, iced | code 1.0: `usda:2708031` ~ `usda:167534` |
| `usda:2758996` | `usda:167535` Tortillas, ready-to-bake or -fry, flour, shelf stable<br>`usda:2758996` Tortilla, wheat flour, shelf stable | code 1.0: `usda:2758996` ~ `usda:167535` |
| `usda:167536` | `usda:167536` Snacks, beef jerky, chopped and formed<br>`usda:2705860` Beef jerky | code 1.0: `usda:2705860` ~ `usda:167536` |
| `usda:167537` | `usda:167537` Snacks, corn-based, extruded, chips, plain<br>`usda:2708198` Corn chips, plain (Fritos) | code 1.0: `usda:2708198` ~ `usda:167537` |
| `usda:167541` | `usda:167541` Snacks, fruit leather, rolls<br>`usda:2710367` Candy, fruit snacks<br>`usda:2710368` Candy, fruit leather | code 1.0: `usda:2710367` ~ `usda:167541`<br>code 1.0: `usda:2710368` ~ `usda:167541` |
| `usda:167542` | `usda:167542` Snacks, granola bars, hard, plain<br>`usda:2708094` Cereal or granola bar (General Mills Nature Valley Crunchy Granola Bar)<br>`usda:2708101` Cereal or Granola bar, NFS<br>`usda:2708106` Cereal or granola bar, peanuts , oats, sugar, wheat germ | code 1.0: `usda:2708094` ~ `usda:167542`<br>code 1.0: `usda:2708101` ~ `usda:167542`<br>code 1.0: `usda:2708106` ~ `usda:167542` |
| `usda:167547` | `usda:167547` Snacks, granola bars, soft, coated, milk chocolate coating, peanut butter<br>`usda:2708111` Cereal or granola bar, coated with non-chocolate coating | code 1.0: `usda:2708111` ~ `usda:167547` |
| `usda:167550` | `usda:167550` Snacks, popcorn, cakes<br>`usda:2708165` Popcorn cake | code 1.0: `usda:2708165` ~ `usda:167550` |
| `usda:167553` | `usda:167553` Snacks, potato chips, made from dried potatoes, reduced fat<br>`usda:2709437` Potato chips, restructured, reduced fat, lightly salted | code 1.0: `usda:2709437` ~ `usda:167553` |
| `usda:167555` | `usda:167555` Snacks, pretzels, hard, plain, salted<br>`usda:2708247` Pretzels, NFS<br>`usda:2708248` Pretzels, hard, NFS<br>`usda:2708249` Pretzels, hard, plain, salted | code 1.0: `usda:2708247` ~ `usda:167555`<br>code 1.0: `usda:2708248` ~ `usda:167555`<br>code 1.0: `usda:2708249` ~ `usda:167555` |
| `usda:167558` | `usda:167558` Snacks, tortilla chips, plain, white corn, salted<br>`usda:2708202` Tortilla chips, plain | code 1.0: `usda:2708202` ~ `usda:167558` |
| `usda:167559` | `usda:167559` Snacks, tortilla chips, nacho cheese<br>`usda:2708204` Tortilla chips, flavored<br>`usda:2708206` Tortilla chips, nacho cheese flavor (Doritos)<br>`usda:2708208` Tortilla chips, other flavors (Doritos) | code 1.0: `usda:2708204` ~ `usda:167559`<br>code 1.0: `usda:2708206` ~ `usda:167559`<br>code 1.0: `usda:2708208` ~ `usda:167559` |
| `usda:167571` | `usda:167571` Candies, white chocolate<br>`usda:2710339` White chocolate candy | code 1.0: `usda:2710339` ~ `usda:167571` |
| `usda:167572` | `usda:167572` Ice creams, vanilla, light<br>`usda:2705634` Ice cream, soft serve, vanilla | code 1.0: `usda:2705634` ~ `usda:167572` |
| `usda:167573` | `usda:167573` Ice creams, vanilla, rich<br>`usda:2705636` Gelato, vanilla | code 1.0: `usda:2705636` ~ `usda:167573` |
| `usda:167575` | `usda:167575` Ice creams, vanilla<br>`usda:2705630` Ice cream, vanilla | code 1.0: `usda:2705630` ~ `usda:167575` |
| `usda:167577` | `usda:167577` Sherbet, orange<br>`usda:2705677` Sherbet, all flavors | code 1.0: `usda:2705677` ~ `usda:167577` |
| `usda:167585` | `usda:167585` Ice creams, chocolate, light<br>`usda:173465` Ice cream, soft serve, chocolate<br>`usda:2705635` Ice cream, soft serve, chocolate | code 1.0: `usda:2705635` ~ `usda:167585`<br>same 1.0: `usda:173465` ~ `usda:2705635` |
| `usda:167587` | `usda:167587` Candies, milk chocolate<br>`usda:2710328` Chocolate candy | code 1.0: `usda:2710328` ~ `usda:167587` |
| `usda:167606` | `usda:167606` Sweet Potatoes, french fried, frozen as packaged, salt added in processing<br>`usda:2709711` Sweet potato fries, frozen<br>`usda:2709714` Sweet potato fries, school<br>`usda:2709717` Sweet potato tots, school | code 1.0: `usda:2709711` ~ `usda:167606`<br>code 1.0: `usda:2709714` ~ `usda:167606`<br>code 1.0: `usda:2709717` ~ `usda:167606` |
| `usda:334720` | `usda:167661` Restaurant, Latino, pupusas con frijoles (pupusas, bean)<br>`usda:2708609` Pupusa, with beans<br>`usda:334720` Restaurant, Latino, pupusas con frijoles (pupusas, bean) | code 1.0: `usda:334720` ~ `usda:167661`<br>code 1.0: `usda:2708609` ~ `usda:167661` |
| `usda:167662` | `usda:167662` Restaurant, Latino, pupusas con queso (pupusas, cheese)<br>`usda:2708608` Pupusa, cheese only | code 1.0: `usda:2708608` ~ `usda:167662` |
| `usda:167663` | `usda:167663` Restaurant, Latino, pupusas del cerdo (pupusas, pork)<br>`usda:2708610` Pupusa, meat | code 1.0: `usda:2708610` ~ `usda:167663` |
| `usda:167664` | `usda:167664` Restaurant, Latino, tamale, corn<br>`usda:2708574` Tamale, no meat | code 1.0: `usda:2708574` ~ `usda:167664` |
| `usda:167665` | `usda:167665` Restaurant, Mexican, spanish rice<br>`usda:2709084` Spanish rice, from restaurant | code 1.0: `usda:2709084` ~ `usda:167665` |
| `usda:334536` | `usda:167668` Restaurant, Chinese, fried rice, without meat<br>`usda:2708951` Rice, fried, meatless<br>`usda:2708952` Rice, fried, NFS<br>`usda:334536` Restaurant, Chinese, fried rice, without meat | code 1.0: `usda:334536` ~ `usda:167668`<br>code 1.0: `usda:2708951` ~ `usda:167668`<br>code 1.0: `usda:2708952` ~ `usda:167668` |
| `usda:167675` | `usda:167675` Restaurant, Chinese, general tso's chicken<br>`usda:2706794` General Tso chicken | code 1.0: `usda:2706794` ~ `usda:167675` |
| `usda:167676` | `usda:167676` Restaurant, Chinese, kung pao chicken<br>`usda:2706796` Kung pao chicken | code 1.0: `usda:2706796` ~ `usda:167676` |
| `usda:167677` | `usda:167677` Restaurant, Chinese, vegetable lo mein, without meat<br>`usda:2708798` Lo mein, NFS<br>`usda:2708799` Lo mein, meatless | code 1.0: `usda:2708798` ~ `usda:167677`<br>code 1.0: `usda:2708799` ~ `usda:167677` |
| `usda:167678` | `usda:167678` Restaurant, Chinese, chicken and vegetables<br>`usda:2706790` Chicken or turkey and vegetables including carrots, broccoli, and/or dark-green leafy; no potatoes, soy-based sauce | code 1.0: `usda:2706790` ~ `usda:167678` |
| `usda:167679` | `usda:167679` Restaurant, Chinese, orange chicken<br>`usda:2706443` Orange chicken | code 1.0: `usda:2706443` ~ `usda:167679` |
| `usda:167681` | `usda:167681` Beverages, fruit-flavored drink, dry powdered mix, low calorie, with aspartame<br>`usda:2710614` Fruit flavored drink, powdered, not reconstituted, diet | code 1.0: `usda:2710614` ~ `usda:167681` |
| `usda:167684` | `usda:167684` Creamy dressing, made with sour cream and/or buttermilk and oil, reduced calorie<br>`usda:2710215` Salad dressing, light, NFS<br>`usda:2710225` Ranch dressing, light | code 1.0: `usda:2710215` ~ `usda:167684`<br>code 1.0: `usda:2710225` ~ `usda:167684` |
| `usda:167687` | `usda:167687` Whipped topping, frozen, low fat<br>`usda:2705612` Whipped topping, fat free<br>`usda:2705613` Whipped topping, sugar free | code 1.0: `usda:2705612` ~ `usda:167687`<br>code 1.0: `usda:2705613` ~ `usda:167687` |
| `usda:167688` | `usda:167688` Cream substitute, powdered, light<br>`usda:2705608` Coffee creamer, powder, fat free | code 1.0: `usda:2705608` ~ `usda:167688` |
| `usda:167694` | `usda:167694` Sausage, turkey and pork, fresh, bulk, patty or link, cooked<br>`usda:2706202` Turkey or chicken and pork sausage | code 1.0: `usda:2706202` ~ `usda:167694` |
| `usda:167699` | `usda:167699` Salad dressing, blue or roquefort cheese dressing, fat-free<br>`usda:2710229` Blue or roquefort cheese dressing, fat free | code 1.0: `usda:2710229` ~ `usda:167699` |
| `usda:167702` | `usda:167702` Oil, flaxseed, cold pressed<br>`usda:2710185` Flaxseed oil | code 1.0: `usda:2710185` ~ `usda:167702` |
| `usda:167704` | `usda:167704` Salad dressing, bacon and tomato<br>`usda:2710198` Bacon and tomato dressing | code 1.0: `usda:2710198` ~ `usda:167704` |
| `usda:167706` | `usda:167706` Jams, preserves, marmalade, reduced sugar<br>`usda:2710305` Jam or jelly, reduced sugar | code 1.0: `usda:2710305` ~ `usda:167706` |
| `usda:167708` | `usda:167708` Tomato and vegetable juice, low sodium<br>`usda:2709732` Tomato and vegetable juice, 100%, low sodium | code 1.0: `usda:2709732` ~ `usda:167708` |
| `usda:167711` | `usda:167711` Beverages, Chocolate-flavored drink, whey and milk based<br>`usda:2705517` Chocolate milk drink | code 1.0: `usda:2705517` ~ `usda:167711` |
| `usda:167712` | `usda:167712` Pork, cured, bacon, cooked, broiled, pan-fried or roasted, reduced sodium<br>`usda:2705857` Beef, bacon, reduced sodium, cooked<br>`usda:2705888` Pork bacon, NS as to fresh, smoked or cured, reduced sodium, cooked<br>`usda:2705891` Pork bacon, smoked or cured, reduced sodium, cooked | code 1.0: `usda:2705857` ~ `usda:167712`<br>code 1.0: `usda:2705888` ~ `usda:167712`<br>code 1.0: `usda:2705891` ~ `usda:167712` |
| `usda:167713` | `usda:167713` Turkey, light or dark meat, smoked, cooked, skin and bone removed<br>`usda:2706120` Turkey, light or dark meat, smoked, skin not eaten | code 1.0: `usda:2706120` ~ `usda:167713` |
| `usda:167718` | `usda:167718` Babyfood, juice, pear<br>`usda:2709377` Baby Toddler juice, pear | code 1.0: `usda:2709377` ~ `usda:167718` |
| `usda:167719` | `usda:167719` Chicken, meatless, breaded, fried<br>`usda:2707469` Chicken, meatless, breaded, fried | code 1.0: `usda:2707469` ~ `usda:167719` |
| `usda:167723` | `usda:167723` Alcoholic beverage, rice (sake)<br>`usda:2710691` Wine, rice | code 1.0: `usda:2710691` ~ `usda:167723` |
| `usda:167727` | `usda:167727` Beverages, ABBOTT, ENSURE PLUS, ready-to-drink<br>`usda:2710718` Nutritional drink or shake, ready-to-drink (Ensure Plus) | code 1.0: `usda:2710718` ~ `usda:167727` |
| `usda:167732` | `usda:167732` Babyfood, banana no tapioca, strained<br>`usda:2709365` Baby Toddler bananas, Stage 1<br>`usda:2709366` Baby Toddler bananas, Stage 2 | code 1.0: `usda:2709365` ~ `usda:167732`<br>code 1.0: `usda:2709366` ~ `usda:167732` |
| `usda:167734` | `usda:167734` Breakfast bar, corn flake crust with fruit<br>`usda:2708114` Breakfast bar, NFS<br>`usda:2708116` Breakfast bar, cereal crust with fruit filling, lowfat | code 1.0: `usda:2708114` ~ `usda:167734`<br>code 1.0: `usda:2708116` ~ `usda:167734` |
| `usda:167735` | `usda:167735` Cheese, mozzarella, low sodium<br>`usda:2705724` Cheese, Mozzarella, reduced sodium | code 1.0: `usda:2705724` ~ `usda:167735` |
| `usda:167738` | `usda:167738` Pie fillings, blueberry, canned<br>`usda:2709278` Blueberry pie filling | code 1.0: `usda:2709278` ~ `usda:167738` |
| `usda:167746` | `usda:167746` Lemons, raw, without peel<br>`usda:2709168` Lemon, raw | code 1.0: `usda:2709168` ~ `usda:167746` |
| `usda:167747` | `usda:167747` Lemon juice, raw<br>`usda:2709180` Lemon juice, 100%, NS as to form<br>`usda:2709181` Lemon juice, 100%, freshly squeezed | code 1.0: `usda:2709180` ~ `usda:167747`<br>code 1.0: `usda:2709181` ~ `usda:167747` |
| `usda:167748` | `usda:167748` Lemon juice from concentrate, canned or bottled<br>`usda:2709182` Lemon juice, 100%, canned or bottled | code 1.0: `usda:2709182` ~ `usda:167748` |
| `usda:167753` | `usda:167753` Prune juice, canned<br>`usda:2709331` Prune juice, 100% | code 1.0: `usda:2709331` ~ `usda:167753` |
| `usda:167765` | `usda:167765` Watermelon, raw<br>`usda:2709270` Watermelon, raw<br>`usda:2709333` Watermelon juice, 100% | code 1.0: `usda:2709270` ~ `usda:167765`<br>code 1.0: `usda:2709333` ~ `usda:167765` |
| `usda:167766` | `usda:167766` Maraschino cherries, canned, drained<br>`usda:2709229` Cherries, maraschino | code 1.0: `usda:2709229` ~ `usda:167766` |
| `usda:2003590` | `usda:167771` Apple juice, canned or bottled, unsweetened, with added ascorbic acid<br>`usda:2003590` Apple juice, with added vitamin C, from concentrate, shelf stable | code 1.0: `usda:2003590` ~ `usda:167771` |
| `usda:2346414` | `usda:167772` Applesauce, canned, unsweetened, with added ascorbic acid<br>`usda:2346414` Applesauce, unsweetened, with added vitamin C<br>`usda:2709217` Applesauce, unsweetened | code 1.0: `usda:2346414` ~ `usda:167772`<br>code 1.0: `usda:2709217` ~ `usda:167772` |
| `usda:746773` | `usda:167776` Pears, raw, bartlett (Includes foods for USDA's Food Distribution Program)<br>`usda:746773` Pears, raw, bartlett | code 1.0: `usda:746773` ~ `usda:167776` |
| `usda:2710836` | `usda:167779` Pears, raw, green anjou (Includes foods for USDA's Food Distribution Program)<br>`usda:2710836` Pear, Anjou, green, with skin, raw | code 1.0: `usda:2710836` ~ `usda:167779` |
| `usda:167787` | `usda:167787` Pomegranate juice, bottled<br>`usda:2709330` Pomegranate juice, 100% | code 1.0: `usda:2709330` ~ `usda:167787` |
| `usda:1750340` | `usda:167793` Apples, raw, fuji, with skin (Includes foods for USDA's Food Distribution Program)<br>`usda:1750340` Apples, fuji, with skin, raw | code 1.0: `usda:1750340` ~ `usda:167793` |
| `usda:167796` | `usda:167796` Fruit juice smoothie, NAKED JUICE, GREEN MACHINE<br>`usda:2710150` Fruit and vegetable smoothie, bottled | code 1.0: `usda:2710150` ~ `usda:167796` |
| `usda:167800` | `usda:167800` Apple juice, canned or bottled, unsweetened, with added ascorbic acid, calcium, and potassium<br>`usda:2709321` Apple juice, 100%, with calcium added | code 1.0: `usda:2709321` ~ `usda:167800` |
| `usda:167870` | `usda:167870` Pork, cured, feet, pickled<br>`usda:2705899` Pork, pig's feet, pickled | code 1.0: `usda:2705899` ~ `usda:167870` |
| `usda:167886` | `usda:167886` Pork, cured, ham, extra lean and regular, canned, roasted<br>`usda:2705880` Ham, canned<br>`usda:2705881` Ham, ground | code 1.0: `usda:2705880` ~ `usda:167886`<br>code 1.0: `usda:2705881` ~ `usda:167886` |
| `usda:2514745` | `usda:167902` Pork, fresh, ground, raw<br>`usda:2514745` Pork, ground, raw | code 1.0: `usda:2514745` ~ `usda:167902` |
| `usda:167927` | `usda:167927` Toaster Pastries, fruit, frosted (include apples, blueberry, cherry, strawberry)<br>`usda:2708077` Breakfast tart | code 1.0: `usda:2708077` ~ `usda:167927` |
| `usda:167929` | `usda:167929` Muffin, blueberry, commercially prepared, low-fat<br>`usda:2707831` Muffin, fruit, low fat | code 1.0: `usda:2707831` ~ `usda:167929` |
| `usda:167933` | `usda:167933` Crackers, whole-wheat, reduced fat<br>`usda:2708183` Crackers, woven wheat, reduced fat | code 1.0: `usda:2708183` ~ `usda:167933` |
| `usda:167934` | `usda:167934` Crackers, wheat, reduced fat<br>`usda:2708149` Crackers, butter, reduced fat<br>`usda:2708187` Crackers, wheat, reduced fat | code 1.0: `usda:2708149` ~ `usda:167934`<br>code 1.0: `usda:2708187` ~ `usda:167934` |
| `usda:167935` | `usda:167935` Bread, pan dulce, sweet yeast bread<br>`usda:2707674` Pan Dulce, no topping | code 1.0: `usda:2707674` ~ `usda:167935` |
| `usda:167939` | `usda:167939` Garlic bread, frozen<br>`usda:2707628` Garlic bread, from frozen | code 1.0: `usda:2707628` ~ `usda:167939` |
| `usda:167940` | `usda:167940` Cinnamon buns, frosted (includes honey buns)<br>`usda:2707668` Roll, sweet, cinnamon bun, frosted<br>`usda:2707672` Roll, sweet, with fruit, frosted, diet | code 1.0: `usda:2707668` ~ `usda:167940`<br>code 1.0: `usda:2707672` ~ `usda:167940` |
| `usda:167941` | `usda:167941` Crackers, cheese, reduced fat<br>`usda:2708153` Crackers, cheese, reduced fat | code 1.0: `usda:2708153` ~ `usda:167941` |
| `usda:167942` | `usda:167942` Crackers, saltines, whole wheat (includes multi-grain)<br>`usda:2708169` Crackers, saltine, multigrain | code 1.0: `usda:2708169` ~ `usda:167942` |
| `usda:167943` | `usda:167943` Bread, potato<br>`usda:2707642` Bread, potato<br>`usda:2707643` Bread, potato, toasted | code 1.0: `usda:2707642` ~ `usda:167943`<br>code 1.0: `usda:2707643` ~ `usda:167943` |
| `usda:167944` | `usda:167944` Bread, cheese<br>`usda:2707618` Bread, cheese<br>`usda:2707619` Bread, cheese, toasted | code 1.0: `usda:2707618` ~ `usda:167944`<br>code 1.0: `usda:2707619` ~ `usda:167944` |
| `usda:167945` | `usda:167945` Focaccia, Italian flatbread, plain<br>`usda:2707612` Focaccia, Italian, plain | code 1.0: `usda:2707612` ~ `usda:167945` |
| `usda:167946` | `usda:167946` SCHIFF,TIGER'S MILK BAR<br>`usda:2708125` Nutrition bar (Tiger's Milk) | code 1.0: `usda:2708125` ~ `usda:167946` |
| `usda:167948` | `usda:167948` Snacks, corn-based, extruded, onion-flavor<br>`usda:2708245` Onion flavored rings | code 1.0: `usda:2708245` ~ `usda:167948` |
| `usda:167949` | `usda:167949` Snacks, corn-based, extruded, puffs or twists, cheese-flavor<br>`usda:2708200` Cheese flavored corn snacks<br>`usda:2708203` Cheese flavored corn snacks (Cheetos) | code 1.0: `usda:2708200` ~ `usda:167949`<br>code 1.0: `usda:2708203` ~ `usda:167949` |
| `usda:167950` | `usda:167950` Snacks, KRAFT, CORNNUTS, plain<br>`usda:2708195` Corn nuts | code 1.0: `usda:2708195` ~ `usda:167950` |
| `usda:167953` | `usda:167953` Fruit syrup<br>`usda:2710275` Blueberry syrup | code 1.0: `usda:2710275` ~ `usda:167953` |
| `usda:167957` | `usda:167957` Syrup, fruit flavored<br>`usda:2710279` Strawberry drink syrup | code 1.0: `usda:2710279` ~ `usda:167957` |
| `usda:167960` | `usda:167960` Snacks, popcorn, cheese-flavor<br>`usda:2708236` Popcorn, ready-to-eat, cheese flavored | code 1.0: `usda:2708236` ~ `usda:167960` |
| `usda:167961` | `usda:167961` Snacks, pork skins, plain<br>`usda:2705902` Pork skin rinds | code 1.0: `usda:2705902` ~ `usda:167961` |
| `usda:167962` | `usda:167962` Snacks, potato chips, barbecue-flavor<br>`usda:2709423` Potato chips, barbecue flavored<br>`usda:2709424` Potato chips, sour cream and onion flavored<br>`usda:2709425` Potato chips, cheese flavored<br>`usda:2709426` Potato chips, other flavored<br>`usda:2709428` Potato chips, ruffled, barbecue flavored<br>`usda:2709429` Potato chips, ruffled, sour cream and onion flavored<br>`usda:2709430` Potato chips, ruffled, cheese flavored<br>`usda:2709431` Potato chips, ruffled, other flavored | code 1.0: `usda:2709423` ~ `usda:167962`<br>code 1.0: `usda:2709424` ~ `usda:167962`<br>code 1.0: `usda:2709425` ~ `usda:167962`<br>code 1.0: `usda:2709426` ~ `usda:167962`<br>code 1.0: `usda:2709428` ~ `usda:167962`<br>code 1.0: `usda:2709429` ~ `usda:167962`<br>code 1.0: `usda:2709430` ~ `usda:167962`<br>code 1.0: `usda:2709431` ~ `usda:167962` |
| `usda:167964` | `usda:167964` Snacks, M&M MARS, COMBOS Snacks Cheddar Cheese Pretzel<br>`usda:2708264` Pretzels, hard, filled, NFS<br>`usda:2708265` Pretzels, hard, cheese filled | code 1.0: `usda:2708264` ~ `usda:167964`<br>code 1.0: `usda:2708265` ~ `usda:167964` |
| `usda:167974` | `usda:167974` Candies, caramels<br>`usda:2710354` Candy, caramel | same 1.0: `usda:167974` ~ `usda:2710354` |
| `usda:167976` | `usda:167976` Candies, semisweet chocolate<br>`usda:2710333` Chocolate chips | code 1.0: `usda:2710333` ~ `usda:167976` |
| `usda:167978` | `usda:167978` Candies, sweet chocolate coated fondant<br>`usda:2710344` Chocolate candy, cream filled | code 1.0: `usda:2710344` ~ `usda:167978` |
| `usda:167989` | `usda:167989` Candies, gumdrops, starch jelly pieces<br>`usda:2710352` Candy, licorice<br>`usda:2710359` Candy, gummy | code 1.0: `usda:2710352` ~ `usda:167989`<br>code 1.0: `usda:2710359` ~ `usda:167989` |
| `usda:167990` | `usda:167990` Candies, hard<br>`usda:2710360` Candy, hard<br>`usda:2710361` Candy, lollipop | code 1.0: `usda:2710360` ~ `usda:167990`<br>code 1.0: `usda:2710361` ~ `usda:167990` |
| `usda:167995` | `usda:167995` Candies, marshmallows<br>`usda:2710353` Candy, marshmallow | code 1.0: `usda:2710353` ~ `usda:167995` |
| `usda:2758995` | `usda:168013` Bread, multi-grain (includes whole-grain)<br>`usda:2707776` Bread, multigrain, toasted<br>`usda:2707777` Bread, multigrain<br>`usda:2758995` Bread, mulitgrain, commercial | code 1.0: `usda:2758995` ~ `usda:168013`<br>code 1.0: `usda:2707776` ~ `usda:168013`<br>code 1.0: `usda:2707777` ~ `usda:168013` |
| `usda:168014` | `usda:168014` Cookies, animal crackers (includes arrowroot, tea biscuits)<br>`usda:2707968` Cookie, animal | code 1.0: `usda:2707968` ~ `usda:168014` |
| `usda:334628` | `usda:168067` Restaurant, Latino, tamale, pork<br>`usda:2708570` Tamale, NFS<br>`usda:2708571` Tamale, beef<br>`usda:2708572` Tamale, pork<br>`usda:2708573` Tamale, chicken<br>`usda:2708575` Tamale casserole with meat<br>`usda:334628` Restaurant, Latino, tamale, pork | code 1.0: `usda:334628` ~ `usda:168067`<br>code 1.0: `usda:2708570` ~ `usda:168067`<br>code 1.0: `usda:2708571` ~ `usda:168067`<br>code 1.0: `usda:2708572` ~ `usda:168067`<br>code 1.0: `usda:2708573` ~ `usda:168067`<br>code 1.0: `usda:2708575` ~ `usda:168067` |
| `usda:168072` | `usda:168072` Restaurant, Chinese, beef and vegetables<br>`usda:2706740` Szechuan beef<br>`usda:2706741` Hunan beef | code 1.0: `usda:2706740` ~ `usda:168072`<br>code 1.0: `usda:2706741` ~ `usda:168072` |
| `usda:168081` | `usda:168081` Restaurant, Chinese, sweet and sour chicken<br>`usda:2706435` Sweet and sour chicken or turkey<br>`usda:2706436` Sweet and sour chicken or turkey, without vegetables | code 1.0: `usda:2706435` ~ `usda:168081`<br>code 1.0: `usda:2706436` ~ `usda:168081` |
| `usda:746774` | `usda:168082` Restaurant, Chinese, sweet and sour pork<br>`usda:2706401` Sweet and sour pork<br>`usda:746774` Restaurant, Chinese, sweet and sour pork | code 1.0: `usda:746774` ~ `usda:168082`<br>code 1.0: `usda:2706401` ~ `usda:168082` |
| `usda:168084` | `usda:168084` Restaurant, Chinese, vegetable chow mein, without meat or noodles<br>`usda:2710064` Chow mein or chop suey, meatless, no noodles | code 1.0: `usda:2710064` ~ `usda:168084` |
| `usda:168087` | `usda:168087` Restaurant, Chinese, sesame chicken<br>`usda:2706444` Sesame chicken | code 1.0: `usda:2706444` ~ `usda:168087` |
| `usda:168089` | `usda:168089` Imitation cheese, american or cheddar, low cholesterol<br>`usda:2705777` Imitation cheese | code 1.0: `usda:2705777` ~ `usda:168089` |
| `usda:168095` | `usda:168095` Granola bar, soft, milk chocolate coated, peanut butter<br>`usda:2708109` Cereal or granola bar with nuts, chocolate coated | code 1.0: `usda:2708109` ~ `usda:168095` |
| `usda:168097` | `usda:168097` Cream substitute, liquid, light<br>`usda:2705602` Coffee creamer, liquid, fat free<br>`usda:2705604` Coffee creamer, liquid, fat free, sugar free, flavored<br>`usda:2705605` Coffee creamer, liquid, sugar free, flavored | code 1.0: `usda:2705602` ~ `usda:168097`<br>code 1.0: `usda:2705604` ~ `usda:168097`<br>code 1.0: `usda:2705605` ~ `usda:168097` |
| `usda:168098` | `usda:168098` Cheese, monterey, low fat<br>`usda:2705721` Cheese, Monterey, reduced fat | code 1.0: `usda:2705721` ~ `usda:168098` |
| `usda:168099` | `usda:168099` Creamy dressing, made with sour cream and/or buttermilk and oil, reduced calorie, fat-free<br>`usda:2710236` Ranch dressing, fat free<br>`usda:2710237` Salad dressing, fat free, NFS | code 1.0: `usda:2710236` ~ `usda:168099`<br>code 1.0: `usda:2710237` ~ `usda:168099` |
| `usda:168101` | `usda:168101` Bologna, beef, low fat<br>`usda:2706177` Bologna, reduced fat | code 1.0: `usda:2706177` ~ `usda:168101` |
| `usda:168104` | `usda:168104` Frozen yogurts, chocolate<br>`usda:2705453` Frozen yogurt, chocolate<br>`usda:2705458` Frozen yogurt bar, chocolate | code 1.0: `usda:2705453` ~ `usda:168104`<br>code 1.0: `usda:2705458` ~ `usda:168104` |
| `usda:168106` | `usda:168106` Papad<br>`usda:2707429` Papad, grilled or broiled | code 1.0: `usda:2707429` ~ `usda:168106` |
| `usda:168107` | `usda:168107` Rice cake, cracker (include hain mini rice cakes)<br>`usda:2708162` Rice cake | code 1.0: `usda:2708162` ~ `usda:168107` |
| `usda:168114` | `usda:168114` Cheese, cottage, lowfat, 1% milkfat, no sodium added<br>`usda:2705758` Cheese, cottage, lowfat, low sodium | code 1.0: `usda:2705758` ~ `usda:168114` |
| `usda:2003594` | `usda:168117` Cranberry juice, unsweetened<br>`usda:2003594` Cranberry juice, not fortified, from concentrate, shelf stable<br>`usda:2709324` Cranberry juice, 100%, not a blend | code 1.0: `usda:2003594` ~ `usda:168117`<br>code 1.0: `usda:2709324` ~ `usda:168117` |
| `usda:168120` | `usda:168120` Turkey, light or dark meat, smoked, cooked, with skin, bone removed<br>`usda:2706119` Turkey, light or dark meat, smoked, skin eaten | code 1.0: `usda:2706119` ~ `usda:168120` |
| `usda:168121` | `usda:168121` Cheese, pasteurized process, cheddar or American, low sodium<br>`usda:2705767` Cheese, American, reduced sodium | code 1.0: `usda:2705767` ~ `usda:168121` |
| `usda:168123` | `usda:168123` Beverages, cranberry-apple juice drink, low calorie, with vitamin C added<br>`usda:2710585` Fruit juice drink, with high vitamin C, light<br>`usda:2710588` Cranberry juice drink, with high vitamin C, light | code 1.0: `usda:2710585` ~ `usda:168123`<br>code 1.0: `usda:2710588` ~ `usda:168123` |
| `usda:168124` | `usda:168124` Cheese, swiss, low sodium<br>`usda:2705736` Cheese, Swiss, reduced sodium | code 1.0: `usda:2705736` ~ `usda:168124` |
| `usda:168126` | `usda:168126` Rolls, pumpernickel<br>`usda:174918` Bread, pumpernickel<br>`usda:2707760` Bread, pumpernickel<br>`usda:2707761` Bread, pumpernickel, toasted<br>`usda:2707763` Muffin, English, pumpernickel<br>`usda:2707764` Bread, black<br>`usda:2707765` Bread, black, toasted<br>`usda:2707767` Roll, pumpernickel | same 1.0: `usda:168126` ~ `usda:2707767`<br>code 1.0: `usda:2707760` ~ `usda:174918`<br>code 1.0: `usda:2707761` ~ `usda:174918`<br>code 1.0: `usda:2707763` ~ `usda:174918`<br>code 1.0: `usda:2707764` ~ `usda:174918`<br>code 1.0: `usda:2707765` ~ `usda:174918`<br>code 1.0: `usda:2707767` ~ `usda:174918` |
| `usda:168130` | `usda:168130` Frozen novelties, ice cream type, chocolate or caramel covered, with nuts<br>`usda:2705640` Ice cream candy bar | code 1.0: `usda:2705640` ~ `usda:168130` |
| `usda:168132` | `usda:168132` Frozen novelties, ice type, pop, with low calorie sweetener<br>`usda:2710318` Italian Ice, no sugar added<br>`usda:2710321` Popsicle, no sugar added<br>`usda:2710324` Snow cone, no sugar added | code 1.0: `usda:2710318` ~ `usda:168132`<br>code 1.0: `usda:2710321` ~ `usda:168132`<br>code 1.0: `usda:2710324` ~ `usda:168132` |
| `usda:168136` | `usda:168136` Ice creams, chocolate, rich<br>`usda:2705637` Gelato, chocolate | code 1.0: `usda:2705637` ~ `usda:168136` |
| `usda:168141` | `usda:168141` Cheese, swiss, low fat<br>`usda:2705737` Cheese, Swiss, reduced fat | code 1.0: `usda:2705737` ~ `usda:168141` |
| `usda:168144` | `usda:168144` Babyfood, grape juice, no sugar, canned<br>`usda:2709375` Baby Toddler juice, grape | code 1.0: `usda:2709375` ~ `usda:168144` |
| `usda:327046` | `usda:168153` Kiwifruit, green, raw<br>`usda:2709239` Kiwi fruit, raw<br>`usda:327046` Kiwifruit, green, raw | code 1.0: `usda:327046` ~ `usda:168153`<br>code 1.0: `usda:2709239` ~ `usda:168153` |
| `usda:168154` | `usda:168154` Kumquats, raw<br>`usda:2709167` Kumquat, raw | code 1.0: `usda:2709167` ~ `usda:168154` |
| `usda:168155` | `usda:168155` Limes, raw<br>`usda:2709170` Lime, raw | code 1.0: `usda:2709170` ~ `usda:168155` |
| `usda:168156` | `usda:168156` Lime juice, raw<br>`usda:2709183` Lime juice, 100%, NS as to form<br>`usda:2709184` Lime juice, 100%, freshly squeezed | code 1.0: `usda:2709183` ~ `usda:168156`<br>code 1.0: `usda:2709184` ~ `usda:168156` |
| `usda:168157` | `usda:168157` Lime juice, canned or bottled, unsweetened<br>`usda:2709185` Lime juice, 100%, canned or bottled | code 1.0: `usda:2709185` ~ `usda:168157` |
| `usda:168158` | `usda:168158` Blueberries, dried, sweetened<br>`usda:2709198` Blueberries, dried | code 1.0: `usda:2709198` ~ `usda:168158` |
| `usda:2758978` | `usda:168162` Plums, dried (prunes), uncooked<br>`usda:2709211` Prune, dried<br>`usda:2758978` Plums, dried (prunes), uncooked | code 1.0: `usda:2758978` ~ `usda:168162`<br>code 1.0: `usda:2709211` ~ `usda:168162` |
| `usda:2758979` | `usda:168164` Raisins, golden, seedless<br>`usda:2758979` Raisins, golden, seedless | code 1.0: `usda:2758979` ~ `usda:168164` |
| `usda:168172` | `usda:168172` Strawberries, canned, heavy syrup pack, solids and liquids<br>`usda:2709284` Strawberries, canned | code 1.0: `usda:2709284` ~ `usda:168172` |
| `usda:168173` | `usda:168173` Strawberries, frozen, unsweetened (Includes foods for USDA's Food Distribution Program)<br>`usda:2709285` Strawberries, frozen | code 1.0: `usda:2709285` ~ `usda:168173` |
| `usda:168177` | `usda:168177` Pears, asian, raw<br>`usda:2709255` Pear, Asian, raw | code 1.0: `usda:2709255` ~ `usda:168177` |
| `usda:168179` | `usda:168179` Blueberries, canned, light syrup, drained<br>`usda:2709276` Bluberries, canned | code 1.0: `usda:2709276` ~ `usda:168179` |
| `usda:168187` | `usda:168187` Pineapple juice, canned or bottled, unsweetened, with added ascorbic acid<br>`usda:2709329` Pineapple juice, 100% | code 1.0: `usda:2709329` ~ `usda:168187` |
| `usda:168195` | `usda:168195` Clementines, raw<br>`usda:169105` Tangerines, (mandarin oranges), raw<br>`usda:2709164` Clementine, raw<br>`usda:2709175` Tangerine, raw | same 1.0: `usda:168195` ~ `usda:2709164`<br>code 1.0: `usda:2709164` ~ `usda:169105`<br>code 1.0: `usda:2709175` ~ `usda:169105` |
| `usda:168196` | `usda:168196` Guanabana nectar, canned<br>`usda:2709350` Soursop, nectar | code 1.0: `usda:2709350` ~ `usda:168196` |
| `usda:168197` | `usda:168197` Juice, apple and grape blend, with added ascorbic acid<br>`usda:2709316` Fruit juice blend, 100% juice | code 1.0: `usda:2709316` ~ `usda:168197` |
| `usda:1750339` | `usda:168201` Apples, raw, red delicious, with skin (Includes foods for USDA's Food Distribution Program)<br>`usda:1750339` Apples, red delicious, with skin, raw | code 1.0: `usda:1750339` ~ `usda:168201` |
| `usda:1750343` | `usda:168202` Apples, raw, golden delicious, with skin<br>`usda:1750343` Apples, honeycrisp, with skin, raw | code 1.0: `usda:1750343` ~ `usda:168202` |
| `usda:1750342` | `usda:168203` Apples, raw, granny smith, with skin (Includes foods for USDA's Food Distribution Program)<br>`usda:1750342` Apples, granny smith, with skin, raw | code 1.0: `usda:1750342` ~ `usda:168203` |
| `usda:1750341` | `usda:168204` Apples, raw, gala, with skin (Includes foods for USDA's Food Distribution Program)<br>`usda:1750341` Apples, gala, with skin, raw | code 1.0: `usda:1750341` ~ `usda:168204` |
| `usda:168207` | `usda:168207` Grape juice, canned or bottled, unsweetened, with added ascorbic acid and calcium<br>`usda:2709326` Grape juice, 100%, with calcium added | code 1.0: `usda:2709326` ~ `usda:168207` |
| `usda:168212` | `usda:168212` Cranberry juice blend, 100% juice, bottled, with added vitamin C and calcium<br>`usda:2709318` Cranberry juice blend, 100% juice, with calcium added | code 1.0: `usda:2709318` ~ `usda:168212` |
| `usda:168214` | `usda:168214` Fruit juice smoothie, NAKED JUICE, strawberry banana<br>`usda:2709339` Fruit smoothie, bottled | code 1.0: `usda:2709339` ~ `usda:168214` |
| `usda:2710818` | `usda:168215` Plantains, green, raw<br>`usda:2710818` Plantains, underripe, raw | code 1.0: `usda:2710818` ~ `usda:168215` |
| `usda:168282` | `usda:168282` Pork, cured, ham, center slice, country-style, separable lean only, raw<br>`usda:2705879` Ham, prosciutto | code 1.0: `usda:2705879` ~ `usda:168282` |
| `usda:168322` | `usda:168322` Pork, cured, bacon, pre-sliced, cooked, pan-fried<br>`usda:2705887` Pork bacon, NS as to fresh, smoked or cured, cooked<br>`usda:2705889` Pork bacon, smoked or cured, cooked<br>`usda:2705890` Bacon or side pork, fresh, cooked<br>`usda:2710239` Bacon, for use with vegetables | code 1.0: `usda:2705889` ~ `usda:168322`<br>code 1.0: `usda:2705890` ~ `usda:168322`<br>code 1.0: `usda:2710239` ~ `usda:168322`<br>unsure 0.83: `usda:2705887` ~ `usda:2705889` |
| `usda:168383` | `usda:168383` Canadian bacon, cooked, pan-fried<br>`usda:2705884` Canadian bacon, cooked | code 1.0: `usda:2705884` ~ `usda:168383` |
| `usda:168386` | `usda:168386` Artichokes, (globe or french), cooked, boiled, drained, without salt<br>`usda:2709766` Artichoke | code 1.0: `usda:2709766` ~ `usda:168386` |
| `usda:168407` | `usda:168407` Cress, garden, raw<br>`usda:2709586` Cress, raw | code 1.0: `usda:2709586` ~ `usda:168407` |
| `usda:2346406` | `usda:168409` Cucumber, with peel, raw<br>`usda:2346406` Cucumber, with peel, raw<br>`usda:2709784` Cucumber, raw | code 1.0: `usda:2346406` ~ `usda:168409`<br>code 1.0: `usda:2709784` ~ `usda:168409` |
| `usda:2758981` | `usda:168411` Edamame, frozen, prepared<br>`usda:2758981` Edamame, frozen, prepared | code 1.0: `usda:2758981` ~ `usda:168411` |
| `usda:2346390` | `usda:168431` Lettuce, red leaf, raw<br>`usda:2346390` Lettuce, leaf, red, raw<br>`usda:2709790` Lettuce, Boston, raw | code 1.0: `usda:2346390` ~ `usda:168431`<br>code 1.0: `usda:2709790` ~ `usda:168431` |
| `usda:2003601` | `usda:168434` Mushrooms, brown, italian, or crimini, raw<br>`usda:2003601` Mushroom, crimini | code 1.0: `usda:2003601` ~ `usda:168434` |
| `usda:2261422` | `usda:168446` Potato flour<br>`usda:2261422` Flour, potato | code 1.0: `usda:2261422` ~ `usda:168446` |
| `usda:168454` | `usda:168454` Rutabagas, raw<br>`usda:2709804` Rutabaga, raw | code 1.0: `usda:2709804` ~ `usda:168454` |
| `usda:168464` | `usda:168464` Squash, summer, crookneck and straightneck, raw<br>`usda:2709807` Summer squash, yellow, raw | code 1.0: `usda:2709807` ~ `usda:168464` |
| `usda:2685571` | `usda:168472` Squash, winter, acorn, raw<br>`usda:2685571` Squash, winter, acorn, raw | code 1.0: `usda:2685571` ~ `usda:168472` |
| `usda:168505` | `usda:168505` Beans, snap, green, canned, no salt added, drained solids<br>`usda:2709865` Green beans, canned, reduced sodium, cooked, no added fat | code 1.0: `usda:2709865` ~ `usda:168505` |
| `usda:324653` | `usda:168558` Pickles, cucumber, dill or kosher dill<br>`usda:2710078` Pickles, dill<br>`usda:324653` Pickles, cucumber, dill or kosher dill | code 1.0: `usda:324653` ~ `usda:168558`<br>code 1.0: `usda:2710078` ~ `usda:168558` |
| `usda:168559` | `usda:168559` Pimento, canned<br>`usda:2709979` Pimiento | code 1.0: `usda:2709979` ~ `usda:168559` |
| `usda:168561` | `usda:168561` Pickle relish, sweet<br>`usda:2710079` Relish, pickle | code 1.0: `usda:2710079` ~ `usda:168561` |
| `usda:2747664` | `usda:168564` Radicchio, raw<br>`usda:2709613` Radicchio, raw<br>`usda:2747664` Radicchio, raw | code 1.0: `usda:2747664` ~ `usda:168564`<br>code 1.0: `usda:2709613` ~ `usda:168564` |
| `usda:168567` | `usda:168567` Tomatoes, sun-dried<br>`usda:2709727` Sun-dried tomatoes | code 1.0: `usda:2709727` ~ `usda:168567` |
| `usda:2258587` | `usda:168568` Carrots, baby, raw<br>`usda:2258587` Carrots, baby, raw | code 1.0: `usda:2258587` ~ `usda:168568` |
| `usda:168571` | `usda:168571` Nopales, raw<br>`usda:2709776` Cactus, raw | code 1.0: `usda:2709776` ~ `usda:168571` |
| `usda:2262074` | `usda:168588` Nuts, almond butter, plain, without salt added<br>`usda:2262074` Almond butter, creamy<br>`usda:2707534` Almond butter, lower sodium | code 1.0: `usda:2262074` ~ `usda:168588`<br>code 1.0: `usda:2707534` ~ `usda:168588` |
| `usda:323294` | `usda:168596` Nuts, almonds, dry roasted, with salt added<br>`usda:323294` Nuts, almonds, dry roasted, with salt added | code 1.0: `usda:323294` ~ `usda:168596` |
| `usda:168597` | `usda:168597` Nuts, cashew butter, plain, with salt added<br>`usda:2707536` Cashew butter | code 1.0: `usda:2707536` ~ `usda:168597` |
| `usda:168598` | `usda:168598` Nuts, macadamia nuts, dry roasted, with salt added<br>`usda:2707503` Macadamia nuts | code 1.0: `usda:2707503` ~ `usda:168598` |
| `usda:746763` | `usda:168620` Beef, short loin, t-bone steak, bone-in, separable lean only, trimmed to 1/8" fat, choice, cooked, grilled<br>`usda:746763` Beef, short loin, t-bone steak, bone-in, separable lean only, trimmed to 1/8" fat, choice, cooked, grilled | code 1.0: `usda:746763` ~ `usda:168620` |
| `usda:746762` | `usda:168640` Beef, short loin, porterhouse steak, separable lean only, trimmed to 1/8" fat, select, raw<br>`usda:746762` Beef, short loin, porterhouse steak, separable lean only, trimmed to 1/8" fat, select, raw | code 1.0: `usda:746762` ~ `usda:168640` |
| `usda:168746` | `usda:168746` Alcoholic beverage, beer, regular, all<br>`usda:2710616` Beer | code 1.0: `usda:2710616` ~ `usda:168746` |
| `usda:168749` | `usda:168749` Alcoholic beverage, beer, light<br>`usda:2710617` Beer, light | code 1.0: `usda:2710617` ~ `usda:168749` |
| `usda:168755` | `usda:168755` Candies, milk chocolate, with rice cereal<br>`usda:2710331` Chocolate candy with cereal | code 1.0: `usda:2710331` ~ `usda:168755` |
| `usda:168758` | `usda:168758` Toppings, strawberry<br>`usda:2710286` Topping, fruit | code 1.0: `usda:2710286` ~ `usda:168758` |
| `usda:168771` | `usda:168771` Chewing gum<br>`usda:2710371` Chewing gum | code 1.0: `usda:2710371` ~ `usda:168771` |
| `usda:168778` | `usda:168778` Puddings, chocolate, ready-to-eat<br>`usda:2705679` Pudding, chocolate, NFS<br>`usda:2705694` Pudding, chocolate, ready-to-eat | code 1.0: `usda:2705679` ~ `usda:168778`<br>code 1.0: `usda:2705694` ~ `usda:168778` |
| `usda:168782` | `usda:168782` Puddings, rice, ready-to-eat<br>`usda:2705685` Pudding, rice | code 1.0: `usda:2705685` ~ `usda:168782` |
| `usda:168795` | `usda:168795` Frostings, chocolate, creamy, ready-to-eat<br>`usda:2710290` Icing, chocolate | code 1.0: `usda:2710290` ~ `usda:168795` |
| `usda:168809` | `usda:168809` Ice creams, chocolate<br>`usda:2705632` Ice cream, chocolate | code 1.0: `usda:2705632` ~ `usda:168809` |
| `usda:168813` | `usda:168813` Frozen novelties, ice type, pop<br>`usda:2710319` Popsicle, NFS<br>`usda:2710320` Popsicle<br>`usda:2710322` Freezer pop | code 1.0: `usda:2710319` ~ `usda:168813`<br>code 1.0: `usda:2710320` ~ `usda:168813`<br>code 1.0: `usda:2710322` ~ `usda:168813` |
| `usda:168815` | `usda:168815` Frozen yogurts, vanilla, soft-serve<br>`usda:2705454` Frozen yogurt, soft serve, vanilla | code 1.0: `usda:2705454` ~ `usda:168815` |
| `usda:168816` | `usda:168816` Fruit butters, apple<br>`usda:2710302` Fruit butter | code 1.0: `usda:2710302` ~ `usda:168816` |
| `usda:168822` | `usda:168822` Pie fillings, apple, canned<br>`usda:2709219` Apple pie filling | code 1.0: `usda:2709219` ~ `usda:168822` |
| `usda:168834` | `usda:168834` Syrups, chocolate, HERSHEY'S Genuine Chocolate Flavored Lite Syrup<br>`usda:2710277` Chocolate syrup, light | code 1.0: `usda:2710277` ~ `usda:168834` |
| `usda:168835` | `usda:168835` Syrups, chocolate, fudge-type<br>`usda:2710285` Topping, chocolate | code 1.0: `usda:2710285` ~ `usda:168835` |
| `usda:168837` | `usda:168837` Syrups, corn, light<br>`usda:2710274` Corn syrup | code 1.0: `usda:2710274` ~ `usda:168837` |
| `usda:168838` | `usda:168838` Syrups, table blends, pancake, with 2% maple<br>`usda:2710273` Pancake syrup | code 1.0: `usda:2710273` ~ `usda:168838` |
| `usda:168841` | `usda:168841` Toppings, butterscotch or caramel<br>`usda:2710284` Topping, butterscotch or caramel<br>`usda:2710293` Caramel dip, light | code 1.0: `usda:2710284` ~ `usda:168841`<br>code 1.0: `usda:2710293` ~ `usda:168841` |
| `usda:168848` | `usda:168848` Frozen yogurts, chocolate, soft-serve<br>`usda:2705455` Frozen yogurt, soft serve, chocolate | same 1.0: `usda:168848` ~ `usda:2705455` |
| `usda:168849` | `usda:168849` Snacks, banana chips<br>`usda:2709200` Banana chips | code 1.0: `usda:2709200` ~ `usda:168849` |
| `usda:168854` | `usda:168854` Snacks, potato sticks<br>`usda:2709444` Potato sticks, plain | code 1.0: `usda:2709444` ~ `usda:168854` |
| `usda:168860` | `usda:168860` Cheese puffs and twists, corn based, baked, low fat<br>`usda:2708201` Cheese flavored corn snacks, reduced fat | code 1.0: `usda:2708201` ~ `usda:168860` |
| `usda:168861` | `usda:168861` Snacks, granola bar, fruit-filled, nonfat<br>`usda:2708103` Cereal or granola bar, nonfat | code 1.0: `usda:2708103` ~ `usda:168861` |
| `usda:168862` | `usda:168862` Snacks, KELLOGG, KELLOGG'S, NUTRI-GRAIN Cereal Bars, fruit<br>`usda:2708083` Cereal or granola bar (Kellogg's Nutri-Grain Cereal Bar)<br>`usda:2708084` Cereal or granola bar (Kellogg's Nutri-Grain Yogurt Bar) | code 1.0: `usda:2708083` ~ `usda:168862`<br>code 1.0: `usda:2708084` ~ `usda:168862` |
| `usda:168865` | `usda:168865` Snacks, taro chips<br>`usda:2709569` Taro chips | code 1.0: `usda:2709569` ~ `usda:168865` |
| `usda:790085` | `usda:168893` Wheat flour, whole-grain (Includes foods for USDA's Food Distribution Program)<br>`usda:790085` Flour, whole wheat, unenriched | code 1.0: `usda:790085` ~ `usda:168893` |
| `usda:789890` | `usda:168894` Wheat flour, white, all-purpose, enriched, bleached<br>`usda:789890` Flour, wheat, all-purpose, enriched, bleached | code 1.0: `usda:789890` ~ `usda:168894` |
| `usda:790146` | `usda:168896` Wheat flour, white, bread, enriched<br>`usda:790146` Flour, bread, white, enriched, unbleached | code 1.0: `usda:790146` ~ `usda:168896` |
| `usda:168914` | `usda:168914` Rice noodles, cooked<br>`usda:2708356` Rice noodles, cooked | same 1.0: `usda:168914` ~ `usda:2708356` |
| `usda:789951` | `usda:168936` Wheat flour, white, all-purpose, enriched, unbleached<br>`usda:789951` Flour, wheat, all-purpose, enriched, unbleached | code 1.0: `usda:789951` ~ `usda:168936` |
| `usda:168957` | `usda:168957` Pizza rolls, frozen, unprepared<br>`usda:2708686` Pizza rolls | code 1.0: `usda:2708686` ~ `usda:168957` |
| `usda:168965` | `usda:168965` Salisbury steak with gravy, frozen<br>`usda:2706380` Salisbury steak with gravy | code 1.0: `usda:2706380` ~ `usda:168965` |
| `usda:169015` | `usda:169015` Restaurant, family style, fried mozzarella sticks<br>`usda:2705817` Mozzarella sticks, breaded, baked, or fried | code 1.0: `usda:2705817` ~ `usda:169015` |
| `usda:169026` | `usda:169026` Restaurant, family style, coleslaw<br>`usda:2709814` Coleslaw, fast food / restaurant | code 1.0: `usda:2709814` ~ `usda:169026` |
| `usda:169042` | `usda:169042` Babyfood, juice, apple-sweet potato<br>`usda:2709378` Baby Toddler juice, fruit and vegetable | code 1.0: `usda:2709378` ~ `usda:169042` |
| `usda:169046` | `usda:169046` Snacks, potato chips, white, restructured, baked<br>`usda:2709434` Potato chips, baked, plain<br>`usda:2709441` Potato chips, popped, plain<br>`usda:2709443` Potato chips, popped, NFS | code 1.0: `usda:2709434` ~ `usda:169046`<br>code 1.0: `usda:2709441` ~ `usda:169046`<br>unsure 0.75: `usda:2709441` ~ `usda:2709443` |
| `usda:169050` | `usda:169050` Cheese, muenster, low fat<br>`usda:2705727` Cheese, Muenster, reduced fat | code 1.0: `usda:2705727` ~ `usda:169050` |
| `usda:169051` | `usda:169051` Cheese, mozzarella, nonfat<br>`usda:2705725` Cheese, Mozzarella, nonfat or fat free | code 1.0: `usda:2705725` ~ `usda:169051` |
| `usda:169055` | `usda:169055` Salad dressing, caesar dressing, regular<br>`usda:2710199` Caesar dressing | code 1.0: `usda:2710199` ~ `usda:169055` |
| `usda:169056` | `usda:169056` Salad dressing, coleslaw<br>`usda:2710200` Coleslaw dressing | code 1.0: `usda:2710200` ~ `usda:169056` |
| `usda:169057` | `usda:169057` Salad dressing, green goddess, regular<br>`usda:2710208` Avocado dressing | code 1.0: `usda:2710208` ~ `usda:169057` |
| `usda:169063` | `usda:169063` Breakfast bars, oats, sugar, raisins, coconut (include granola bar)<br>`usda:2707933` Cookie, granola<br>`usda:2707944` Cookie, multigrain, high fiber | code 1.0: `usda:2707933` ~ `usda:169063`<br>code 1.0: `usda:2707944` ~ `usda:169063` |
| `usda:169064` | `usda:169064` Pretzels, soft<br>`usda:2708267` Pretzels, soft, NFS | same 1.0: `usda:169064` ~ `usda:2708267` |
| `usda:169066` | `usda:169066` Luncheon slices, meatless<br>`usda:2707471` Luncheon slice, meatless-beef, chicken, salami or turkey | code 1.0: `usda:2707471` ~ `usda:169066` |
| `usda:169067` | `usda:169067` Meatballs, meatless<br>`usda:2707472` Meatball, meatless | code 1.0: `usda:2707472` ~ `usda:169067` |
| `usda:169068` | `usda:169068` Vegetarian fillets<br>`usda:2707478` Vegetarian, fillet | code 1.0: `usda:2707478` ~ `usda:169068` |
| `usda:169071` | `usda:169071` Alcoholic beverage, wine, light<br>`usda:2710693` Wine, light | code 1.0: `usda:2710693` ~ `usda:169071` |
| `usda:169072` | `usda:169072` Sweeteners, tabletop, saccharin (sodium saccharin)<br>`usda:2710269` Sugar substitute, saccharin, powder | code 1.0: `usda:2710269` ~ `usda:169072` |
| `usda:169073` | `usda:169073` Beverage, instant breakfast powder, chocolate, not reconstituted<br>`usda:2710729` Nutritional powder mix (Carnation Instant Breakfast)<br>`usda:2710740` Nutritional powder mix, NFS | code 1.0: `usda:2710729` ~ `usda:169073`<br>code 1.0: `usda:2710740` ~ `usda:169073` |
| `usda:169078` | `usda:169078` Cheese, cottage, with vegetables<br>`usda:2705752` Cheese, cottage, with vegetables | same 1.0: `usda:169078` ~ `usda:2705752` |
| `usda:169081` | `usda:169081` Cheese spread, cream cheese base<br>`usda:2705775` Cheese spread, cream cheese | code 1.0: `usda:2705775` ~ `usda:169081` |
| `usda:169083` | `usda:169083` Soybean, curd cheese<br>`usda:2707437` Soybean curd cheese | code 1.0: `usda:2707437` ~ `usda:169083` |
| `usda:169086` | `usda:169086` Litchis, raw<br>`usda:2709240` Lychee | code 1.0: `usda:2709240` ~ `usda:169086` |
| `usda:169091` | `usda:169091` Mango, dried, sweetened<br>`usda:2709205` Mango, dried | code 1.0: `usda:2709205` ~ `usda:169091` |
| `usda:746770` | `usda:169092` Melons, cantaloupe, raw<br>`usda:2709226` Cantaloupe, raw<br>`usda:746770` Melons, cantaloupe, raw | code 1.0: `usda:746770` ~ `usda:169092`<br>code 1.0: `usda:2709226` ~ `usda:169092` |
| `usda:169096` | `usda:169096` Olives, pickled, canned or bottled, green<br>`usda:2710089` Olives, green | code 1.0: `usda:2710089` ~ `usda:169096` |
| `usda:169097` | `usda:169097` Oranges, raw, all commercial varieties<br>`usda:2709171` Orange, raw | unsure 0.4: `usda:169097` ~ `usda:2709171` |
| `usda:2003591` | `usda:169098` Orange juice, raw (Includes foods for USDA's Food Distribution Program)<br>`usda:169100` Orange juice, chilled, includes from concentrate<br>`usda:2003591` Orange juice, no pulp, not fortified, from concentrate, refrigerated<br>`usda:2003597` Orange juice, no pulp, not fortified, not from concentrate, refrigerated<br>`usda:2709187` Orange juice, 100%,  freshly squeezed | code 1.0: `usda:2003597` ~ `usda:169098`<br>code 1.0: `usda:2709187` ~ `usda:169098`<br>code 1.0: `usda:2003591` ~ `usda:169100`<br>unsure 1.0: `usda:2003591` ~ `usda:2003597` |
| `usda:169106` | `usda:169106` Tangerines, (mandarin oranges), canned, juice pack<br>`usda:2709173` Orange, canned, juice pack | code 1.0: `usda:2709173` ~ `usda:169106` |
| `usda:169108` | `usda:169108` Passion-fruit, (granadilla), purple, raw<br>`usda:2709248` Passion fruit, raw | code 1.0: `usda:2709248` ~ `usda:169108` |
| `usda:169109` | `usda:169109` Passion-fruit juice, purple, raw<br>`usda:2709328` Passion fruit juice, 100% | code 1.0: `usda:2709328` ~ `usda:169109` |
| `usda:169118` | `usda:169118` Pears, raw<br>`usda:2709254` Pear, raw | same 1.0: `usda:169118` ~ `usda:2709254` |
| `usda:2346398` | `usda:169124` Pineapple, raw, all varieties<br>`usda:2346398` Pineapple, raw<br>`usda:2709260` Pineapple, raw<br>`usda:2709264` Pineapple, frozen | code 1.0: `usda:2346398` ~ `usda:169124`<br>code 1.0: `usda:2709260` ~ `usda:169124`<br>code 1.0: `usda:2709264` ~ `usda:169124` |
| `usda:2710817` | `usda:169130` Plantains, yellow, raw<br>`usda:2709560` Plantain, raw<br>`usda:2710817` Plantains, ripe, raw | code 1.0: `usda:2710817` ~ `usda:169130`<br>code 1.0: `usda:2709560` ~ `usda:169130` |
| `usda:169134` | `usda:169134` Pomegranates, raw<br>`usda:2709267` Pomegranate, raw | code 1.0: `usda:2709267` ~ `usda:169134` |
| `usda:321611` | `usda:169143` Beans, snap, green, canned, regular pack, drained solids<br>`usda:2709854` Green beans, canned, cooked, no added fat<br>`usda:321611` Beans, snap, green, canned, regular pack, drained solids | code 1.0: `usda:321611` ~ `usda:169143`<br>code 1.0: `usda:2709854` ~ `usda:169143` |
| `usda:2685576` | `usda:169145` Beets, raw<br>`usda:2685576` Beets, raw<br>`usda:2709770` Beets, raw | code 1.0: `usda:2685576` ~ `usda:169145`<br>code 1.0: `usda:2709770` ~ `usda:169145` |
| `usda:169148` | `usda:169148` Pork, cured, ham -- water added, whole, boneless, separable lean only, heated, roasted<br>`usda:2706210` Ham luncheon meat, loaf type<br>`usda:2710240` Ham, for use with vegetables | code 1.0: `usda:2706210` ~ `usda:169148`<br>code 1.0: `usda:2710240` ~ `usda:169148` |
| `usda:169207` | `usda:169207` Asparagus, canned, drained solids<br>`usda:2709836` Asparagus, canned, cooked, no added fat | code 1.0: `usda:2709836` ~ `usda:169207` |
| `usda:169214` | `usda:169214` Corn, sweet, yellow, canned, whole kernel, drained solids<br>`usda:2709912` Corn, canned, cooked, no added fat | code 1.0: `usda:2709912` ~ `usda:169214` |
| `usda:169215` | `usda:169215` Corn, sweet, yellow, canned, cream style, regular pack<br>`usda:2709923` Corn, creamed | code 1.0: `usda:2709923` ~ `usda:169215` |
| `usda:169226` | `usda:169226` Dandelion greens, raw<br>`usda:2709588` Dandelion greens, raw | code 1.0: `usda:2709588` ~ `usda:169226` |
| `usda:326196` | `usda:169240` Kale, frozen, cooked, boiled, drained, without salt<br>`usda:326196` Kale, frozen, cooked, boiled, drained, without salt | code 1.0: `usda:326196` ~ `usda:169240` |
| `usda:1999628` | `usda:169242` Mushrooms, shiitake, raw<br>`usda:1999628` Mushrooms, shiitake | code 1.0: `usda:1999628` ~ `usda:169242` |
| `usda:2003598` | `usda:169243` Mushrooms, portabella, grilled<br>`usda:2003598` Mushroom, portabella | code 1.0: `usda:2003598` ~ `usda:169243` |
| `usda:746769` | `usda:169247` Lettuce, cos or romaine, raw<br>`usda:746769` Lettuce, cos or romaine, raw | code 1.0: `usda:746769` ~ `usda:169247` |
| `usda:2346388` | `usda:169248` Lettuce, iceberg (includes crisphead types), raw<br>`usda:2346388` Lettuce, iceberg, raw | code 1.0: `usda:2346388` ~ `usda:169248` |
| `usda:2346391` | `usda:169249` Lettuce, green leaf, raw<br>`usda:2346391` Lettuce, leaf, green, raw | code 1.0: `usda:2346391` ~ `usda:169249` |
| `usda:169256` | `usda:169256` Mustard greens, raw<br>`usda:2709606` Mustard greens, raw | code 1.0: `usda:2709606` ~ `usda:169256` |
| `usda:169264` | `usda:169264` Potatoes, french fried, all types, salt added in processing, frozen, home-prepared, oven heated<br>`usda:2709460` Potato, french fries, from frozen, baked | code 1.0: `usda:2709460` ~ `usda:169264` |
| `usda:169286` | `usda:169286` Spinach, canned, regular pack, drained solids<br>`usda:2709617` Spinach, canned, cooked, no added fat | code 1.0: `usda:2709617` ~ `usda:169286` |
| `usda:169291` | `usda:169291` Squash, summer, zucchini, includes skin, raw<br>`usda:2709808` Summer squash, green, raw | code 1.0: `usda:2709808` ~ `usda:169291` |
| `usda:2685570` | `usda:169295` Squash, winter, butternut, raw<br>`usda:2685570` Squash, winter, butternut, raw | code 1.0: `usda:2685570` ~ `usda:169295` |
| `usda:169340` | `usda:169340` Carrots, canned, no salt added, solids and liquids<br>`usda:2709678` Carrots, canned, reduced sodium, cooked, no added fat | code 1.0: `usda:2709678` ~ `usda:169340` |
| `usda:169345` | `usda:169345` Corn, sweet, yellow, canned, no salt added, solids and liquids (Includes foods for USDA's Food Distribution Program)<br>`usda:2709924` Corn, canned, reduced sodium, cooked, no added fat | code 1.0: `usda:2709924` ~ `usda:169345` |
| `usda:169381` | `usda:169381` Catsup, low sodium<br>`usda:2709734` Ketchup, reduced sodium | code 1.0: `usda:2709734` ~ `usda:169381` |
| `usda:2003600` | `usda:169382` Mushrooms, enoki, raw<br>`usda:2003600` Mushroom, enoki | code 1.0: `usda:2003600` ~ `usda:169382` |
| `usda:2258589` | `usda:169383` Peppers, sweet, yellow, raw<br>`usda:2258589` Peppers, bell, yellow, raw | code 1.0: `usda:2258589` ~ `usda:169383` |
| `usda:2747655` | `usda:169385` Fennel, bulb, raw<br>`usda:2709779` Fennel bulb, raw<br>`usda:2747655` Fennel, bulb, raw | code 1.0: `usda:2747655` ~ `usda:169385`<br>code 1.0: `usda:2709779` ~ `usda:169385` |
| `usda:169387` | `usda:169387` Arugula, raw<br>`usda:2709791` Lettuce, arugula, raw | code 1.0: `usda:2709791` ~ `usda:169387` |
| `usda:169389` | `usda:169389` Cauliflower, green, raw<br>`usda:2709771` Broccoflower, raw | code 1.0: `usda:2709771` ~ `usda:169389` |
| `usda:169392` | `usda:169392` Broccoli, chinese, cooked<br>`usda:2709658` Broccoli, Chinese, cooked | same 1.0: `usda:169392` ~ `usda:2709658` |
| `usda:169394` | `usda:169394` Pepper, banana, raw<br>`usda:2709802` Peppers, banana, raw | code 1.0: `usda:2709802` ~ `usda:169394` |
| `usda:2003602` | `usda:169403` Mushrooms, maitake, raw<br>`usda:2003602` Mushroom, maitake | code 1.0: `usda:2003602` ~ `usda:169403` |
| `usda:169404` | `usda:169404` Broccoli, chinese, raw<br>`usda:2709657` Broccoli, chinese, raw | code 1.0: `usda:2709657` ~ `usda:169404` |
| `usda:325524` | `usda:169418` Seeds, sunflower seed kernels, dry roasted, with salt added<br>`usda:325524` Seeds, sunflower seed kernels, dry roasted, with salt added | code 1.0: `usda:325524` ~ `usda:169418` |
| `usda:169423` | `usda:169423` Nuts, mixed nuts, oil roasted, without peanuts, with salt added<br>`usda:170588` Nuts, mixed nuts, oil roasted, without peanuts, without salt added | unsure 1.0: `usda:169423` ~ `usda:170588` |
| `usda:169576` | `usda:169576` Candies, milk chocolate coated raisins<br>`usda:2710348` Chocolate candy with dried fruit | code 1.0: `usda:2710348` ~ `usda:169576` |
| `usda:169577` | `usda:169577` Syrups, table blends, pancake, reduced-calorie<br>`usda:2710280` Pancake syrup, light | code 1.0: `usda:2710280` ~ `usda:169577` |
| `usda:169583` | `usda:169583` Candies, MARS SNACKFOOD US, M&M's Milk Chocolate Candies<br>`usda:2710365` Chocolate candy, candy shell | code 1.0: `usda:2710365` ~ `usda:169583` |
| `usda:169586` | `usda:169586` Candies, peanut brittle, prepared-from-recipe<br>`usda:2710357` Candy, peanut brittle | code 1.0: `usda:2710357` ~ `usda:169586` |
| `usda:169593` | `usda:169593` Cocoa, dry powder, unsweetened<br>`usda:2705587` Cocoa powder, not reconstituted | code 1.0: `usda:2705587` ~ `usda:169593` |
| `usda:169596` | `usda:169596` Gelatin desserts, dry mix, prepared with water<br>`usda:2710310` Gelatin dessert | code 1.0: `usda:2710310` ~ `usda:169596` |
| `usda:169598` | `usda:169598` Gelatin desserts, dry mix, reduced calorie, with aspartame, prepared with water<br>`usda:2710313` Gelatin dessert, sugar free | code 1.0: `usda:2710313` ~ `usda:169598` |
| `usda:169608` | `usda:169608` Puddings, vanilla, ready-to-eat<br>`usda:2705681` Pudding, flavors other than chocolate, NFS<br>`usda:2705692` Pudding, flavors other than chocolate, ready-to-eat | code 1.0: `usda:2705681` ~ `usda:169608`<br>code 1.0: `usda:2705692` ~ `usda:169608` |
| `usda:169614` | `usda:169614` Puddings, tapioca, ready-to-eat<br>`usda:2705687` Pudding, tapioca, made from dry mix<br>`usda:2705696` Pudding, tapioca, ready-to-eat | code 1.0: `usda:2705687` ~ `usda:169614`<br>code 1.0: `usda:2705696` ~ `usda:169614` |
| `usda:169620` | `usda:169620` Frostings, vanilla, creamy, ready-to-eat<br>`usda:2710291` Icing, white | code 1.0: `usda:2710291` ~ `usda:169620` |
| `usda:169638` | `usda:169638` Frozen novelties, ice type, lime<br>`usda:2710317` Italian Ice<br>`usda:2710323` Snow cone | code 1.0: `usda:2710317` ~ `usda:169638`<br>code 1.0: `usda:2710323` ~ `usda:169638` |
| `usda:169641` | `usda:169641` Jams and preserves<br>`usda:2710301` Jam | code 1.0: `usda:2710301` ~ `usda:169641` |
| `usda:169642` | `usda:169642` Jellies<br>`usda:2710300` Jelly | code 1.0: `usda:2710300` ~ `usda:169642` |
| `usda:746784` | `usda:169655` Sugars, granulated<br>`usda:2710257` Sugar, NFS<br>`usda:2710258` Sugar, white, granulated or lump<br>`usda:2710363` Candy, cotton<br>`usda:746784` Sugars, granulated | code 1.0: `usda:746784` ~ `usda:169655`<br>code 1.0: `usda:2710257` ~ `usda:169655`<br>code 1.0: `usda:2710258` ~ `usda:169655`<br>code 1.0: `usda:2710363` ~ `usda:169655` |
| `usda:169656` | `usda:169656` Sugars, powdered<br>`usda:2710259` Sugar, white, confectioner's, powdered | code 1.0: `usda:2710259` ~ `usda:169656` |
| `usda:169657` | `usda:169657` Sweeteners, tabletop, aspartame, EQUAL, packets<br>`usda:2710271` Sugar substitute, aspartame, powder | code 1.0: `usda:2710271` ~ `usda:169657` |
| `usda:169664` | `usda:169664` Toppings, marshmallow cream<br>`usda:2710287` Topping, marshmallow | code 1.0: `usda:2710287` ~ `usda:169664` |
| `usda:169666` | `usda:169666` Toppings, nuts in syrup<br>`usda:2710288` Topping, nuts and syrup | code 1.0: `usda:2710288` ~ `usda:169666` |
| `usda:169674` | `usda:169674` Snacks, granola bars, soft, uncoated, chocolate chip<br>`usda:2708095` Cereal or granola bar (Quaker Chewy Granola Bar) | code 1.0: `usda:2708095` ~ `usda:169674` |
| `usda:169677` | `usda:169677` Snacks, potato chips, plain, salted<br>`usda:2709421` Potato chips, NFS<br>`usda:2709422` Potato chips, plain<br>`usda:2709427` Potato chips, ruffled, plain | code 1.0: `usda:2709422` ~ `usda:169677`<br>code 1.0: `usda:2709427` ~ `usda:169677`<br>unsure 0.67: `usda:2709421` ~ `usda:2709422` |
| `usda:169687` | `usda:169687` Snacks, KELLOGG, KELLOGG'S RICE KRISPIES TREATS Squares<br>`usda:2707938` Cookie, marshmallow, with rice cereal, no bake<br>`usda:2707940` Cookie, marshmallow and peanut butter, with oat cereal, no bake<br>`usda:2707954` Cookie, peanut butter with rice cereal, no bake<br>`usda:2708113` Cereal or granola bar, with rice cereal | code 1.0: `usda:2707938` ~ `usda:169687`<br>code 1.0: `usda:2707940` ~ `usda:169687`<br>code 1.0: `usda:2707954` ~ `usda:169687`<br>code 1.0: `usda:2708113` ~ `usda:169687` |
| `usda:2512379` | `usda:169702` Millet, raw<br>`usda:2512379` Millet, whole grain | code 1.0: `usda:2512379` ~ `usda:169702` |
| `usda:2512380` | `usda:169703` Rice, brown, long-grain, raw (Includes foods for USDA's Food Distribution Program)<br>`usda:2512380` Rice, brown, long grain, unenriched, raw | code 1.0: `usda:2512380` ~ `usda:169703` |
| `usda:2346396` | `usda:169705` Oats (Includes foods for USDA's Food Distribution Program)<br>`usda:2346396` Oats, whole grain, rolled, old fashioned | code 1.0: `usda:2346396` ~ `usda:169705` |
| `usda:790214` | `usda:169714` Rice flour, white, unenriched<br>`usda:790214` Flour, rice, white, unenriched | code 1.0: `usda:790214` ~ `usda:169714` |
| `usda:2710821` | `usda:169726` Wild rice, raw<br>`usda:2710821` Wild rice, dry, raw | code 1.0: `usda:2710821` ~ `usda:169726` |
| `usda:169735` | `usda:169735` Noodles, flat, crunchy, Chinese restaurant<br>`usda:2708179` Crackers, wonton<br>`usda:2708354` Noodles, chow mein | code 1.0: `usda:2708179` ~ `usda:169735`<br>code 1.0: `usda:2708354` ~ `usda:169735` |
| `usda:2512376` | `usda:169739` Barley flour or meal<br>`usda:2512376` Flour, barley | code 1.0: `usda:2512376` ~ `usda:169739` |
| `usda:2003587` | `usda:169745` Spelt, uncooked<br>`usda:2003587` Flour, spelt, whole grain | code 1.0: `usda:2003587` ~ `usda:169745` |
| `usda:2512381` | `usda:169756` Rice, white, long-grain, regular, raw, unenriched<br>`usda:2512381` Rice, white, long grain, unenriched, raw | code 1.0: `usda:2512381` ~ `usda:169756` |
| `usda:790018` | `usda:169761` Wheat flour, white, all-purpose, unenriched<br>`usda:790018` Flour, wheat, all-purpose, unenriched, unbleached | code 1.0: `usda:790018` ~ `usda:169761` |
| `usda:169765` | `usda:169765` Ginger root, pickled, canned, with artificial sweetener<br>`usda:2710082` Ginger root, pickled | code 1.0: `usda:2710082` ~ `usda:169765` |
| `usda:169766` | `usda:169766` Peppers, hot pickled, canned<br>`usda:2710095` Peppers, hot, pickled | code 1.0: `usda:2710095` ~ `usda:169766` |
| `usda:169768` | `usda:169768` Potatoes, mashed, ready-to-eat<br>`usda:2709495` Potato, mashed, ready-to-heat<br>`usda:2709507` Potato, mashed, ready-to-heat, NFS | code 1.0: `usda:2709495` ~ `usda:169768`<br>code 1.0: `usda:2709507` ~ `usda:169768` |
| `usda:169773` | `usda:169773` Potsticker or wonton, pork and vegetable, frozen, unprepared<br>`usda:2708708` Wonton, dumpling or pot sticker, steamed | code 1.0: `usda:2708708` ~ `usda:169773` |
| `usda:169779` | `usda:169779` Dumpling, potato- or cheese-filled, frozen<br>`usda:2708720` Pierogi | code 1.0: `usda:2708720` ~ `usda:169779` |
| `usda:169836` | `usda:169836` Restaurant, family style, french fries<br>`usda:2709462` Potato, french fries, restaurant | code 1.0: `usda:2709462` ~ `usda:169836` |
| `usda:169839` | `usda:169839` Restaurant, family style, macaroni & cheese, from kids' menu<br>`usda:2708812` Macaroni or noodles with cheese, from restaurant | code 1.0: `usda:2708812` ~ `usda:169839` |
| `usda:169850` | `usda:169850` Restaurant, Italian, lasagna with meat<br>`usda:2708752` Lasagna with meat, from restaurant | code 1.0: `usda:2708752` ~ `usda:169850` |
| `usda:169863` | `usda:169863` Snacks, granola bar, with coconut, chocolate coated<br>`usda:2708108` Cereal or granola bar, with coconut, chocolate coated | code 1.0: `usda:2708108` ~ `usda:169863` |
| `usda:169877` | `usda:169877` Salad dressing, caesar, low calorie<br>`usda:2710219` Caesar dressing, light | code 1.0: `usda:2710219` ~ `usda:169877` |
| `usda:169878` | `usda:169878` Syrups, sugar free<br>`usda:2710265` Sugar substitute, stevia, liquid<br>`usda:2710268` Sugar substitute, liquid, NFS | code 1.0: `usda:2710265` ~ `usda:169878`<br>code 1.0: `usda:2710268` ~ `usda:169878` |
| `usda:169879` | `usda:169879` Jellies, no sugar (with sodium saccharin), any flavors<br>`usda:2710304` Jam or jelly, sugar free | code 1.0: `usda:2710304` ~ `usda:169879` |
| `usda:169880` | `usda:169880` Candies, hard, dietetic or low calorie (sorbitol)<br>`usda:2710370` Candy, non chocolate, sugar free | code 1.0: `usda:2710370` ~ `usda:169880` |
| `usda:169881` | `usda:169881` Candies, chocolate covered, low sugar or low calorie<br>`usda:2710349` Chocolate candy, sugar free | code 1.0: `usda:2710349` ~ `usda:169881` |
| `usda:169883` | `usda:169883` Fluid replacement, electrolyte solution (include PEDIALYTE)<br>`usda:2710775` Fluid replacement, electrolyte solution | code 1.0: `usda:2710775` ~ `usda:169883` |
| `usda:169886` | `usda:169886` Chicken, meatless<br>`usda:2707468` Chicken, meatless, NFS | code 1.0: `usda:2707468` ~ `usda:169886` |
| `usda:169887` | `usda:169887` Frankfurter, meatless<br>`usda:2707470` Hot dog, vegetarian | code 1.0: `usda:2707470` ~ `usda:169887` |
| `usda:169892` | `usda:169892` Eggplant, pickled<br>`usda:2710081` Eggplant, pickled | same 1.0: `usda:169892` ~ `usda:2710081` |
| `usda:169893` | `usda:169893` Bacon bits, meatless<br>`usda:2707466` Bacon bits | code 1.0: `usda:2707466` ~ `usda:169893` |
| `usda:169894` | `usda:169894` Butter replacement, without fat, powder<br>`usda:2710163` Butter replacement, powder | code 1.0: `usda:2710163` ~ `usda:169894` |
| `usda:169897` | `usda:169897` Beverage, instant breakfast powder, chocolate, sugar-free, not reconstituted<br>`usda:2710730` Nutritional powder mix, sugar free (Carnation Instant Breakfast) | code 1.0: `usda:2710730` ~ `usda:169897` |
| `usda:169910` | `usda:169910` Mangos, raw<br>`usda:2709242` Mango, raw<br>`usda:2709244` Mango, frozen<br>`usda:2709372` Baby Toddler mangoes | code 1.0: `usda:2709242` ~ `usda:169910`<br>code 1.0: `usda:2709244` ~ `usda:169910`<br>code 1.0: `usda:2709372` ~ `usda:169910` |
| `usda:2710816` | `usda:169911` Melons, honeydew, raw<br>`usda:2709241` Honeydew melon, raw<br>`usda:2710816` Melons, honeydew, raw | code 1.0: `usda:2710816` ~ `usda:169911`<br>code 1.0: `usda:2709241` ~ `usda:169911` |
| `usda:327357` | `usda:169914` Nectarines, raw<br>`usda:2709245` Nectarine, raw<br>`usda:327357` Nectarines, raw | code 1.0: `usda:327357` ~ `usda:169914`<br>code 1.0: `usda:2709245` ~ `usda:169914` |
| `usda:746771` | `usda:169917` Oranges, raw, navels (Includes foods for USDA's Food Distribution Program)<br>`usda:746771` Oranges, raw, navels | code 1.0: `usda:746771` ~ `usda:169917` |
| `usda:169923` | `usda:169923` Orange juice, frozen concentrate, unsweetened, undiluted<br>`usda:2709191` Orange juice, 100%, frozen, not reconstituted | code 1.0: `usda:2709191` ~ `usda:169923` |
| `usda:169925` | `usda:169925` Tangerine juice, raw<br>`usda:2709193` Tangerine juice, 100% | code 1.0: `usda:2709193` ~ `usda:169925` |
| `usda:169926` | `usda:169926` Papayas, raw<br>`usda:2709246` Papaya, raw | code 1.0: `usda:2709246` ~ `usda:169926` |
| `usda:325430` | `usda:169928` Peaches, yellow, raw<br>`usda:2709249` Peach, raw<br>`usda:2709253` Peach, frozen<br>`usda:325430` Peaches, yellow, raw | code 1.0: `usda:325430` ~ `usda:169928`<br>code 1.0: `usda:2709249` ~ `usda:169928`<br>code 1.0: `usda:2709253` ~ `usda:169928` |
| `usda:169934` | `usda:169934` Peaches, dried, sulfured, uncooked<br>`usda:2709207` Peach, dried | code 1.0: `usda:2709207` ~ `usda:169934` |
| `usda:169941` | `usda:169941` Persimmons, japanese, raw<br>`usda:2709259` Persimmon, raw | code 1.0: `usda:2709259` ~ `usda:169941` |
| `usda:169949` | `usda:169949` Plums, raw<br>`usda:2709265` Plum, raw | code 1.0: `usda:2709265` ~ `usda:169949` |
| `usda:169957` | `usda:169957` Mung beans, mature seeds, sprouted, raw<br>`usda:2709764` Sprouts, NFS<br>`usda:2709768` Bean sprouts, raw | code 1.0: `usda:2709764` ~ `usda:169957`<br>code 1.0: `usda:2709768` ~ `usda:169957` |
| `usda:2346400` | `usda:169961` Beans, snap, green, raw<br>`usda:2346400` Beans, snap, green, raw<br>`usda:2709769` Green beans, raw<br>`usda:2710803` Green beans, cooked, as ingredient | code 1.0: `usda:2346400` ~ `usda:169961`<br>code 1.0: `usda:2709769` ~ `usda:169961`<br>code 1.0: `usda:2710803` ~ `usda:169961` |
| `usda:169966` | `usda:169966` Beets, canned, drained solids<br>`usda:2709873` Beets, canned, cooked, no added fat | code 1.0: `usda:2709873` ~ `usda:169966` |
| `usda:746764` | `usda:169983` Carrots, frozen, unprepared (Includes foods for USDA's Food Distribution Program)<br>`usda:746764` Carrots, frozen, unprepared | code 1.0: `usda:746764` ~ `usda:169983` |
| `usda:169994` | `usda:169994` Chives, raw<br>`usda:2709781` Chives, raw | code 1.0: `usda:2709781` ~ `usda:169994` |
| `usda:169997` | `usda:169997` Coriander (cilantro) leaves, raw<br>`usda:2709782` Cilantro, raw | code 1.0: `usda:2709782` ~ `usda:169997` |
| `usda:169998` | `usda:169998` Corn, sweet, yellow, raw<br>`usda:2709783` Corn, raw | code 1.0: `usda:2709783` ~ `usda:169998` |
| `usda:170005` | `usda:170005` Onions, spring or scallions (includes tops and bulb), raw<br>`usda:2709794` Onions, green, raw | code 1.0: `usda:2709794` ~ `usda:170005` |
| `usda:170010` | `usda:170010` Peas, edible-podded, raw<br>`usda:2709806` Snowpeas, raw | code 1.0: `usda:2709806` ~ `usda:170010` |
| `usda:170013` | `usda:170013` Peas, green (includes baby and lesuer types), canned, drained solids, unprepared<br>`usda:2709961` Green peas, canned, cooked, no added fat | code 1.0: `usda:2709961` ~ `usda:170013` |
| `usda:170047` | `usda:170047` Potato puffs, frozen, unprepared<br>`usda:2709515` Potato tots, frozen, baked | code 1.0: `usda:2709515` ~ `usda:170047` |
| `usda:170054` | `usda:170054` Tomato products, canned, sauce<br>`usda:2709748` Spaghetti sauce, fat free | code 1.0: `usda:2709748` ~ `usda:170054` |
| `usda:170062` | `usda:170062` Turnip greens and turnips, frozen, cooked, boiled, drained, without salt<br>`usda:170469` Turnip greens, frozen, cooked, boiled, drained, without salt | same 1.0: `usda:170062` ~ `usda:170469` |
| `usda:170063` | `usda:170063` Vegetable juice cocktail, canned<br>`usda:2709730` Tomato juice cocktail<br>`usda:2709731` Tomato and vegetable juice, 100% | code 1.0: `usda:2709730` ~ `usda:170063`<br>code 1.0: `usda:2709731` ~ `usda:170063` |
| `usda:170067` | `usda:170067` Waterchestnuts, chinese, canned, solids and liquids<br>`usda:2710003` Water Chesnut | code 1.0: `usda:2710003` ~ `usda:170067` |
| `usda:170073` | `usda:170073` Yambean (jicama), raw<br>`usda:2709787` Jicama, raw | code 1.0: `usda:2709787` ~ `usda:170073` |
| `usda:170092` | `usda:170092` Potato pancakes<br>`usda:2709552` Potato pancake | same 1.0: `usda:170092` ~ `usda:2709552` |
| `usda:170094` | `usda:170094` Potatoes, microwaved, cooked in skin, flesh and skin, without salt<br>`usda:170441` Potatoes, microwaved, cooked in skin, flesh, without salt | unsure 1.0: `usda:170094` ~ `usda:170441` |
| `usda:170103` | `usda:170103` Peas, green, canned, no salt added, solids and liquids<br>`usda:2709972` Green peas, canned, reduced sodium, cooked, no added fat | code 1.0: `usda:2709972` ~ `usda:170103` |
| `usda:2258590` | `usda:170108` Peppers, sweet, red, raw<br>`usda:2258590` Peppers, bell, red, raw<br>`usda:2709801` Peppers, sweet, red, raw<br>`usda:2710799` Red pepper, cooked, as ingredient | code 1.0: `usda:2258590` ~ `usda:170108`<br>code 1.0: `usda:2709801` ~ `usda:170108`<br>code 1.0: `usda:2710799` ~ `usda:170108` |
| `usda:170140` | `usda:170140` Turnip greens, frozen, cooked, boiled, drained, with salt<br>`usda:170141` Turnip greens and turnips, frozen, cooked, boiled, drained, with salt | same 1.0: `usda:170140` ~ `usda:170141` |
| `usda:170158` | `usda:170158` Nuts, almonds, dry roasted, without salt added<br>`usda:2707485` Almonds, NFS | code 1.0: `usda:2707485` ~ `usda:170158` |
| `usda:170160` | `usda:170160` Nuts, almond paste<br>`usda:2707535` Almond paste | code 1.0: `usda:2707535` ~ `usda:170160` |
| `usda:2515374` | `usda:170162` Nuts, cashew nuts, raw<br>`usda:2515374` Nuts, cashew nuts, raw | code 1.0: `usda:2515374` ~ `usda:170162` |
| `usda:170169` | `usda:170169` Nuts, coconut meat, raw<br>`usda:2707500` Coconut, fresh | code 1.0: `usda:2707500` ~ `usda:170169` |
| `usda:170171` | `usda:170171` Nuts, coconut cream, canned, sweetened<br>`usda:2707571` Coconut cream, canned, sweetened | code 1.0: `usda:2707571` ~ `usda:170171` |
| `usda:170172` | `usda:170172` Nuts, coconut milk, raw (liquid expressed from grated meat and water)<br>`usda:2707568` Coconut milk, used in cooking | code 1.0: `usda:2707568` ~ `usda:170172` |
| `usda:2515378` | `usda:170178` Nuts, macadamia nuts, raw<br>`usda:2515378` Nuts, macadamia nuts, raw | code 1.0: `usda:2515378` ~ `usda:170178` |
| `usda:2346395` | `usda:170182` Nuts, pecans<br>`usda:2346395` Nuts, pecans, halves, raw<br>`usda:2707521` Pecans, NFS<br>`usda:2707522` Pecans, unroasted | code 1.0: `usda:2346395` ~ `usda:170182`<br>code 1.0: `usda:2707521` ~ `usda:170182`<br>code 1.0: `usda:2707522` ~ `usda:170182` |
| `usda:2515379` | `usda:170184` Nuts, pistachio nuts, raw<br>`usda:2515379` Nuts, pistachio nuts, raw | code 1.0: `usda:2515379` ~ `usda:170184` |
| `usda:170185` | `usda:170185` Nuts, pistachio nuts, dry roasted, without salt added<br>`usda:2707527` Pistachio nuts, NFS | code 1.0: `usda:2707527` ~ `usda:170185` |
| `usda:2346394` | `usda:170187` Nuts, walnuts, english<br>`usda:2346394` Nuts, walnuts, English, halves, raw<br>`usda:2707531` Walnuts, excluding honey roasted | code 1.0: `usda:2346394` ~ `usda:170187`<br>code 1.0: `usda:2707531` ~ `usda:170187` |
| `usda:170190` | `usda:170190` Nuts, chestnuts, european, roasted<br>`usda:2707499` Chestnuts | code 1.0: `usda:2707499` ~ `usda:170190` |
| `usda:170198` | `usda:170198` Beef, cured, breakfast strips, cooked<br>`usda:2705856` Beef, bacon, cooked | code 1.0: `usda:2705856` ~ `usda:170198` |
| `usda:170200` | `usda:170200` Beef, cured, corned beef, brisket, cooked<br>`usda:2705850` Beef, corned | code 1.0: `usda:2705850` ~ `usda:170200` |
| `usda:170204` | `usda:170204` Beef, cured, pastrami<br>`usda:2706183` Pastrami, NFS | code 1.0: `usda:2706183` ~ `usda:170204` |
| `usda:170249` | `usda:170249` Snacks, pretzels, hard, plain, made with enriched flour, unsalted<br>`usda:2708251` Pretzels, hard, plain, unsalted | code 1.0: `usda:2708251` ~ `usda:170249` |
| `usda:170254` | `usda:170254` Snacks, tortilla chips, low fat, unsalted<br>`usda:2708211` Tortilla chips, low fat, unsalted | code 1.0: `usda:2708211` ~ `usda:170254` |
| `usda:170257` | `usda:170257` Sweeteners, tabletop, sucralose, SPLENDA packets<br>`usda:2710263` Sugar substitute, sucralose, powder | code 1.0: `usda:2710263` ~ `usda:170257` |
| `usda:170258` | `usda:170258` Frozen novelties, No Sugar Added, FUDGSICLE pops<br>`usda:2705678` Fudgesicle, light | code 1.0: `usda:2705678` ~ `usda:170258` |
| `usda:170274` | `usda:170274` Candies, chocolate, dark, NFS (45-59% cacao solids 90%; 60-69% cacao solids 5%; 70-85% cacao solids 5%)<br>`usda:2710336` Dark chocolate candy | code 1.0: `usda:2710336` ~ `usda:170274` |
| `usda:170277` | `usda:170277` Sweetener, syrup, agave<br>`usda:2710282` Agave liquid sweetener | code 1.0: `usda:2710282` ~ `usda:170277` |
| `usda:170280` | `usda:170280` Jams, preserves, marmalades, sweetened with fruit juice<br>`usda:2710306` Jam or jelly, fruit juice sweetened | code 1.0: `usda:2710306` ~ `usda:170280` |
| `usda:2512378` | `usda:170286` Buckwheat<br>`usda:2512378` Buckwheat, whole grain | code 1.0: `usda:2512378` ~ `usda:170286` |
| `usda:170301` | `usda:170301` Fast foods, hush puppies<br>`usda:2707819` Hush puppy | code 1.0: `usda:2707819` ~ `usda:170301` |
| `usda:170302` | `usda:170302` Fast food, biscuit<br>`usda:2707803` Biscuit, from fast food / restaurant | code 1.0: `usda:2707803` ~ `usda:170302` |
| `usda:170317` | `usda:170317` Pizza, cheese topping, regular crust, frozen, cooked<br>`usda:2708613` Pizza, cheese, from frozen, thick crust | code 1.0: `usda:2708613` ~ `usda:170317` |
| `usda:170365` | `usda:170365` Fast Food, Pizza Chain, 14" pizza, sausage topping, thick crust<br>`usda:2708652` Pizza with meat other than pepperoni, from restaurant or fast food, thick crust | code 1.0: `usda:2708652` ~ `usda:170365` |
| `usda:170367` | `usda:170367` Fast Food, Pizza Chain, 14" pizza, sausage topping, regular crust<br>`usda:2708649` Pizza with meat other than pepperoni, from restaurant or fast food, NS as to type of crust<br>`usda:2708650` Pizza with meat other than pepperoni, from restaurant or fast food, thin crust<br>`usda:2708651` Pizza with meat other than pepperoni, from restaurant or fast food, medium crust | code 1.0: `usda:2708649` ~ `usda:170367`<br>code 1.0: `usda:2708650` ~ `usda:170367`<br>code 1.0: `usda:2708651` ~ `usda:170367` |
| `usda:170373` | `usda:170373` Pizza, cheese topping, thin crust, frozen, cooked<br>`usda:2708612` Pizza, cheese, from frozen, thin crust | code 1.0: `usda:2708612` ~ `usda:170373` |
| `usda:2747653` | `usda:170375` Beet greens, raw<br>`usda:2709570` Beet greens, raw<br>`usda:2747653` Beet greens, raw | code 1.0: `usda:2747653` ~ `usda:170375`<br>code 1.0: `usda:2709570` ~ `usda:170375` |
| `usda:170381` | `usda:170381` Broccoli raab, raw<br>`usda:2709572` Broccoli raab, raw | code 1.0: `usda:2709572` ~ `usda:170381` |
| `usda:170382` | `usda:170382` Broccoli raab, cooked<br>`usda:2709573` Broccoli raab, cooked | same 1.0: `usda:170382` ~ `usda:2709573` |
| `usda:170392` | `usda:170392` Cabbage, kimchi<br>`usda:2710077` Kimchi | code 1.0: `usda:2710077` ~ `usda:170392` |
| `usda:170396` | `usda:170396` Carrots, canned, regular pack, drained solids<br>`usda:2709666` Carrots, canned, cooked, no added fat | code 1.0: `usda:2709666` ~ `usda:170396` |
| `usda:2685574` | `usda:170406` Collards, raw<br>`usda:2685574` Collards, raw<br>`usda:2709576` Collards, raw | code 1.0: `usda:2685574` ~ `usda:170406`<br>code 1.0: `usda:2709576` ~ `usda:170406` |
| `usda:324317` | `usda:170415` Onion rings, breaded, par fried, frozen, prepared, heated in oven<br>`usda:324317` Onion rings, breaded, par fried, frozen, prepared, heated in oven | code 1.0: `usda:324317` ~ `usda:170415` |
| `usda:170419` | `usda:170419` Peas, green, raw<br>`usda:2709797` Green peas, raw | code 1.0: `usda:2709797` ~ `usda:170419` |
| `usda:2258588` | `usda:170427` Peppers, sweet, green, raw<br>`usda:2258588` Peppers, bell, green, raw<br>`usda:2709800` Peppers, sweet, green, raw<br>`usda:2710798` Green pepper, cooked, as ingredient | code 1.0: `usda:2258588` ~ `usda:170427`<br>code 1.0: `usda:2709800` ~ `usda:170427`<br>code 1.0: `usda:2710798` ~ `usda:170427` |
| `usda:170438` | `usda:170438` Potatoes, boiled, cooked in skin, flesh, without salt<br>`usda:170440` Potatoes, boiled, cooked without skin, flesh, without salt<br>`usda:170520` Potatoes, boiled, cooked without skin, flesh, with salt | unsure 1.0: `usda:170438` ~ `usda:170440`<br>unsure 1.0: `usda:170438` ~ `usda:170520` |
| `usda:170457` | `usda:170457` Tomatoes, red, ripe, raw, year round average<br>`usda:2710795` Tomatoes, cooked, as ingredient | code 1.0: `usda:2710795` ~ `usda:170457` |
| `usda:2003596` | `usda:170458` Tomato juice, canned, with salt added<br>`usda:2003596` Tomato juice, with added ingredients, from concentrate, shelf stable<br>`usda:2709728` Tomato juice, 100% | code 1.0: `usda:2003596` ~ `usda:170458`<br>code 1.0: `usda:2709728` ~ `usda:170458` |
| `usda:2685580` | `usda:170459` Tomato products, canned, paste, without salt added (Includes foods for USDA's Food Distribution Program)<br>`usda:2685580` Tomato, paste, canned, without salt added | code 1.0: `usda:2685580` ~ `usda:170459` |
| `usda:2747674` | `usda:170465` Turnips, raw<br>`usda:2709809` Turnip, raw<br>`usda:2747674` Turnips, raw | code 1.0: `usda:2747674` ~ `usda:170465`<br>code 1.0: `usda:2709809` ~ `usda:170465` |
| `usda:170468` | `usda:170468` Turnip greens, frozen, unprepared<br>`usda:170470` Turnip greens and turnips, frozen, unprepared | same 1.0: `usda:170468` ~ `usda:170470` |
| `usda:170480` | `usda:170480` Beets, pickled, canned, solids and liquids<br>`usda:2710071` Beets, pickled | code 1.0: `usda:2710071` ~ `usda:170480` |
| `usda:170491` | `usda:170491` Carrot juice, canned<br>`usda:2709683` Carrot juice, 100% | code 1.0: `usda:2709683` ~ `usda:170491` |
| `usda:170494` | `usda:170494` Spinach souffle<br>`usda:2709629` Spinach souffle | same 1.0: `usda:170494` ~ `usda:2709629` |
| `usda:2685581` | `usda:170501` Tomatoes, crushed, canned<br>`usda:2685581` Tomatoes, crushed, canned | code 1.0: `usda:2685581` ~ `usda:170501` |
| `usda:170521` | `usda:170521` Potatoes, microwaved, cooked, in skin, flesh and skin, with salt<br>`usda:170522` Potatoes, microwaved, cooked in skin, flesh, with salt | unsure 1.0: `usda:170521` ~ `usda:170522` |
| `usda:2710819` | `usda:170554` Seeds, chia seeds, dried<br>`usda:2707590` Chia seeds<br>`usda:2710819` Chia seeds, dry, raw | code 1.0: `usda:2710819` ~ `usda:170554`<br>code 1.0: `usda:2707590` ~ `usda:170554` |
| `usda:2515380` | `usda:170556` Seeds, pumpkin and squash seed kernels, dried<br>`usda:2515380` Seeds, pumpkin seeds (pepitas), raw | code 1.0: `usda:2515380` ~ `usda:170556` |
| `usda:2515381` | `usda:170562` Seeds, sunflower seed kernels, dried<br>`usda:2515381` Seeds, sunflower seed, kernel, raw | code 1.0: `usda:2515381` ~ `usda:170562` |
| `usda:2346393` | `usda:170567` Nuts, almonds<br>`usda:2346393` Nuts, almonds, whole, raw<br>`usda:2707486` Almonds, unroasted | code 1.0: `usda:2346393` ~ `usda:170567`<br>code 1.0: `usda:2707486` ~ `usda:170567` |
| `usda:170569` | `usda:170569` Nuts, brazilnuts, dried, unblanched<br>`usda:2707492` Brazil nuts | code 1.0: `usda:2707492` ~ `usda:170569` |
| `usda:170571` | `usda:170571` Nuts, cashew nuts, dry roasted, without salt added<br>`usda:2707493` Cashews, NFS<br>`usda:2707494` Cashews, unroasted | code 1.0: `usda:2707493` ~ `usda:170571`<br>code 1.0: `usda:2707494` ~ `usda:170571` |
| `usda:170577` | `usda:170577` Nuts, coconut meat, dried (desiccated), sweetened, flaked, packaged<br>`usda:2707501` Coconut, packaged | code 1.0: `usda:2707501` ~ `usda:170577` |
| `usda:2515375` | `usda:170581` Nuts, hazelnuts or filberts<br>`usda:2515375` Nuts, hazelnuts or filberts, raw<br>`usda:2707502` Hazelnuts | code 1.0: `usda:2515375` ~ `usda:170581`<br>code 1.0: `usda:2707502` ~ `usda:170581` |
| `usda:170604` | `usda:170604` Beef, cured, dried<br>`usda:2705858` Beef, dried, chipped, uncooked | code 1.0: `usda:2705858` ~ `usda:170604` |
| `usda:170679` | `usda:170679` Sweetener, herbal extract powder from Stevia leaf<br>`usda:2710264` Sugar substitute, stevia, powder<br>`usda:2710266` Sugar substitute, monk fruit, powder | code 1.0: `usda:2710264` ~ `usda:170679`<br>code 1.0: `usda:2710266` ~ `usda:170679` |
| `usda:170681` | `usda:170681` Syrup, NESTLE, chocolate<br>`usda:2710276` Chocolate syrup | code 1.0: `usda:2710276` ~ `usda:170681` |
| `usda:2512374` | `usda:170687` Buckwheat flour, whole-groat<br>`usda:2512374` Flour, buckwheat | code 1.0: `usda:2512374` ~ `usda:170687` |
| `usda:2710820` | `usda:170688` Bulgur, dry<br>`usda:2710820` Bulgur, dry, raw | code 1.0: `usda:2710820` ~ `usda:170688` |
| `usda:170691` | `usda:170691` Fast foods, cheeseburger; single, regular patty, with condiments<br>`usda:2706892` Cheeseburger (McDonalds) | code 1.0: `usda:2706892` ~ `usda:170691` |
| `usda:170694` | `usda:170694` Fast foods, hamburger; single, regular patty; with condiments<br>`usda:2706924` Hamburger (McDonalds) | code 1.0: `usda:2706924` ~ `usda:170694` |
| `usda:170698` | `usda:170698` Fast foods, potato, french fried in vegetable oil<br>`usda:2709461` Potato, french fries, fast food | code 1.0: `usda:2709461` ~ `usda:170698` |
| `usda:170699` | `usda:170699` Fast foods, potato, mashed<br>`usda:2709493` Potato, mashed, from fast food | code 1.0: `usda:2709493` ~ `usda:170699` |
| `usda:170710` | `usda:170710` Fast foods, hamburger, large, single patty, with condiments<br>`usda:2706898` Quarter Pounder (McDonalds) | code 1.0: `usda:2706898` ~ `usda:170710` |
| `usda:170715` | `usda:170715` Pizza, meat and vegetable topping, regular crust, frozen, cooked<br>`usda:2708660` Pizza with meat and vegetables, from frozen, thin crust<br>`usda:2708661` Pizza with meat and vegetables, from frozen, medium crust<br>`usda:2708662` Pizza with meat and vegetables, from frozen, thick crust | code 1.0: `usda:2708660` ~ `usda:170715`<br>code 1.0: `usda:2708661` ~ `usda:170715`<br>code 1.0: `usda:2708662` ~ `usda:170715` |
| `usda:170718` | `usda:170718` Fast foods, chicken, breaded and fried, boneless pieces, plain<br>`usda:2706093` Chicken nuggets, from fast food<br>`usda:2706094` Chicken nuggets, from restaurant | code 1.0: `usda:2706093` ~ `usda:170718`<br>code 1.0: `usda:2706094` ~ `usda:170718` |
| `usda:170773` | `usda:170773` Fast Food, Pizza Chain, 14" pizza, cheese topping, stuffed crust<br>`usda:2708618` Pizza, cheese, stuffed crust | code 1.0: `usda:2708618` ~ `usda:170773` |
| `usda:170775` | `usda:170775` Fast foods, strawberry banana smoothie made with ice and low-fat yogurt<br>`usda:2705516` Fruit smoothie juice drink, with dairy | code 1.0: `usda:2705516` ~ `usda:170775` |
| `usda:170779` | `usda:170779` School Lunch, pizza, cheese topping, thick crust, whole grain, frozen, cooked<br>`usda:2708621` Pizza, cheese, from school lunch, thick crust | code 1.0: `usda:2708621` ~ `usda:170779` |
| `usda:170780` | `usda:170780` School Lunch, pizza, pepperoni topping, thin crust, whole grain, frozen, cooked<br>`usda:2708643` Pizza with pepperoni, from school lunch, thin crust | code 1.0: `usda:2708643` ~ `usda:170780` |
| `usda:170781` | `usda:170781` School Lunch, pizza, pepperoni topping, thick crust, whole grain, frozen, cooked<br>`usda:2708645` Pizza with pepperoni, from school lunch, thick crust | code 1.0: `usda:2708645` ~ `usda:170781` |
| `usda:170782` | `usda:170782` School Lunch, pizza, sausage topping, thin crust, whole grain, frozen, cooked<br>`usda:2708655` Pizza, with meat other than pepperoni, from school lunch, thin crust | code 1.0: `usda:2708655` ~ `usda:170782` |
| `usda:170792` | `usda:170792` School Lunch, pizza, cheese topping, thin crust, whole grain, frozen, cooked<br>`usda:2708620` Pizza, cheese, from school lunch, thin crust | code 1.0: `usda:2708620` ~ `usda:170792` |
| `usda:170793` | `usda:170793` School Lunch, pizza, sausage topping, thick crust, whole grain, frozen, cooked<br>`usda:2708656` Pizza, with meat other than pepperoni, from school lunch, thick crust | code 1.0: `usda:2708656` ~ `usda:170793` |
| `usda:170795` | `usda:170795` School Lunch, chicken nuggets, whole grain breaded<br>`usda:2706095` Chicken nuggets, from school lunch<br>`usda:2706101` Chicken tenders or strips, breaded, from school lunch | code 1.0: `usda:2706095` ~ `usda:170795`<br>code 1.0: `usda:2706101` ~ `usda:170795` |
| `usda:170843` | `usda:170843` Cheese, fontina<br>`usda:2705715` Cheese, Fontina | code 1.0: `usda:2705715` ~ `usda:170843` |
| `usda:170844` | `usda:170844` Cheese, monterey<br>`usda:2705720` Cheese, Monterey | same 1.0: `usda:170844` ~ `usda:2705720` |
| `usda:170848` | `usda:170848` Cheese, parmesan, hard<br>`usda:2705730` Cheese, Parmesan, hard | same 1.0: `usda:170848` ~ `usda:2705730` |
| `usda:170850` | `usda:170850` Cheese, provolone<br>`usda:2705733` Cheese, Provolone | same 1.0: `usda:170850` ~ `usda:2705733` |
| `usda:746766` | `usda:170851` Cheese, ricotta, whole milk<br>`usda:746766` Cheese, ricotta, whole milk | code 1.0: `usda:746766` ~ `usda:170851` |
| `usda:325198` | `usda:170853` Cheese, pasteurized process, American, fortified with vitamin D<br>`usda:325198` Cheese, pasteurized process, American, vitamin D fortified | code 1.0: `usda:325198` ~ `usda:170853` |
| `usda:170857` | `usda:170857` Cream, fluid, light (coffee cream or table cream)<br>`usda:2705593` Cream, light | code 1.0: `usda:2705593` ~ `usda:170857` |
| `usda:2346386` | `usda:170859` Cream, fluid, heavy whipping<br>`usda:2346386` Cream, heavy<br>`usda:2705597` Cream, heavy | code 1.0: `usda:2346386` ~ `usda:170859`<br>code 1.0: `usda:2705597` ~ `usda:170859` |
| `usda:170863` | `usda:170863` Cheese, American, nonfat or fat free<br>`usda:2705766` Cheese, American, nonfat or fat free | code 1.0: `usda:2705766` ~ `usda:170863` |
| `usda:170868` | `usda:170868` Dessert topping, semi solid, frozen<br>`usda:2705611` Whipped topping | code 1.0: `usda:2705611` ~ `usda:170868` |
| `usda:170869` | `usda:170869` Sour cream, imitation, cultured<br>`usda:2705617` Sour cream, imitation | code 1.0: `usda:2705617` ~ `usda:170869` |
| `usda:746772` | `usda:170872` Milk, lowfat, fluid, 1% milkfat, with added vitamin A and vitamin D<br>`usda:2705387` Milk, low fat (1%)<br>`usda:2705389` Milk, lactose free, low fat (1%)<br>`usda:746772` Milk, lowfat, fluid, 1% milkfat, with added vitamin A and vitamin D | code 1.0: `usda:746772` ~ `usda:170872`<br>code 1.0: `usda:2705387` ~ `usda:170872`<br>code 1.0: `usda:2705389` ~ `usda:170872` |
| `usda:2259792` | `usda:170874` Milk, buttermilk, fluid, cultured, lowfat<br>`usda:2259792` Buttermilk, low fat<br>`usda:2705393` Buttermilk | code 1.0: `usda:2259792` ~ `usda:170874`<br>code 1.0: `usda:2705393` ~ `usda:170874` |
| `usda:170878` | `usda:170878` Milk, canned, evaporated, nonfat, with added vitamin A and vitamin D<br>`usda:2705401` Milk, evaporated, fat free (skim) | code 1.0: `usda:2705401` ~ `usda:170878` |
| `usda:170879` | `usda:170879` Milk, chocolate, fluid, commercial, whole, with added vitamin A and vitamin D<br>`usda:2705467` Chocolate milk, whole | code 1.0: `usda:2705467` ~ `usda:170879` |
| `usda:170880` | `usda:170880` Milk, chocolate, fluid, commercial, reduced fat, with added vitamin A and vitamin D<br>`usda:2705468` Chocolate milk, reduced fat (2%) | code 1.0: `usda:2705468` ~ `usda:170880` |
| `usda:170881` | `usda:170881` Milk, chocolate, lowfat, with added vitamin A and vitamin D<br>`usda:2705470` Chocolate milk, low fat (1%) | code 1.0: `usda:2705470` ~ `usda:170881` |
| `usda:170892` | `usda:170892` Nutritional supplement for people with diabetes, liquid<br>`usda:2710719` Nutritional drink or shake, ready-to-drink, sugar free (Glucerna) | code 1.0: `usda:2710719` ~ `usda:170892` |
| `usda:330137` | `usda:170894` Yogurt, Greek, plain, nonfat (Includes foods for USDA's Food Distribution Program)<br>`usda:2705424` Yogurt, Greek, nonfat milk, plain<br>`usda:330137` Yogurt, Greek, plain, nonfat | code 1.0: `usda:330137` ~ `usda:170894`<br>code 1.0: `usda:2705424` ~ `usda:170894` |
| `usda:170896` | `usda:170896` Cheese spread, American or Cheddar cheese base, reduced fat<br>`usda:2705768` Cheese spread, American or Cheddar cheese base, reduced fat | code 1.0: `usda:2705768` ~ `usda:170896` |
| `usda:170897` | `usda:170897` Cheese, Swiss, nonfat or fat free<br>`usda:2705738` Cheese, Swiss, nonfat or fat free | code 1.0: `usda:2705738` ~ `usda:170897` |
| `usda:330415` | `usda:170901` Yogurt, Greek, strawberry, nonfat<br>`usda:330415` Yogurt, Greek, strawberry, nonfat | code 1.0: `usda:330415` ~ `usda:170901` |
| `usda:170905` | `usda:170905` Yogurt, Greek, fruit, whole milk<br>`usda:2705430` Yogurt, Greek, whole milk, fruit | same 1.0: `usda:170905` ~ `usda:2705430` |
| `usda:170939` | `usda:170939` Babyfood, vegetables, peas, strained<br>`usda:2710131` Baby Toddler peas, Stage 1<br>`usda:2710132` Baby Toddler peas, Stage 2 | code 1.0: `usda:2710131` ~ `usda:170939`<br>code 1.0: `usda:2710132` ~ `usda:170939` |
| `usda:170943` | `usda:170943` Babyfood, fruit, pears, junior<br>`usda:2709370` Baby Toddler pears, Stage 2 | code 1.0: `usda:2709370` ~ `usda:170943` |
| `usda:170959` | `usda:170959` Babyfood, juice, apple<br>`usda:2709374` Baby Toddler juice, apple | code 1.0: `usda:2709374` ~ `usda:170959` |
| `usda:170969` | `usda:170969` Babyfood, cereal, rice, dry fortified<br>`usda:2708493` Baby Toddler cereal, rice, dry | code 1.0: `usda:2708493` ~ `usda:170969` |
| `usda:171000` | `usda:171000` Babyfood, Multigrain whole grain cereal, dry fortified<br>`usda:2708496` Baby Toddler cereal, multigrain, dry | code 1.0: `usda:2708496` ~ `usda:171000` |
| `usda:171001` | `usda:171001` Babyfood, Baby MUM MUM Rice Biscuits<br>`usda:2708190` Baby Toddler crackers | code 1.0: `usda:2708190` ~ `usda:171001` |
| `usda:171003` | `usda:171003` Salad dressing, KRAFT Mayo Fat Free Mayonnaise Dressing<br>`usda:2710235` Mayonnaise, fat free | code 1.0: `usda:2710235` ~ `usda:171003` |
| `usda:171005` | `usda:171005` Salad dressing, russian dressing<br>`usda:2710206` Russian dressing | code 1.0: `usda:2710206` ~ `usda:171005` |
| `usda:171006` | `usda:171006` Salad dressing, sesame seed dressing, regular<br>`usda:2710211` Sesame dressing | code 1.0: `usda:2710211` ~ `usda:171006` |
| `usda:171008` | `usda:171008` Salad dressing, thousand island dressing, reduced fat<br>`usda:2710227` Thousand Island dressing, light | code 1.0: `usda:2710227` ~ `usda:171008` |
| `usda:2758986` | `usda:171009` Salad dressing, mayonnaise, regular<br>`usda:2710204` Mayonnaise, regular<br>`usda:2758986` Mayonnaise, Regular | code 1.0: `usda:2710204` ~ `usda:171009`<br>same 1.0: `usda:2710204` ~ `usda:2758986` |
| `usda:2758987` | `usda:171019` Salad dressing, italian dressing, commercial, regular<br>`usda:2710203` Italian dressing, made with vinegar and oil<br>`usda:2758987` Salad dressing, Italian dressing, commercial, regular | code 1.0: `usda:2758987` ~ `usda:171019`<br>code 1.0: `usda:2710203` ~ `usda:171019` |
| `usda:171034` | `usda:171034` Salad dressing, honey mustard dressing, reduced calorie<br>`usda:2710223` Honey mustard dressing, light | code 1.0: `usda:2710223` ~ `usda:171034` |
| `usda:171043` | `usda:171043` Salad dressing, honey mustard, regular<br>`usda:2710202` Honey mustard dressing | code 1.0: `usda:2710202` ~ `usda:171043` |
| `usda:171044` | `usda:171044` Salad dressing, poppyseed, creamy<br>`usda:2710210` Poppy seed dressing | code 1.0: `usda:2710210` ~ `usda:171044` |
| `usda:171045` | `usda:171045` Salad dressing, caesar, fat-free<br>`usda:2710230` Caesar dressing, fat free | code 1.0: `usda:2710230` ~ `usda:171045` |
| `usda:171046` | `usda:171046` Dressing, honey mustard, fat-free<br>`usda:2710233` Honey mustard dressing, fat free | code 1.0: `usda:2710233` ~ `usda:171046` |
| `usda:171055` | `usda:171055` Chicken, broilers or fryers, skin only, cooked, roasted<br>`usda:2706083` Chicken, tail | code 1.0: `usda:2706083` ~ `usda:171055` |
| `usda:171110` | `usda:171110` Chicken, canned, no broth<br>`usda:2706086` Chicken, canned, meat only<br>`usda:2706132` Turkey, canned | code 1.0: `usda:2706086` ~ `usda:171110`<br>code 1.0: `usda:2706132` ~ `usda:171110` |
| `usda:171114` | `usda:171114` Chicken, broiler, rotisserie, BBQ, drumstick, meat only<br>`usda:2706001` Chicken drumstick, NS as to cooking method, skin not eaten<br>`usda:2706005` Chicken drumstick, baked or broiled, skin not eaten, from pre-cooked<br>`usda:2706009` Chicken drumstick, rotisserie, skin not eaten | code 1.0: `usda:2706001` ~ `usda:171114`<br>code 1.0: `usda:2706005` ~ `usda:171114`<br>code 1.0: `usda:2706009` ~ `usda:171114` |
| `usda:2514746` | `usda:171116` Chicken, ground, raw<br>`usda:2514746` Chicken, ground, with additives, raw | code 1.0: `usda:2514746` ~ `usda:171116` |
| `usda:171118` | `usda:171118` Chicken, broiler, rotisserie, BBQ, thigh, meat only<br>`usda:2706028` Chicken thigh, NS as to cooking method, skin not eaten<br>`usda:2706032` Chicken thigh, baked or broiled, skin not eaten, from pre-cooked<br>`usda:2706036` Chicken thigh, rotisserie, skin not eaten | code 1.0: `usda:2706028` ~ `usda:171118`<br>code 1.0: `usda:2706032` ~ `usda:171118`<br>code 1.0: `usda:2706036` ~ `usda:171118` |
| `usda:171119` | `usda:171119` Chicken, feet, boiled<br>`usda:2706085` Chicken feet | code 1.0: `usda:2706085` ~ `usda:171119` |
| `usda:171125` | `usda:171125` Chicken, broiler, rotisserie, BBQ, breast, meat and skin<br>`usda:2705953` Chicken breast, NS as to cooking method, skin eaten<br>`usda:2705957` Chicken breast, baked or broiled, skin eaten, from pre-cooked<br>`usda:2705963` Chicken breast, rotisserie, skin eaten | code 1.0: `usda:2705953` ~ `usda:171125`<br>code 1.0: `usda:2705957` ~ `usda:171125`<br>code 1.0: `usda:2705963` ~ `usda:171125` |
| `usda:171126` | `usda:171126` Chicken, broiler, rotisserie, BBQ, drumstick, meat and skin<br>`usda:2706000` Chicken drumstick, NS as to cooking method, skin eaten<br>`usda:2706004` Chicken drumstick, baked or broiled, skin eaten, from pre-cooked<br>`usda:2706008` Chicken drumstick, rotisserie, skin eaten | code 1.0: `usda:2706000` ~ `usda:171126`<br>code 1.0: `usda:2706004` ~ `usda:171126`<br>code 1.0: `usda:2706008` ~ `usda:171126` |
| `usda:171127` | `usda:171127` Chicken, broiler, rotisserie, BBQ, thigh, meat and skin<br>`usda:2706027` Chicken thigh, NS as to cooking method, skin eaten<br>`usda:2706031` Chicken thigh, baked or broiled, skin eaten, from pre-cooked<br>`usda:2706035` Chicken thigh, rotisserie, skin eaten | code 1.0: `usda:2706027` ~ `usda:171127`<br>code 1.0: `usda:2706031` ~ `usda:171127`<br>code 1.0: `usda:2706035` ~ `usda:171127` |
| `usda:331960` | `usda:171140` Chicken, broiler or fryers, breast, skinless, boneless, meat only, cooked, braised<br>`usda:331960` Chicken, broiler or fryers, breast, skinless, boneless, meat only, cooked, braised | code 1.0: `usda:331960` ~ `usda:171140` |
| `usda:171167` | `usda:171167` Sauce, teriyaki, ready-to-serve<br>`usda:2707445` Teriyaki sauce | code 1.0: `usda:2707445` ~ `usda:171167` |
| `usda:332282` | `usda:171192` Sauce, pasta, spaghetti/marinara, ready-to-serve<br>`usda:2709745` Spaghetti sauce<br>`usda:332282` Sauce, pasta, spaghetti/marinara, ready-to-serve | code 1.0: `usda:332282` ~ `usda:171192`<br>code 1.0: `usda:2709745` ~ `usda:171192` |
| `usda:171203` | `usda:171203` Beef, chuck for stew, separable lean and fat, all grades, cooked, braised<br>`usda:2710241` Beef, for use with vegetables | code 1.0: `usda:2710241` ~ `usda:171203` |
| `usda:171243` | `usda:171243` Cheese, limburger<br>`usda:2705719` Cheese, Limburger | code 1.0: `usda:2705719` ~ `usda:171243` |
| `usda:329370` | `usda:171244` Cheese, mozzarella, low moisture, part-skim<br>`usda:2705722` Cheese, Mozzarella, NFS<br>`usda:2705723` Cheese, Mozzarella, part skim<br>`usda:329370` Cheese, mozzarella, low moisture, part-skim | code 1.0: `usda:329370` ~ `usda:171244`<br>code 1.0: `usda:2705722` ~ `usda:171244`<br>code 1.0: `usda:2705723` ~ `usda:171244` |
| `usda:171245` | `usda:171245` Cheese, muenster<br>`usda:2705726` Cheese, Muenster | code 1.0: `usda:2705726` ~ `usda:171245` |
| `usda:325036` | `usda:171247` Cheese, parmesan, grated<br>`usda:325036` Cheese, parmesan, grated | code 1.0: `usda:325036` ~ `usda:171247` |
| `usda:746767` | `usda:171251` Cheese, swiss<br>`usda:2705735` Cheese, Swiss<br>`usda:746767` Cheese, swiss | code 1.0: `usda:746767` ~ `usda:171251`<br>code 1.0: `usda:2705735` ~ `usda:171251` |
| `usda:171254` | `usda:171254` Cheese spread, pasteurized process, American<br>`usda:2705773` Cheese spread, American or Cheddar cheese base<br>`usda:2705774` Cheese spread, Swiss cheese base<br>`usda:2705776` Cheese spread, pressurized can | code 1.0: `usda:2705773` ~ `usda:171254`<br>code 1.0: `usda:2705774` ~ `usda:171254`<br>code 1.0: `usda:2705776` ~ `usda:171254` |
| `usda:2346387` | `usda:171257` Cream, sour, cultured<br>`usda:2346387` Cream, sour, full fat<br>`usda:2705614` Sour cream, regular | code 1.0: `usda:2346387` ~ `usda:171257`<br>code 1.0: `usda:2705614` ~ `usda:171257` |
| `usda:171258` | `usda:171258` Eggnog<br>`usda:2705502` Eggnog | code 1.0: `usda:2705502` ~ `usda:171258` |
| `usda:171261` | `usda:171261` Cream substitute, liquid, with hydrogenated vegetable oil and soy protein<br>`usda:2705599` Coffee creamer, NFS<br>`usda:2705600` Coffee creamer, liquid<br>`usda:2705610` Coffee creamer, soy, liquid | code 1.0: `usda:2705599` ~ `usda:171261`<br>code 1.0: `usda:2705600` ~ `usda:171261`<br>code 1.0: `usda:2705610` ~ `usda:171261` |
| `usda:171263` | `usda:171263` Cream substitute, powdered<br>`usda:2705606` Coffee creamer, powder<br>`usda:2705609` Coffee creamer,powder, sugar free, flavored | code 1.0: `usda:2705606` ~ `usda:171263`<br>code 1.0: `usda:2705609` ~ `usda:171263` |
| `usda:746778` | `usda:171267` Milk, reduced fat, fluid, 2% milkfat, with added vitamin A and vitamin D<br>`usda:2705386` Milk, reduced fat (2%)<br>`usda:2705391` Milk, lactose free, reduced fat (2%)<br>`usda:746778` Milk, reduced fat, fluid, 2% milkfat, with added vitamin A and vitamin D | code 1.0: `usda:746778` ~ `usda:171267`<br>code 1.0: `usda:2705386` ~ `usda:171267`<br>code 1.0: `usda:2705391` ~ `usda:171267` |
| `usda:746776` | `usda:171269` Milk, nonfat, fluid, with added vitamin A and vitamin D (fat free or skim)<br>`usda:2705388` Milk, fat free (skim)<br>`usda:2705390` Milk, lactose free, fat free (skim)<br>`usda:746776` Milk, nonfat, fluid, with added vitamin A and vitamin D (fat free or skim) | code 1.0: `usda:746776` ~ `usda:171269`<br>code 1.0: `usda:2705388` ~ `usda:171269`<br>code 1.0: `usda:2705390` ~ `usda:171269` |
| `usda:2758990` | `usda:171275` Milk, canned, condensed, sweetened<br>`usda:2705402` Milk, condensed, sweetened<br>`usda:2758990` Sweetened condensed milk | code 1.0: `usda:2758990` ~ `usda:171275`<br>code 1.0: `usda:2705402` ~ `usda:171275` |
| `usda:171278` | `usda:171278` Milk, goat, fluid, with added vitamin D<br>`usda:2705395` Goat milk | code 1.0: `usda:2705395` ~ `usda:171278` |
| `usda:171283` | `usda:171283` Whey, sweet, dried<br>`usda:2705586` Whey, sweet, dry | code 1.0: `usda:2705586` ~ `usda:171283` |
| `usda:748967` | `usda:171287` Egg, whole, raw, fresh<br>`usda:2707152` Egg, whole, raw<br>`usda:2707154` Egg, whole, boiled or poached<br>`usda:748967` Eggs, Grade A, Large, egg whole | code 1.0: `usda:748967` ~ `usda:171287`<br>code 1.0: `usda:2707152` ~ `usda:171287`<br>code 1.0: `usda:2707154` ~ `usda:171287` |
| `usda:171288` | `usda:171288` Cheese, Mexican blend<br>`usda:2705741` Cheese, Mexican blend | same 1.0: `usda:171288` ~ `usda:2705741` |
| `usda:171289` | `usda:171289` Cheese product, pasteurized process, American, vitamin D fortified<br>`usda:2705770` Cheese, processed cheese food<br>`usda:2705772` Cheese,  with wine | code 1.0: `usda:2705770` ~ `usda:171289`<br>code 1.0: `usda:2705772` ~ `usda:171289` |
| `usda:171292` | `usda:171292` Cheese, cheddar, reduced fat (Includes foods for USDA's Food Distribution Program)<br>`usda:2705710` Cheese, Cheddar, reduced fat | code 1.0: `usda:2705710` ~ `usda:171292` |
| `usda:171294` | `usda:171294` Ice cream bar, stick or nugget, with crunch coating<br>`usda:2705638` Ice cream bar, vanilla | code 1.0: `usda:2705638` ~ `usda:171294` |
| `usda:171295` | `usda:171295` Cheese, cheddar, nonfat or fat free<br>`usda:2705711` Cheese, Cheddar, nonfat or fat free | code 1.0: `usda:2705711` ~ `usda:171295` |
| `usda:171303` | `usda:171303` Milk, chocolate, fat free, with added vitamin A and vitamin D<br>`usda:2705469` Chocolate milk, fat free (skim) | code 1.0: `usda:2705469` ~ `usda:171303` |
| `usda:2259794` | `usda:171304` Yogurt, Greek, plain, whole milk<br>`usda:2259794` Yogurt, Greek, plain, whole milk<br>`usda:2705422` Yogurt, Greek, whole milk, plain | code 1.0: `usda:2259794` ~ `usda:171304`<br>code 1.0: `usda:2705422` ~ `usda:171304` |
| `usda:171307` | `usda:171307` Light ice cream, Creamsicle<br>`usda:2705673` Creamsicle | code 1.0: `usda:2705673` ~ `usda:171307` |
| `usda:171336` | `usda:171336` Babyfood, fruit, peaches, strained<br>`usda:2709367` Baby Toddler peaches, Stage 1 | code 1.0: `usda:2709367` ~ `usda:171336` |
| `usda:171337` | `usda:171337` Babyfood, fruit, peaches, junior<br>`usda:2709368` Baby Toddler peaches, Stage 2 | code 1.0: `usda:2709368` ~ `usda:171337` |
| `usda:171338` | `usda:171338` Babyfood, fruit, pears, strained<br>`usda:2709369` Baby Toddler pears, Stage 1 | code 1.0: `usda:2709369` ~ `usda:171338` |
| `usda:171340` | `usda:171340` Babyfood, prunes, without vitamin c, strained<br>`usda:2709371` Baby Toddler prunes | code 1.0: `usda:2709371` ~ `usda:171340` |
| `usda:171358` | `usda:171358` Babyfood, cereal, barley, dry fortified<br>`usda:2708491` Baby Toddler cereal, barley, dry | code 1.0: `usda:2708491` ~ `usda:171358` |
| `usda:171360` | `usda:171360` Babyfood, cereal, oatmeal, dry fortified<br>`usda:2708492` Baby Toddler cereal, oatmeal, dry | code 1.0: `usda:2708492` ~ `usda:171360` |
| `usda:171372` | `usda:171372` Zwieback<br>`usda:2707705` Zwieback toast | code 1.0: `usda:2707705` ~ `usda:171372` |
| `usda:171380` | `usda:171380` Babyfood, dessert, custard pudding, vanilla, junior<br>`usda:2709380` Baby Toddler pudding | code 1.0: `usda:2709380` ~ `usda:171380` |
| `usda:171388` | `usda:171388` Babyfood, fortified cereal bar, fruit filling<br>`usda:2708129` Baby Toddler bar | code 1.0: `usda:2708129` ~ `usda:171388` |
| `usda:171396` | `usda:171396` Infant formula, ABBOTT NUTRITION, SIMILAC, Expert Care, Diarrhea, ready- to- feed with ARA and DHA<br>`usda:2705573` Infant formula, Similac for Diarrhea | code 1.0: `usda:2705573` ~ `usda:171396` |
| `usda:171402` | `usda:171402` Salad dressing, thousand island, commercial, regular<br>`usda:2710213` Thousand Island dressing | code 1.0: `usda:2710213` ~ `usda:171402` |
| `usda:171403` | `usda:171403` Salad dressing, mayonnaise type, regular, with salt<br>`usda:2710207` Mayonnaise-type salad dressing | code 1.0: `usda:2710207` ~ `usda:171403` |
| `usda:171404` | `usda:171404` Salad dressing, french dressing, reduced fat<br>`usda:2710218` French or Catalina dressing, light | code 1.0: `usda:2710218` ~ `usda:171404` |
| `usda:171405` | `usda:171405` Salad dressing, italian dressing, commercial, reduced fat<br>`usda:2710224` Italian dressing, light<br>`usda:2710226` Sesame dressing, light | code 1.0: `usda:2710224` ~ `usda:171405`<br>code 1.0: `usda:2710226` ~ `usda:171405` |
| `usda:171406` | `usda:171406` Salad dressing, mayonnaise, imitation, soybean<br>`usda:2710205` Vegan mayonnaise | code 1.0: `usda:2710205` ~ `usda:171406` |
| `usda:171409` | `usda:171409` Sandwich spread, with chopped pickle, regular, unspecified oils<br>`usda:2710172` Sandwich spread | code 1.0: `usda:2710172` ~ `usda:171409` |
| `usda:748366` | `usda:171411` Oil, soybean, salad or cooking<br>`usda:2710191` Soybean oil<br>`usda:748366` Oil, soybean | code 1.0: `usda:748366` ~ `usda:171411`<br>code 1.0: `usda:2710191` ~ `usda:171411` |
| `usda:171414` | `usda:171414` Salad dressing, french dressing, commercial, regular<br>`usda:2710201` French or Catalina dressing | code 1.0: `usda:2710201` ~ `usda:171414` |
| `usda:171420` | `usda:171420` Salad dressing, french dressing, fat-free<br>`usda:2710232` French or Catalina dressing, fat free | code 1.0: `usda:2710232` ~ `usda:171420` |
| `usda:171443` | `usda:171443` Mayonnaise, reduced fat, with olive oil<br>`usda:2710221` Mayonnaise, reduced fat,  with olive oil | code 1.0: `usda:2710221` ~ `usda:171443` |
| `usda:171444` | `usda:171444` Salad dressing, mayonnaise-type, light<br>`usda:2710222` Mayonnaise-type salad dressing, light | code 1.0: `usda:2710222` ~ `usda:171444` |
| `usda:171445` | `usda:171445` Chicken, broiler, rotisserie, BBQ, breast, meat only<br>`usda:2705954` Chicken breast, NS as to cooking method, skin not eaten<br>`usda:2705958` Chicken breast, baked or broiled, skin not eaten, from pre-cooked<br>`usda:2705964` Chicken breast, rotisserie, skin not eaten | code 1.0: `usda:2705954` ~ `usda:171445`<br>code 1.0: `usda:2705958` ~ `usda:171445`<br>code 1.0: `usda:2705964` ~ `usda:171445` |
| `usda:171513` | `usda:171513` Chicken patty, frozen, cooked<br>`usda:2706088` Chicken patty, breaded | code 1.0: `usda:2706088` ~ `usda:171513` |
| `usda:171564` | `usda:171564` Gravy, beef, canned, ready-to-serve<br>`usda:2707145` Gravy, beef<br>`usda:2707146` Gravy, beef, fat free | code 1.0: `usda:2707145` ~ `usda:171564`<br>code 1.0: `usda:2707146` ~ `usda:171564` |
| `usda:171566` | `usda:171566` Gravy, chicken, canned or bottled, ready-to-serve<br>`usda:2707144` Gravy, poultry<br>`usda:2707147` Gravy, poultry, fat free | code 1.0: `usda:2707144` ~ `usda:171566`<br>code 1.0: `usda:2707147` ~ `usda:171566` |
| `usda:171595` | `usda:171595` Sauce, tomato chili sauce, bottled, with salt<br>`usda:2709735` Tomato chili sauce | code 1.0: `usda:2709735` ~ `usda:171595` |
| `usda:171597` | `usda:171597` Sauce, pasta, spaghetti/marinara, ready-to-serve, low sodium<br>`usda:2709747` Spaghetti sauce, reduced sodium | code 1.0: `usda:2709747` ~ `usda:171597` |
| `usda:171618` | `usda:171618` Blood sausage<br>`usda:2706173` Blood sausage | code 1.0: `usda:2706173` ~ `usda:171618` |
| `usda:171620` | `usda:171620` Bratwurst, pork, cooked<br>`usda:2706174` Bratwurst | code 1.0: `usda:2706174` ~ `usda:171620` |
| `usda:171621` | `usda:171621` Braunschweiger (a liver sausage), pork<br>`usda:2706213` Liverwurst | code 1.0: `usda:2706213` ~ `usda:171621` |
| `usda:171625` | `usda:171625` Frankfurter, turkey<br>`usda:2706170` Hot dog, turkey | code 1.0: `usda:2706170` ~ `usda:171625` |
| `usda:171630` | `usda:171630` Headcheese, pork<br>`usda:2706180` Head cheese | code 1.0: `usda:2706180` ~ `usda:171630` |
| `usda:171636` | `usda:171636` Pork sausage, link/patty, reduced fat, cooked, pan-fried<br>`usda:2706192` Pork sausage, reduced fat | code 1.0: `usda:2706192` ~ `usda:171636` |
| `usda:171637` | `usda:171637` Bologna, meat and poultry<br>`usda:2706176` Bologna | code 1.0: `usda:2706176` ~ `usda:171637` |
| `usda:171639` | `usda:171639` Bacon, turkey, microwaved<br>`usda:2706135` Turkey bacon, cooked | code 1.0: `usda:2706135` ~ `usda:171639` |
| `usda:171640` | `usda:171640` Bacon, turkey, low sodium<br>`usda:2705886` Bacon, NS as to type of meat, reduced sodium, cooked<br>`usda:2706136` Turkey bacon, reduced sodium, cooked | code 1.0: `usda:2705886` ~ `usda:171640`<br>code 1.0: `usda:2706136` ~ `usda:171640` |
| `usda:2710815` | `usda:171697` Apricots, raw<br>`usda:2709221` Apricot, raw<br>`usda:2710815` Apricot, with skin, raw | code 1.0: `usda:2710815` ~ `usda:171697`<br>code 1.0: `usda:2709221` ~ `usda:171697` |
| `usda:171705` | `usda:171705` Avocados, raw, all commercial varieties<br>`usda:2709223` Avocado, raw | code 1.0: `usda:2709223` ~ `usda:171705` |
| `usda:171708` | `usda:171708` Cherries, tart, dried, sweetened (Includes foods for USDA's Food Distribution Program)<br>`usda:2709199` Cherries, dried | code 1.0: `usda:2709199` ~ `usda:171708` |
| `usda:171710` | `usda:171710` Blackberries, frozen, unsweetened<br>`usda:2709274` Blackberries, frozen | code 1.0: `usda:2709274` ~ `usda:171710` |
| `usda:171715` | `usda:171715` Carambola, (starfruit), raw<br>`usda:2709228` Starfruit, raw | code 1.0: `usda:2709228` ~ `usda:171715` |
| `usda:2346399` | `usda:171719` Cherries, sweet, raw<br>`usda:2346399` Cherries, sweet, dark red, raw<br>`usda:2709231` Cherries, raw<br>`usda:2709233` Cherries, frozen | code 1.0: `usda:2346399` ~ `usda:171719`<br>code 1.0: `usda:2709231` ~ `usda:171719`<br>code 1.0: `usda:2709233` ~ `usda:171719` |
| `usda:2758976` | `usda:171723` Cranberries, dried, sweetened (Includes foods for USDA's Food Distribution Program)<br>`usda:2709202` Cranberries, dried<br>`usda:2758976` Cranberries, dried, sweetened | code 1.0: `usda:2758976` ~ `usda:171723`<br>code 1.0: `usda:2709202` ~ `usda:171723` |
| `usda:171724` | `usda:171724` Currants, zante, dried<br>`usda:2709201` Currants, dried | code 1.0: `usda:2709201` ~ `usda:171724` |
| `usda:171726` | `usda:171726` Dates, deglet noor<br>`usda:2709203` Date | code 1.0: `usda:2709203` ~ `usda:171726` |
| `usda:746760` | `usda:171761` Beef, round, eye of round roast, boneless, separable lean only, trimmed to 0" fat, select, raw<br>`usda:746760` Beef, round, eye of round roast, boneless, separable lean only, trimmed to 0" fat, select, raw | code 1.0: `usda:746760` ~ `usda:171761` |
| `usda:171823` | `usda:171823` Sauce, duck, ready-to-serve<br>`usda:2710298` Duck sauce | code 1.0: `usda:2710298` ~ `usda:171823` |
| `usda:171824` | `usda:171824` Sauce, salsa, verde, ready-to-serve<br>`usda:2709742` Enchilada sauce, green<br>`usda:2709743` Salsa verde or salsa, green | code 1.0: `usda:2709742` ~ `usda:171824`<br>code 1.0: `usda:2709743` ~ `usda:171824` |
| `usda:171825` | `usda:171825` Sauce, steak, tomato based<br>`usda:2709752` Steak sauce | code 1.0: `usda:2709752` ~ `usda:171825` |
| `usda:171826` | `usda:171826` Sauce, tartar, ready-to-serve<br>`usda:2710173` Tartar sauce | code 1.0: `usda:2710173` ~ `usda:171826` |
| `usda:171831` | `usda:171831` Wasabi<br>`usda:2710103` Wasabi paste | code 1.0: `usda:2710103` ~ `usda:171831` |
| `usda:171832` | `usda:171832` Dip, bean, original flavor<br>`usda:2707400` Bean dip, made with refried beans | code 1.0: `usda:2707400` ~ `usda:171832` |
| `usda:171835` | `usda:171835` Cookie, vanilla with caramel, coconut, and chocolate coating<br>`usda:2707983` Cookie, vanilla with caramel, coconut, and chocolate coating | code 1.0: `usda:2707983` ~ `usda:171835` |
| `usda:171836` | `usda:171836` Cookie, with peanut butter filling, chocolate-coated<br>`usda:2707956` Cookie, with peanut butter filling, chocolate-coated | code 1.0: `usda:2707956` ~ `usda:171836` |
| `usda:171837` | `usda:171837` Cookies, animal, with frosting or icing<br>`usda:2707969` Cookie, animal, with frosting or icing | code 1.0: `usda:2707969` ~ `usda:171837` |
| `usda:171838` | `usda:171838` Crackers, multigrain<br>`usda:2708170` Crackers, multigrain | code 1.0: `usda:2708170` ~ `usda:171838` |
| `usda:171840` | `usda:171840` Cookies, brownies, commercially prepared, reduced fat, with added fiber<br>`usda:2707906` Cookie, brownie, reduced fat, NS as to icing | code 1.0: `usda:2707906` ~ `usda:171840` |
| `usda:171841` | `usda:171841` Cookies, chocolate sandwich, with creme filling, reduced fat<br>`usda:2707921` Cookie, chocolate sandwich, reduced fat | code 1.0: `usda:2707921` ~ `usda:171841` |
| `usda:171842` | `usda:171842` Cookies, oatmeal sandwich, with creme filling<br>`usda:2707948` Cookie, oatmeal sandwich, with creme filling<br>`usda:2707950` Cookie, oatmeal sandwich, with peanut butter and jelly filling<br>`usda:2707961` Cookie, raisin sandwich, cream-filled | code 1.0: `usda:2707948` ~ `usda:171842`<br>code 1.0: `usda:2707950` ~ `usda:171842`<br>code 1.0: `usda:2707961` ~ `usda:171842` |
| `usda:171843` | `usda:171843` Cookies, peanut butter, commercially prepared, sugar free<br>`usda:2707988` Cookie, sugar or plain, sugar free<br>`usda:2707990` Cookie, peanut butter, sugar free | code 1.0: `usda:2707988` ~ `usda:171843`<br>code 1.0: `usda:2707990` ~ `usda:171843` |
| `usda:171847` | `usda:171847` Cookies, coconut macaroon<br>`usda:2707927` Cookie, coconut<br>`usda:2707936` Cookie, macaroon | code 1.0: `usda:2707927` ~ `usda:171847`<br>code 1.0: `usda:2707936` ~ `usda:171847` |
| `usda:171848` | `usda:171848` Crackers, sandwich-type, peanut butter filled, reduced fat<br>`usda:2708174` Crackers, sandwich, reduced fat, peanut butter filled | code 1.0: `usda:2708174` ~ `usda:171848` |
| `usda:171849` | `usda:171849` Bread, cinnamon<br>`usda:2707620` Bread, cinnamon | code 1.0: `usda:2707620` ~ `usda:171849` |
| `usda:171850` | `usda:171850` Bread, wheat, sprouted<br>`usda:171851` Bread, wheat, sprouted, toasted<br>`usda:2707718` Bread, sprouted wheat<br>`usda:2707719` Bread, sprouted wheat, toasted | code 1.0: `usda:2707718` ~ `usda:171850`<br>code 1.0: `usda:2707719` ~ `usda:171850`<br>unsure 1.0: `usda:171851` ~ `usda:2707719` |
| `usda:171853` | `usda:171853` Pancakes, whole wheat, dry mix, incomplete<br>`usda:172776` Pancakes, whole-wheat, dry mix, incomplete | same 1.0: `usda:171853` ~ `usda:172776` |
| `usda:171855` | `usda:171855` Crackers, whole grain, sandwich-type, with peanut butter filling<br>`usda:2708175` Crackers, whole grain, sandwich, peanut butter filled | code 1.0: `usda:2708175` ~ `usda:171855` |
| `usda:171856` | `usda:171856` Crackers, water biscuits<br>`usda:2708178` Crackers, water | code 1.0: `usda:2708178` ~ `usda:171856` |
| `usda:171857` | `usda:171857` Cookies, gluten-free, chocolate sandwich, with creme filling<br>`usda:2707991` Cookie, gluten free | code 1.0: `usda:2707991` ~ `usda:171857` |
| `usda:171862` | `usda:171862` Rolls, gluten-free, white, made with rice flour, rice starch, and corn starch<br>`usda:2707800` Roll, gluten free | code 1.0: `usda:2707800` ~ `usda:171862` |
| `usda:171865` | `usda:171865` Cookies, oatmeal, reduced fat<br>`usda:2707947` Cookie, oatmeal, reduced fat, NS as to raisins | code 1.0: `usda:2707947` ~ `usda:171865` |
| `usda:171866` | `usda:171866` Cookies, chocolate cream covered biscuit sticks<br>`usda:2707967` Pocky | code 1.0: `usda:2707967` ~ `usda:171866` |
| `usda:171867` | `usda:171867` Cookies, Marie biscuit<br>`usda:2707971` Marie biscuit | code 1.0: `usda:2707971` ~ `usda:171867` |
| `usda:171868` | `usda:171868` Cookies, vanilla sandwich with creme filling, reduced fat<br>`usda:2707977` Cookie, vanilla sandwich, reduced fat | code 1.0: `usda:2707977` ~ `usda:171868` |
| `usda:171869` | `usda:171869` Beverages, carbonated, tonic water<br>`usda:2710538` Water, tonic | code 1.0: `usda:2710538` ~ `usda:171869` |
| `usda:171870` | `usda:171870` Beverages, Energy drink, RED BULL, sugar free, with added caffeine, niacin, pantothenic acid, vitamins B6 and B12<br>`usda:2710763` Energy drink, sugar-free (Red Bull)<br>`usda:2710766` Energy drink (XS)<br>`usda:2710767` Energy drink (XS Gold Plus) | code 1.0: `usda:2710763` ~ `usda:171870`<br>code 1.0: `usda:2710766` ~ `usda:171870`<br>code 1.0: `usda:2710767` ~ `usda:171870` |
| `usda:171871` | `usda:171871` Beverages, carbonated, root beer<br>`usda:2710557` Soft drink, root beer | code 1.0: `usda:2710557` ~ `usda:171871` |
| `usda:171873` | `usda:171873` Beverages, chocolate drink, milk and soy based, ready to drink, fortified<br>`usda:2710714` Nutritional drink or shake, ready-to-drink (Boost) | code 1.0: `usda:2710714` ~ `usda:171873` |
| `usda:171878` | `usda:171878` Beverages, Lemonade fruit juice drink light, fortified with vitamin E and C<br>`usda:2710592` Lemonade, fruit juice drink, light | code 1.0: `usda:2710592` ~ `usda:171878` |
| `usda:171880` | `usda:171880` Beverages, coffee, ready to drink, milk based, sweetened<br>`usda:2710478` Coffee, bottled/canned | code 1.0: `usda:2710478` ~ `usda:171880` |
| `usda:171884` | `usda:171884` Beverages, The COCA-COLA company, Minute Maid, Lemonade<br>`usda:2710570` Lemonade, fruit juice drink | code 1.0: `usda:2710570` ~ `usda:171884` |
| `usda:171885` | `usda:171885` Beverages, tea, green, ready-to-drink, diet<br>`usda:2710501` Tea, iced, instant, green, pre-sweetened with low calorie sweetener<br>`usda:2710534` Tea, iced, bottled, green, diet | code 1.0: `usda:2710501` ~ `usda:171885`<br>code 1.0: `usda:2710534` ~ `usda:171885` |
| `usda:171888` | `usda:171888` Beverages, tea, black, ready-to-drink, lemon, sweetened<br>`usda:2710527` Tea, iced, bottled, black | code 1.0: `usda:2710527` ~ `usda:171888` |
| `usda:171889` | `usda:171889` Beverages, coffee, brewed, prepared with tap water, decaffeinated<br>`usda:2710451` Coffee, NS as to brewed or instant, decaffeinated<br>`usda:2710452` Coffee, brewed, decaffeinated<br>`usda:2710471` Coffee and chicory, brewed, decaffeinated | code 1.0: `usda:2710451` ~ `usda:171889`<br>code 1.0: `usda:2710452` ~ `usda:171889`<br>code 1.0: `usda:2710471` ~ `usda:171889` |
| `usda:171890` | `usda:171890` Beverages, coffee, brewed, prepared with tap water<br>`usda:2710373` Coffee, NS as to type<br>`usda:2710374` Coffee, NS as to brewed or instant<br>`usda:2710375` Coffee, brewed<br>`usda:2710380` Coffee, brewed, flavored<br>`usda:2710470` Coffee and chicory, brewed | code 1.0: `usda:2710373` ~ `usda:171890`<br>code 1.0: `usda:2710374` ~ `usda:171890`<br>code 1.0: `usda:2710375` ~ `usda:171890`<br>code 1.0: `usda:2710380` ~ `usda:171890`<br>code 1.0: `usda:2710470` ~ `usda:171890` |
| `usda:171891` | `usda:171891` Beverages, coffee, brewed, espresso, restaurant-prepared<br>`usda:2710378` Coffee, espresso | code 1.0: `usda:2710378` ~ `usda:171891` |
| `usda:171892` | `usda:171892` Beverages, tea, black, ready-to-drink, lemon, diet<br>`usda:2710529` Tea, iced, bottled, black, diet | code 1.0: `usda:2710529` ~ `usda:171892` |
| `usda:171893` | `usda:171893` Beverages, coffee, instant, regular, powder<br>`usda:2710480` Coffee, instant, not reconstituted | code 1.0: `usda:2710480` ~ `usda:171893` |
| `usda:171897` | `usda:171897` Beverages, coffee, instant, with chicory<br>`usda:174134` Beverages, coffee, instant, chicory | same 1.0: `usda:171897` ~ `usda:174134` |
| `usda:171903` | `usda:171903` Cranberry juice cocktail, bottled<br>`usda:2710579` Cranberry juice drink, with high vitamin C | code 1.0: `usda:2710579` ~ `usda:171903` |
| `usda:171906` | `usda:171906` Alcoholic beverages, beer, higher alcohol<br>`usda:2710618` Beer, higher alcohol<br>`usda:2710620` Alcoholic malt beverage | code 1.0: `usda:2710618` ~ `usda:171906`<br>code 1.0: `usda:2710620` ~ `usda:171906` |
| `usda:171910` | `usda:171910` Beverages, tea, green, brewed, decaffeinated<br>`usda:2710491` Tea, hot, leaf, green, decaffeinated<br>`usda:2710526` Tea, iced, brewed, green, decaffeinated, unsweetened | code 1.0: `usda:2710491` ~ `usda:171910`<br>code 1.0: `usda:2710526` ~ `usda:171910` |
| `usda:171911` | `usda:171911` Beverages, tea, green, ready to drink, unsweetened<br>`usda:2710499` Tea, iced, instant, green, unsweetened<br>`usda:2710535` Tea, iced, bottled, green, unsweetened | code 1.0: `usda:2710499` ~ `usda:171911`<br>code 1.0: `usda:2710535` ~ `usda:171911` |
| `usda:171915` | `usda:171915` Beverages, Tropical Punch, ready-to-drink<br>`usda:2710567` Fruit juice drink | code 1.0: `usda:2710567` ~ `usda:171915` |
| `usda:171917` | `usda:171917` Beverages, tea, green, brewed, regular<br>`usda:2710490` Tea, hot, leaf, green<br>`usda:2710523` Tea, iced, brewed, green, unsweetened | code 1.0: `usda:2710490` ~ `usda:171917`<br>code 1.0: `usda:2710523` ~ `usda:171917` |
| `usda:171921` | `usda:171921` Carbonated beverage, chocolate-flavored soda<br>`usda:2710559` Soft drink, chocolate flavored | code 1.0: `usda:2710559` ~ `usda:171921` |
| `usda:171926` | `usda:171926` Water, non-carbonated, bottles, natural fruit flavors, sweetened with low calorie sweetener<br>`usda:2710709` Water, non-carbonated, flavored | code 1.0: `usda:2710709` ~ `usda:171926` |
| `usda:171935` | `usda:171935` Beverages, Energy Drink, Monster, fortified with vitamins C, B2, B3, B6, B12<br>`usda:2710747` Energy drink (Monster) | code 1.0: `usda:2710747` ~ `usda:171935` |
| `usda:171936` | `usda:171936` Beverages, Energy drink, AMP, sugar free<br>`usda:2710759` Energy drink, sugar free (Mountain Dew AMP) | code 1.0: `usda:2710759` ~ `usda:171936` |
| `usda:171937` | `usda:171937` Beverages, Energy drink, ROCKSTAR<br>`usda:2710753` Energy drink (Rockstar) | code 1.0: `usda:2710753` ~ `usda:171937` |
| `usda:171938` | `usda:171938` Beverages, Energy drink, ROCKSTAR, sugar free<br>`usda:2710764` Energy drink, sugar free (Rockstar) | code 1.0: `usda:2710764` ~ `usda:171938` |
| `usda:171940` | `usda:171940` Water, with corn syrup and/or sugar and low calorie sweetener, fruit flavored<br>`usda:2710710` Water beverage, fruit flavored | code 1.0: `usda:2710710` ~ `usda:171940` |
| `usda:171942` | `usda:171942` Beverages, rice milk, unsweetened<br>`usda:2705411` Rice milk | code 1.0: `usda:2705411` ~ `usda:171942` |
| `usda:171943` | `usda:171943` Beverages, Energy drink, VAULT, citrus flavor<br>`usda:2710755` Energy drink (Vault) | code 1.0: `usda:2710755` ~ `usda:171943` |
| `usda:171945` | `usda:171945` Beverages, fruit juice drink, greater than 3% fruit juice, high vitamin C and added thiamin<br>`usda:2710582` Fruit juice drink (Sunny D) | code 1.0: `usda:2710582` ~ `usda:171945` |
| `usda:171946` | `usda:171946` Beverages, tea, hibiscus, brewed<br>`usda:2710503` Tea, hot, hibiscus | code 1.0: `usda:2710503` ~ `usda:171946` |
| `usda:171947` | `usda:171947` Beverages, fruit juice drink, greater than 3% juice, high vitamin C<br>`usda:2710580` Fruit juice drink, with high vitamin C | code 1.0: `usda:2710580` ~ `usda:171947` |
| `usda:333374` | `usda:171964` Fish, haddock, raw<br>`usda:333374` Fish, haddock, raw | code 1.0: `usda:333374` ~ `usda:171964` |
| `usda:171966` | `usda:171966` Crustaceans, crab, blue, canned<br>`usda:2706345` Crab, canned | code 1.0: `usda:2706345` ~ `usda:171966` |
| `usda:171981` | `usda:171981` Mollusks, oyster, eastern, canned<br>`usda:2706355` Oysters, canned | code 1.0: `usda:2706355` ~ `usda:171981` |
| `usda:2758991` | `usda:172012` Bologna, beef<br>`usda:2758991` Bologna, beef | code 1.0: `usda:2758991` ~ `usda:172012` |
| `usda:172035` | `usda:172035` Fast foods, french toast sticks<br>`usda:2708339` French toast sticks, fast food / restaurant | code 1.0: `usda:2708339` ~ `usda:172035` |
| `usda:172081` | `usda:172081` Fast foods, cheeseburger; single, large patty; with condiments, vegetables and mayonnaise<br>`usda:2706899` Whopper with cheese (Burger King) | code 1.0: `usda:2706899` ~ `usda:172081` |
| `usda:172082` | `usda:172082` Fast foods, cheeseburger; single, large patty; with condiments<br>`usda:2706900` Quarter Pounder with cheese (McDonalds) | code 1.0: `usda:2706900` ~ `usda:172082` |
| `usda:172084` | `usda:172084` Fast foods, cheeseburger; double, regular patty; double decker bun with condiments and special sauce<br>`usda:2706916` Big Mac (McDonalds) | code 1.0: `usda:2706916` ~ `usda:172084` |
| `usda:172094` | `usda:172094` Tortellini, pasta with cheese filling, fresh-refrigerated, as purchased<br>`usda:2708792` Tortellini, cheese-filled, no sauce | code 1.0: `usda:2708792` ~ `usda:172094` |
| `usda:172111` | `usda:172111` Chicken, nuggets, dark and white meat, precooked, frozen, not reheated<br>`usda:2706096` Chicken nuggets, from frozen | code 1.0: `usda:2706096` ~ `usda:172111` |
| `usda:172113` | `usda:172113` Ravioli, cheese with tomato sauce, frozen, not prepared, includes regular and light entrees<br>`usda:2708768` Ravioli, cheese-filled, with tomato sauce | code 1.0: `usda:2708768` ~ `usda:172113` |
| `usda:172175` | `usda:172175` Cheese, blue<br>`usda:2705705` Cheese, Blue or Roquefort | code 1.0: `usda:2705705` ~ `usda:172175` |
| `usda:172176` | `usda:172176` Cheese, brick<br>`usda:2705706` Cheese, Brick | code 1.0: `usda:2705706` ~ `usda:172176` |
| `usda:172177` | `usda:172177` Cheese, brie<br>`usda:2705708` Cheese, Brie | code 1.0: `usda:2705708` ~ `usda:172177` |
| `usda:2346384` | `usda:172179` Cheese, cottage, creamed, large or small curd<br>`usda:2346384` Cottage cheese, full fat, large or small curd<br>`usda:2705748` Cheese, cottage, creamed, large or small curd | code 1.0: `usda:2346384` ~ `usda:172179`<br>code 1.0: `usda:2705748` ~ `usda:172179` |
| `usda:172181` | `usda:172181` Cheese, cottage, nonfat, uncreamed, dry, large or small curd<br>`usda:2705753` Cheese, cottage, dry curd | code 1.0: `usda:2705753` ~ `usda:172181` |
| `usda:328841` | `usda:172182` Cheese, cottage, lowfat, 2% milkfat<br>`usda:2705747` Cheese, cottage, NFS<br>`usda:2705756` Cheese, cottage, low fat<br>`usda:2705759` Cheese, cottage, lowfat, lactose reduced<br>`usda:328841` Cheese, cottage, lowfat, 2% milkfat | code 1.0: `usda:328841` ~ `usda:172182`<br>code 1.0: `usda:2705747` ~ `usda:172182`<br>code 1.0: `usda:2705756` ~ `usda:172182`<br>code 1.0: `usda:2705759` ~ `usda:172182` |
| `usda:748236` | `usda:172184` Egg, yolk, raw, fresh<br>`usda:2707172` Egg, yolk only, raw<br>`usda:748236` Eggs, Grade A, Large, egg yolk | code 1.0: `usda:748236` ~ `usda:172184`<br>code 1.0: `usda:2707172` ~ `usda:172184` |
| `usda:329490` | `usda:172188` Egg, whole, dried<br>`usda:329490` Egg, whole, dried | code 1.0: `usda:329490` ~ `usda:172188` |
| `usda:172195` | `usda:172195` Milk, dry, nonfat, regular, with added vitamin A and vitamin D<br>`usda:2705585` Milk, dry, not reconstituted | code 1.0: `usda:2705585` ~ `usda:172195` |
| `usda:172201` | `usda:172201` Cheese, mexican, queso anejo<br>`usda:2705743` Queso Anejo, aged Mexican cheese | code 1.0: `usda:2705743` ~ `usda:172201` |
| `usda:323604` | `usda:172202` Egg, whole, raw, frozen, pasteurized (Includes foods for USDA's Food Distribution Program)<br>`usda:323604` Egg, whole, raw, frozen, pasteurized | code 1.0: `usda:323604` ~ `usda:172202` |
| `usda:323697` | `usda:172203` Egg, white, raw, frozen, pasteurized<br>`usda:323697` Egg, white, raw, frozen, pasteurized | code 1.0: `usda:323697` ~ `usda:172203` |
| `usda:323793` | `usda:172204` Egg, white, dried<br>`usda:323793` Egg, white, dried | code 1.0: `usda:323793` ~ `usda:172204` |
| `usda:172206` | `usda:172206` Parmesan cheese topping, fat free<br>`usda:2705731` Cheese, Parmesan, dry grated, fat free | code 1.0: `usda:2705731` ~ `usda:172206` |
| `usda:172207` | `usda:172207` Cheese, cream, fat free<br>`usda:2705769` Cream cheese, fat free | code 1.0: `usda:2705769` ~ `usda:172207` |
| `usda:172212` | `usda:172212` Cream, half and half, fat free<br>`usda:2705596` Cream, half and half, fat free | code 1.0: `usda:2705596` ~ `usda:172212` |
| `usda:172214` | `usda:172214` Cream substitute, flavored, powdered<br>`usda:2705607` Coffee creamer, powder, flavored | code 1.0: `usda:2705607` ~ `usda:172214` |
| `usda:172215` | `usda:172215` Cheese, provolone, reduced fat<br>`usda:2705734` Cheese, provolone, reduced fat | code 1.0: `usda:2705734` ~ `usda:172215` |
| `usda:172216` | `usda:172216` Cheese, Mexican, blend, reduced fat<br>`usda:2705742` Cheese, Mexican blend, reduced fat | code 1.0: `usda:2705742` ~ `usda:172216` |
| `usda:746765` | `usda:172222` Cheese, dry white, queso seco<br>`usda:746765` Cheese, dry white, queso seco | code 1.0: `usda:746765` ~ `usda:172222` |
| `usda:172227` | `usda:172227` Ice cream cookie sandwich<br>`usda:2705644` Ice cream cookie sandwich | same 1.0: `usda:172227` ~ `usda:2705644` |
| `usda:172228` | `usda:172228` Ice cream cone, chocolate covered, with nuts, flavors other than chocolate<br>`usda:2705654` Ice cream cone, vanilla, prepackaged | code 1.0: `usda:2705654` ~ `usda:172228` |
| `usda:172247` | `usda:172247` Babyfood, meat, ham, strained<br>`usda:2705903` Baby Toddler ham | code 1.0: `usda:2705903` ~ `usda:172247` |
| `usda:172250` | `usda:172250` Babyfood, meat, turkey, strained<br>`usda:2706152` Baby Toddler turkey | code 1.0: `usda:2706152` ~ `usda:172250` |
| `usda:172252` | `usda:172252` Babyfood, finger snacks, GERBER, GRADUATES, PUFFS, apple and cinnamon<br>`usda:2708191` Baby Toddler puffs, fruit<br>`usda:2708192` Baby Toddler puffs, vegetable | code 1.0: `usda:2708191` ~ `usda:172252`<br>code 1.0: `usda:2708192` ~ `usda:172252` |
| `usda:172253` | `usda:172253` Babyfood, water, bottled, GERBER, without added fluoride<br>`usda:2710713` Water, baby | code 1.0: `usda:2710713` ~ `usda:172253` |
| `usda:172272` | `usda:172272` Babyfood, vegetables, green beans, junior<br>`usda:2710124` Baby Toddler green beans, Stage 1<br>`usda:2710125` Baby Toddler green beans, Stage 2 | code 1.0: `usda:2710124` ~ `usda:172272`<br>code 1.0: `usda:2710125` ~ `usda:172272` |
| `usda:172274` | `usda:172274` Babyfood, vegetables, squash, strained<br>`usda:2710120` Baby Toddler squash, Stage 1 | code 1.0: `usda:2710120` ~ `usda:172274` |
| `usda:172275` | `usda:172275` Babyfood, vegetables, squash, junior<br>`usda:2710121` Baby Toddler squash, Stage 2 | code 1.0: `usda:2710121` ~ `usda:172275` |
| `usda:172276` | `usda:172276` Babyfood, vegetables, sweet potatoes strained<br>`usda:2710122` Baby Toddler sweet potatoes, Stage 1 | code 1.0: `usda:2710122` ~ `usda:172276` |
| `usda:172277` | `usda:172277` Babyfood, vegetables, sweet potatoes, junior<br>`usda:2710123` Baby Toddler sweet potatoes, Stage 2 | code 1.0: `usda:2710123` ~ `usda:172277` |
| `usda:172278` | `usda:172278` Babyfood, fruit, applesauce, junior<br>`usda:2709364` Baby Toddler apples, Stage 2 | code 1.0: `usda:2709364` ~ `usda:172278` |
| `usda:172313` | `usda:172313` Child formula, ABBOTT NUTRITION, PEDIASURE, ready-to-feed<br>`usda:2705545` Toddler formula, PediaSure<br>`usda:2705548` Toddler formula, store brand, pediatric shake | code 1.0: `usda:2705545` ~ `usda:172313`<br>code 1.0: `usda:2705548` ~ `usda:172313` |
| `usda:172318` | `usda:172318` Infant formula, ABBOTT NUTRITION, SIMILAC, ALIMENTUM, ADVANCE, ready-to-feed, with ARA and DHA<br>`usda:2705520` Infant formula, Similac Alimentum, ready-to-feed<br>`usda:2705521` Infant formula, Similac Alimentum, powder, made with water | code 1.0: `usda:2705520` ~ `usda:172318`<br>code 1.0: `usda:2705521` ~ `usda:172318` |
| `usda:748278` | `usda:172336` Oil, canola<br>`usda:2710188` Canola oil<br>`usda:748278` Oil, canola | code 1.0: `usda:748278` ~ `usda:172336`<br>code 1.0: `usda:2710188` ~ `usda:172336` |
| `usda:172356` | `usda:172356` Salad dressing, thousand island dressing, fat-free<br>`usda:2710238` Thousand Island dressing, fat free | code 1.0: `usda:2710238` ~ `usda:172356` |
| `usda:2515376` | `usda:172430` Peanuts, all types, raw<br>`usda:2515376` Peanuts, raw<br>`usda:2707514` Peanuts, unroasted | code 1.0: `usda:2515376` ~ `usda:172430`<br>code 1.0: `usda:2707514` ~ `usda:172430` |
| `usda:172438` | `usda:172438` Refried beans, canned, traditional style<br>`usda:2707396` Refried beans | code 1.0: `usda:2707396` ~ `usda:172438` |
| `usda:172439` | `usda:172439` Bacon, meatless<br>`usda:2707465` Bacon strip, meatless | code 1.0: `usda:2707465` ~ `usda:172439` |
| `usda:172440` | `usda:172440` Soybeans, mature seeds, roasted, salted<br>`usda:2707433` Soy nuts | code 1.0: `usda:2707433` ~ `usda:172440` |
| `usda:172443` | `usda:172443` Natto<br>`usda:2707440` Natto | code 1.0: `usda:2707440` ~ `usda:172443` |
| `usda:172449` | `usda:172449` Tofu, soft, prepared with calcium sulfate and magnesium chloride (nigari)<br>`usda:2707435` Soybean curd | code 1.0: `usda:2707435` ~ `usda:172449` |
| `usda:172451` | `usda:172451` Tofu, fried<br>`usda:2707448` Soybean curd, deep fried | code 1.0: `usda:2707448` ~ `usda:172451` |
| `usda:172457` | `usda:172457` Peanut spread, reduced sugar<br>`usda:2707540` Peanut butter, lower sugar | code 1.0: `usda:2707540` ~ `usda:172457` |
| `usda:172458` | `usda:172458` Peanut butter, smooth, reduced fat<br>`usda:2707541` Peanut butter, reduced fat | code 1.0: `usda:2707541` ~ `usda:172458` |
| `usda:172459` | `usda:172459` Peanut butter, smooth, vitamin and mineral fortified<br>`usda:2707542` Peanut butter, vitamin and mineral fortified | code 1.0: `usda:2707542` ~ `usda:172459` |
| `usda:172470` | `usda:172470` Peanut butter, smooth style, without salt<br>`usda:2707538` Peanut butter, lower sodium | code 1.0: `usda:2707538` ~ `usda:172470` |
| `usda:172473` | `usda:172473` Soy sauce made from soy and wheat (shoyu), low sodium<br>`usda:2707443` Soy sauce, reduced sodium | code 1.0: `usda:2707443` ~ `usda:172473` |
| `usda:172669` | `usda:172669` Biscuits, plain or buttermilk, refrigerated dough, higher fat, baked<br>`usda:2707802` Biscuit, from refrigerated dough | code 1.0: `usda:2707802` ~ `usda:172669` |
| `usda:172672` | `usda:172672` Bread, cracked-wheat<br>`usda:172686` Bread, wheat<br>`usda:2707720` Bread, wheat or cracked wheat<br>`usda:2707721` Bread, wheat or cracked wheat, toasted<br>`usda:2707788` Bread, barley<br>`usda:2707847` Bread, Boston Brown | same 1.0: `usda:172672` ~ `usda:2707720`<br>code 1.0: `usda:2707720` ~ `usda:172686`<br>code 1.0: `usda:2707721` ~ `usda:172686`<br>code 1.0: `usda:2707788` ~ `usda:172686`<br>code 1.0: `usda:2707847` ~ `usda:172686` |
| `usda:172673` | `usda:172673` Bread, egg<br>`usda:2707624` Bread, egg, Challah<br>`usda:2707625` Bread, egg, Challah, toasted<br>`usda:2707659` Roll, egg bread | code 1.0: `usda:2707624` ~ `usda:172673`<br>code 1.0: `usda:2707625` ~ `usda:172673`<br>code 1.0: `usda:2707659` ~ `usda:172673` |
| `usda:172675` | `usda:172675` Bread, french or vienna (includes sourdough)<br>`usda:2707604` Bread, Cuban<br>`usda:2707605` Bread, Cuban, toasted<br>`usda:2707610` Bread, French or Vienna<br>`usda:2707611` Bread, French or Vienna, toasted<br>`usda:2707646` Bread, sour dough<br>`usda:2707647` Bread, sour dough, toasted<br>`usda:2707658` Roll, diet<br>`usda:2707661` Roll, French or Vienna<br>`usda:2707665` Roll, sour dough | code 1.0: `usda:2707604` ~ `usda:172675`<br>code 1.0: `usda:2707605` ~ `usda:172675`<br>code 1.0: `usda:2707610` ~ `usda:172675`<br>code 1.0: `usda:2707611` ~ `usda:172675`<br>code 1.0: `usda:2707646` ~ `usda:172675`<br>code 1.0: `usda:2707647` ~ `usda:172675`<br>code 1.0: `usda:2707658` ~ `usda:172675`<br>code 1.0: `usda:2707661` ~ `usda:172675`<br>code 1.0: `usda:2707665` ~ `usda:172675` |
| `usda:172676` | `usda:172676` Bread, oat bran<br>`usda:172677` Bread, oat bran, toasted<br>`usda:172678` Bread, oatmeal<br>`usda:172679` Bread, oatmeal, toasted<br>`usda:2707768` Bread, oatmeal<br>`usda:2707769` Bread, oatmeal, toasted<br>`usda:2707770` Bread, oat bran<br>`usda:2707771` Bread, oat bran, toasted<br>`usda:2707773` Roll, oatmeal<br>`usda:2707774` Muffin, English, oat bran | same 1.0: `usda:172676` ~ `usda:2707770`<br>same 1.0: `usda:172677` ~ `usda:2707771`<br>code 1.0: `usda:2707768` ~ `usda:172678`<br>code 1.0: `usda:2707769` ~ `usda:172678`<br>code 1.0: `usda:2707770` ~ `usda:172678`<br>code 1.0: `usda:2707771` ~ `usda:172678`<br>code 1.0: `usda:2707773` ~ `usda:172678`<br>code 1.0: `usda:2707774` ~ `usda:172678`<br>same 1.0: `usda:172679` ~ `usda:2707769` |
| `usda:172684` | `usda:172684` Bread, rye<br>`usda:172685` Bread, rye, toasted<br>`usda:2707755` Bread, rye<br>`usda:2707756` Bread, rye, toasted<br>`usda:2707757` Bread, marble rye and pumpernickel<br>`usda:2707758` Bread, marble rye and pumpernickel, toasted<br>`usda:2707759` Muffin, English, rye<br>`usda:2707766` Roll, rye | code 1.0: `usda:2707755` ~ `usda:172684`<br>code 1.0: `usda:2707756` ~ `usda:172684`<br>code 1.0: `usda:2707757` ~ `usda:172684`<br>code 1.0: `usda:2707758` ~ `usda:172684`<br>code 1.0: `usda:2707759` ~ `usda:172684`<br>code 1.0: `usda:2707766` ~ `usda:172684`<br>same 1.0: `usda:172685` ~ `usda:2707756` |
| `usda:2758994` | `usda:172688` Bread, whole-wheat, commercially prepared<br>`usda:2707709` Bread, whole wheat<br>`usda:2707710` Bread, whole wheat, toasted<br>`usda:2758994` Bread, 100% whole wheat, commercial | code 1.0: `usda:2758994` ~ `usda:172688`<br>code 1.0: `usda:2707709` ~ `usda:172688`<br>code 1.0: `usda:2707710` ~ `usda:172688` |
| `usda:172693` | `usda:172693` Bread, stuffing, cornbread, dry mix, prepared<br>`usda:2707812` Cornbread stuffing | code 1.0: `usda:2707812` ~ `usda:172693` |
| `usda:172695` | `usda:172695` Cake, angelfood, dry mix, prepared<br>`usda:2707854` Cake, angel food | code 1.0: `usda:2707854` ~ `usda:172695` |
| `usda:172696` | `usda:172696` Cake, boston cream pie, commercially prepared<br>`usda:2707858` Cake, Boston cream pie | code 1.0: `usda:2707858` ~ `usda:172696` |
| `usda:172704` | `usda:172704` Cake, pound, commercially prepared, butter (includes fresh and frozen)<br>`usda:2707882` Cake, pound | code 1.0: `usda:2707882` ~ `usda:172704` |
| `usda:172706` | `usda:172706` Cake, sponge, commercially prepared<br>`usda:2707886` Cake, sponge | code 1.0: `usda:2707886` ~ `usda:172706` |
| `usda:172713` | `usda:172713` Cookies, brownies, commercially prepared<br>`usda:2707903` Cookie, brownie, NS as to icing<br>`usda:2707904` Cookie, brownie, without icing<br>`usda:2707907` Cookie, butterscotch, brownie | code 1.0: `usda:2707903` ~ `usda:172713`<br>code 1.0: `usda:2707904` ~ `usda:172713`<br>code 1.0: `usda:2707907` ~ `usda:172713` |
| `usda:172714` | `usda:172714` Cookies, chocolate wafers<br>`usda:2707915` Cookie, chocolate or fudge<br>`usda:2707924` Cookie, chocolate wafer | code 1.0: `usda:2707915` ~ `usda:172714`<br>code 1.0: `usda:2707924` ~ `usda:172714` |
| `usda:172715` | `usda:172715` Cookies, chocolate chip, commercially prepared, regular, lower fat<br>`usda:2707911` Cookie, chocolate chip, reduced fat | code 1.0: `usda:2707911` ~ `usda:172715` |
| `usda:172716` | `usda:172716` Cookies, chocolate chip, commercially prepared, regular, higher fat, enriched<br>`usda:2707899` Cookie, NFS<br>`usda:2707908` Cookie, bar, with chocolate<br>`usda:2707909` Cookie, chocolate chip<br>`usda:2707926` Cookie bar, with chocolate, nuts, and graham crackers<br>`usda:2707974` Cookie, toffee bar | code 1.0: `usda:2707899` ~ `usda:172716`<br>code 1.0: `usda:2707908` ~ `usda:172716`<br>code 1.0: `usda:2707909` ~ `usda:172716`<br>code 1.0: `usda:2707926` ~ `usda:172716`<br>code 1.0: `usda:2707974` ~ `usda:172716` |
| `usda:172718` | `usda:172718` Cookies, chocolate sandwich, with creme filling, regular<br>`usda:2707920` Cookie, chocolate sandwich<br>`usda:2707923` Cookie, chocolate and vanilla sandwich | code 1.0: `usda:2707920` ~ `usda:172718`<br>code 1.0: `usda:2707923` ~ `usda:172718` |
| `usda:172720` | `usda:172720` Cookies, chocolate sandwich, with extra creme filling<br>`usda:2707922` Cookie, chocolate, sandwich, with extra filling<br>`usda:2707976` Cookie, vanilla sandwich, extra filling | code 1.0: `usda:2707922` ~ `usda:172720`<br>code 1.0: `usda:2707976` ~ `usda:172720` |
| `usda:172721` | `usda:172721` Cookies, fig bars<br>`usda:2707928` Cookie, fruit-filled bar<br>`usda:2707929` Cookie, fig bar<br>`usda:2707984` Cookie, rugelach<br>`usda:2708115` Breakfast bar, date, with yogurt coating | code 1.0: `usda:2707928` ~ `usda:172721`<br>code 1.0: `usda:2707929` ~ `usda:172721`<br>code 1.0: `usda:2707984` ~ `usda:172721`<br>code 1.0: `usda:2708115` ~ `usda:172721` |
| `usda:172722` | `usda:172722` Cookies, fortune<br>`usda:2707930` Cookie, fortune<br>`usda:2707980` Cookie, tea, Japanese | code 1.0: `usda:2707930` ~ `usda:172722`<br>code 1.0: `usda:2707980` ~ `usda:172722` |
| `usda:172723` | `usda:172723` Cookies, marshmallow, chocolate-coated (includes marshmallow pies)<br>`usda:2707916` Cookie, marshmallow, chocolate-covered<br>`usda:2707917` Cookie, marshmallow pie, chocolate covered<br>`usda:2707937` Cookie, marshmallow, with coconut | code 1.0: `usda:2707916` ~ `usda:172723`<br>code 1.0: `usda:2707917` ~ `usda:172723`<br>code 1.0: `usda:2707937` ~ `usda:172723` |
| `usda:172724` | `usda:172724` Cookies, molasses<br>`usda:2707942` Cookie, molasses<br>`usda:2707943` Cookie, Lebkuchen<br>`usda:2708137` Crackers, Cuban | code 1.0: `usda:2707942` ~ `usda:172724`<br>code 1.0: `usda:2707943` ~ `usda:172724`<br>code 1.0: `usda:2708137` ~ `usda:172724` |
| `usda:172725` | `usda:172725` Cookies, oatmeal, commercially prepared, regular<br>`usda:2707901` Cookie, applesauce<br>`usda:2707914` Cookie, chocolate, made with oatmeal and coconut, no bake<br>`usda:2707945` Cookie, oatmeal<br>`usda:2707946` Cookie, oatmeal, with raisins<br>`usda:2707951` Cookie, oatmeal, with chocolate and peanut butter, no bake<br>`usda:2707959` Cookie, pumpkin | code 1.0: `usda:2707901` ~ `usda:172725`<br>code 1.0: `usda:2707914` ~ `usda:172725`<br>code 1.0: `usda:2707945` ~ `usda:172725`<br>code 1.0: `usda:2707946` ~ `usda:172725`<br>code 1.0: `usda:2707951` ~ `usda:172725`<br>code 1.0: `usda:2707959` ~ `usda:172725` |
| `usda:172727` | `usda:172727` Cookies, peanut butter, commercially prepared, regular<br>`usda:2707952` Cookie, peanut butter | code 1.0: `usda:2707952` ~ `usda:172727` |
| `usda:172732` | `usda:172732` Cookies, chocolate chip, commercially prepared, special dietary<br>`usda:2707985` Cookie, chocolate chip, reduced sugar | code 1.0: `usda:2707985` ~ `usda:172732` |
| `usda:172733` | `usda:172733` Cookies, chocolate sandwich, with creme filling, special dietary<br>`usda:2707987` Cookie, sandwich, reduced sugar | code 1.0: `usda:2707987` ~ `usda:172733` |
| `usda:172734` | `usda:172734` Cookies, oatmeal, commercially prepared, special dietary<br>`usda:2707986` Cookie, oatmeal, reduced sugar | code 1.0: `usda:2707986` ~ `usda:172734` |
| `usda:172736` | `usda:172736` Cookies, sugar wafers with creme filling, regular<br>`usda:2707973` Cookie, sugar wafer | code 1.0: `usda:2707973` ~ `usda:172736` |
| `usda:172737` | `usda:172737` Cookies, vanilla sandwich with creme filling<br>`usda:2707963` Cookie, sandwich-type, not chocolate or vanilla<br>`usda:2707975` Cookie, vanilla sandwich<br>`usda:2708139` Graham crackers, sandwich, with filling | code 1.0: `usda:2707963` ~ `usda:172737`<br>code 1.0: `usda:2707975` ~ `usda:172737`<br>code 1.0: `usda:2708139` ~ `usda:172737` |
| `usda:172738` | `usda:172738` Puff pastry, frozen, ready-to-bake, baked<br>`usda:2708053` Pastry, puff | code 1.0: `usda:2708053` ~ `usda:172738` |
| `usda:172739` | `usda:172739` Crackers, crispbread, rye<br>`usda:2708156` Crackers, crispbread | code 1.0: `usda:2708156` ~ `usda:172739` |
| `usda:172740` | `usda:172740` Crackers, matzo, plain<br>`usda:2708142` Crackers, matzo, reduced sodium<br>`usda:2708158` Crackers, matzo | code 1.0: `usda:2708142` ~ `usda:172740`<br>code 1.0: `usda:2708158` ~ `usda:172740` |
| `usda:172746` | `usda:172746` Crackers, saltines (includes oyster, soda, soup)<br>`usda:2708160` Crackers, oyster<br>`usda:2708167` Crackers, saltine | code 1.0: `usda:2708160` ~ `usda:172746`<br>code 1.0: `usda:2708167` ~ `usda:172746` |
| `usda:172752` | `usda:172752` Croutons, seasoned<br>`usda:2707697` Croutons | code 1.0: `usda:2707697` ~ `usda:172752` |
| `usda:172753` | `usda:172753` Danish pastry, cinnamon, enriched<br>`usda:2708059` Danish pastry, plain or spice | code 1.0: `usda:2708059` ~ `usda:172753` |
| `usda:172754` | `usda:172754` Danish pastry, cheese<br>`usda:2708061` Danish pastry, with cheese | code 1.0: `usda:2708061` ~ `usda:172754` |
| `usda:172755` | `usda:172755` Danish pastry, fruit, enriched (includes apple, cinnamon, raisin, lemon, raspberry, strawberry)<br>`usda:2708058` Breakfast pastry, NFS<br>`usda:2708060` Danish pastry, with fruit | code 1.0: `usda:2708058` ~ `usda:172755`<br>code 1.0: `usda:2708060` ~ `usda:172755` |
| `usda:172758` | `usda:172758` Doughnuts, yeast-leavened, glazed, enriched (includes honey buns)<br>`usda:2708072` Doughnut, yeast type | code 1.0: `usda:2708072` ~ `usda:172758` |
| `usda:172761` | `usda:172761` Muffins, English, wheat<br>`usda:172762` Muffins, English, whole-wheat<br>`usda:2707738` Muffin, English, wheat bran<br>`usda:2707740` Muffin, English, wheat or cracked wheat<br>`usda:2707741` Muffin, English, whole wheat<br>`usda:2707744` Muffin, English, whole grain white<br>`usda:2707787` Muffin, English, multigrain | code 1.0: `usda:2707738` ~ `usda:172761`<br>code 1.0: `usda:2707740` ~ `usda:172761`<br>code 1.0: `usda:2707741` ~ `usda:172761`<br>code 1.0: `usda:2707744` ~ `usda:172761`<br>code 1.0: `usda:2707787` ~ `usda:172761`<br>same 1.0: `usda:172762` ~ `usda:2707741` |
| `usda:172765` | `usda:172765` Muffins, blueberry, commercially prepared (Includes mini-muffins)<br>`usda:2707829` Muffin, NFS<br>`usda:2707830` Muffin, fruit<br>`usda:2707841` Muffin, plain | code 1.0: `usda:2707829` ~ `usda:172765`<br>code 1.0: `usda:2707830` ~ `usda:172765`<br>unsure 0.5: `usda:2707829` ~ `usda:2707841` |
| `usda:172769` | `usda:172769` Muffins, oat bran<br>`usda:2707840` Muffin, oat bran | code 1.0: `usda:2707840` ~ `usda:172769` |
| `usda:172771` | `usda:172771` Pancakes plain, frozen, ready-to-heat (includes buttermilk)<br>`usda:2708295` Pancakes, plain, frozen | code 1.0: `usda:2708295` ~ `usda:172771` |
| `usda:172783` | `usda:172783` Pie, egg custard, commercially prepared<br>`usda:2708007` Pie, custard | code 1.0: `usda:2708007` ~ `usda:172783` |
| `usda:172784` | `usda:172784` Pie, fried pies, fruit<br>`usda:2707994` Tart, all types<br>`usda:2707996` Pie, apple, fast food<br>`usda:2708046` Turnover, fruit | code 1.0: `usda:2707994` ~ `usda:172784`<br>code 1.0: `usda:2707996` ~ `usda:172784`<br>code 1.0: `usda:2708046` ~ `usda:172784` |
| `usda:172796` | `usda:172796` Rolls, hamburger or hotdog, plain<br>`usda:2707595` Roll, NS as to major flour<br>`usda:2707654` Roll, white, soft<br>`usda:2707663` Roll, white, hoagie, submarine | code 1.0: `usda:2707595` ~ `usda:172796`<br>code 1.0: `usda:2707654` ~ `usda:172796`<br>code 1.0: `usda:2707663` ~ `usda:172796` |
| `usda:172797` | `usda:172797` Rolls, hamburger or hotdog, mixed-grain<br>`usda:2707597` Roll, bran, NS as to type of bran<br>`usda:2707782` Roll, multigrain<br>`usda:2707783` Roll, multigrain, hot dog bun<br>`usda:2707784` Roll, multigrain, hamburger bun | code 1.0: `usda:2707597` ~ `usda:172797`<br>code 1.0: `usda:2707782` ~ `usda:172797`<br>code 1.0: `usda:2707783` ~ `usda:172797`<br>code 1.0: `usda:2707784` ~ `usda:172797` |
| `usda:172800` | `usda:172800` Taco shells, baked<br>`usda:2707826` Taco shell, corn | code 1.0: `usda:2707826` ~ `usda:172800` |
| `usda:172823` | `usda:172823` Crackers, whole-wheat, low salt<br>`usda:2708141` Crackers, butter, reduced sodium<br>`usda:2708144` Crackers, wheat, reduced sodium<br>`usda:2708145` Crackers, woven wheat, reduced sodium | code 1.0: `usda:2708141` ~ `usda:172823`<br>code 1.0: `usda:2708144` ~ `usda:172823`<br>code 1.0: `usda:2708145` ~ `usda:172823` |
| `usda:172830` | `usda:172830` Chicken, broiler, rotisserie, BBQ, wing, meat and skin<br>`usda:2706056` Chicken wing, NS as to cooking method<br>`usda:2706058` Chicken wing, baked or broiled, from pre-cooked<br>`usda:2706060` Chicken wing, rotisserie | code 1.0: `usda:2706056` ~ `usda:172830`<br>code 1.0: `usda:2706058` ~ `usda:172830`<br>code 1.0: `usda:2706060` ~ `usda:172830` |
| `usda:2514747` | `usda:172850` Turkey, ground, 93% lean, 7% fat, raw<br>`usda:2514747` Turkey, ground, 93% lean/ 7% fat, raw | code 1.0: `usda:2514747` ~ `usda:172850` |
| `usda:746785` | `usda:172851` Turkey, ground, 93% lean, 7% fat, pan-broiled crumbles<br>`usda:746785` Turkey, ground, 93% lean, 7% fat, pan-broiled crumbles | code 1.0: `usda:746785` ~ `usda:172851` |
| `usda:331897` | `usda:172852` Chicken, broilers or fryers, dark meat, drumstick, meat only, cooked, braised<br>`usda:331897` Chicken, broilers or fryers, drumstick, meat only, cooked, braised | code 1.0: `usda:331897` ~ `usda:172852` |
| `usda:172886` | `usda:172886` Sauce, hoisin, ready-to-serve<br>`usda:2707441` Hoisin sauce | code 1.0: `usda:2707441` ~ `usda:172886` |
| `usda:172890` | `usda:172890` Sauce, teriyaki, ready-to-serve, reduced sodium<br>`usda:2707446` Teriyaki sauce, reduced sodium | code 1.0: `usda:2707446` ~ `usda:172890` |
| `usda:172928` | `usda:172928` Pate, chicken liver, canned<br>`usda:2706155` Liver, paste or pate | code 1.0: `usda:2706155` ~ `usda:172928` |
| `usda:172937` | `usda:172937` Salami, cooked, turkey<br>`usda:2706196` Salami, made from any type of meat, reduced fat | code 1.0: `usda:2706196` ~ `usda:172937` |
| `usda:172940` | `usda:172940` Thuringer, cervelat, summer sausage, beef, pork<br>`usda:2706199` Thuringer | code 1.0: `usda:2706199` ~ `usda:172940` |
| `usda:172941` | `usda:172941` Turkey breast, sliced, prepackaged<br>`usda:2706215` Turkey, prepackaged or deli, luncheon meat<br>`usda:2706217` Turkey ham, prepackaged or deli, luncheon meat | code 1.0: `usda:2706215` ~ `usda:172941`<br>code 1.0: `usda:2706217` ~ `usda:172941` |
| `usda:172942` | `usda:172942` Sausage, Vienna, canned, chicken, beef, pork<br>`usda:2706203` Vienna sausage, canned | code 1.0: `usda:2706203` ~ `usda:172942` |
| `usda:172950` | `usda:172950` Luncheon meat, pork, ham, and chicken, minced, canned, reduced sodium, added ascorbic acid, includes SPAM, 25% less sodium<br>`usda:2706212` Spam, reduced sodium | code 1.0: `usda:2706212` ~ `usda:172950` |
| `usda:172951` | `usda:172951` Luncheon meat, pork with ham, minced, canned, includes Spam (Hormel)<br>`usda:2706211` Spam | code 1.0: `usda:2706211` ~ `usda:172951` |
| `usda:172969` | `usda:172969` Scrapple, pork<br>`usda:2706198` Scrapple, cooked | code 1.0: `usda:2706198` ~ `usda:172969` |
| `usda:173006` | `usda:173006` Rice and Wheat cereal bar<br>`usda:2708087` Cereal or granola bar (Kellogg's Special K bar) | code 1.0: `usda:2708087` ~ `usda:173006` |
| `usda:173035` | `usda:173035` Grapefruit, sections, canned, water pack, solids and liquids<br>`usda:2709166` Grapefruit, canned | code 1.0: `usda:2709166` ~ `usda:173035` |
| `usda:173038` | `usda:173038` Grapefruit juice, pink or red, with added calcium<br>`usda:2709179` Grapefruit juice, 100%, with calcium added | code 1.0: `usda:2709179` ~ `usda:173038` |
| `usda:173039` | `usda:173039` Grapefruit juice, white, raw<br>`usda:2709176` Grapefruit juice, 100%, freshly squeezed | code 1.0: `usda:2709176` ~ `usda:173039` |
| `usda:2003592` | `usda:173041` Grape juice, canned or bottled, unsweetened, with added ascorbic acid<br>`usda:2003592` Grape juice, purple, with added vitamin C, from concentrate, shelf stable | code 1.0: `usda:2003592` ~ `usda:173041` |
| `usda:173044` | `usda:173044` Guavas, common, raw<br>`usda:2709238` Guava, raw | code 1.0: `usda:2709238` ~ `usda:173044` |
| `usda:173137` | `usda:173137` Formulated bar, POWER BAR, chocolate<br>`usda:2708120` Nutrition bar (PowerBar) | code 1.0: `usda:2708120` ~ `usda:173137` |
| `usda:173139` | `usda:173139` Formulated bar, SLIM-FAST OPTIMA meal bar, milk chocolate peanut<br>`usda:2708121` Nutrition bar (Slim Fast Original Meal Bar)<br>`usda:2708123` Nutrition bar (South Beach Living Meal Bar) | code 1.0: `usda:2708121` ~ `usda:173139`<br>code 1.0: `usda:2708123` ~ `usda:173139` |
| `usda:173140` | `usda:173140` Snacks, soy chips or crisps, salted<br>`usda:2707434` Soy chips | code 1.0: `usda:2707434` ~ `usda:173140` |
| `usda:173142` | `usda:173142` Snacks, plantain chips, salted<br>`usda:2709563` Plantain chips | code 1.0: `usda:2709563` ~ `usda:173142` |
| `usda:173145` | `usda:173145` Snacks, granola bar, chewy, reduced sugar, all flavors<br>`usda:2708097` Cereal or granola bar (Quaker Chewy 25% Less Sugar Granola Bar)<br>`usda:2708104` Cereal or granola bar, reduced sugar, NFS | code 1.0: `usda:2708097` ~ `usda:173145`<br>code 1.0: `usda:2708104` ~ `usda:173145` |
| `usda:173146` | `usda:173146` Snacks, granola bites, mixed flavors<br>`usda:2708099` Cereal or granola bar (Quaker Granola Bites) | code 1.0: `usda:2708099` ~ `usda:173146` |
| `usda:173147` | `usda:173147` Snacks, pita chips, salted<br>`usda:2708215` Pita chips | code 1.0: `usda:2708215` ~ `usda:173147` |
| `usda:173148` | `usda:173148` Snacks, granola bars, soft, almond, confectioners coating<br>`usda:2708110` Cereal or granola bar, oats, nuts, coated with non-chocolate coating | code 1.0: `usda:2708110` ~ `usda:173148` |
| `usda:173149` | `usda:173149` Formulated bar, high fiber, chewy, oats and chocolate<br>`usda:2708082` Cereal or granola bar (General Mills Fiber One Chewy Bar)<br>`usda:2708112` Cereal or granola bar, high fiber, coated with non-chocolate yogurt coating | code 1.0: `usda:2708082` ~ `usda:173149`<br>code 1.0: `usda:2708112` ~ `usda:173149` |
| `usda:173150` | `usda:173150` Snacks, bagel chips, plain<br>`usda:2708292` Bagel chips | code 1.0: `usda:2708292` ~ `usda:173150` |
| `usda:173151` | `usda:173151` Snacks, NUTRI-GRAIN FRUIT AND NUT BAR<br>`usda:2708085` Cereal or granola bar (Kellogg's Nutri-Grain Fruit and Nut Bar) | code 1.0: `usda:2708085` ~ `usda:173151` |
| `usda:173153` | `usda:173153` Snacks, granola bar, GENERAL MILLS, NATURE VALLEY, CHEWY TRAIL MIX<br>`usda:2708091` Cereal or granola bar (General Mills Nature Valley Chewy Trail Mix) | code 1.0: `usda:2708091` ~ `usda:173153` |
| `usda:173154` | `usda:173154` Snacks, granola bar, QUAKER, DIPPS, all flavors<br>`usda:2708098` Cereal or granola bar (Quaker Chewy Dipps Granola Bar)<br>`usda:2708107` Cereal or granola bar, chocolate coated, NFS | code 1.0: `usda:2708098` ~ `usda:173154`<br>code 1.0: `usda:2708107` ~ `usda:173154` |
| `usda:173155` | `usda:173155` Snacks, brown rice chips<br>`usda:2708161` Chips, rice | code 1.0: `usda:2708161` ~ `usda:173155` |
| `usda:173156` | `usda:173156` Snack, Pretzel, hard chocolate coated<br>`usda:2708259` Pretzels, hard, coated, NFS<br>`usda:2708260` Pretzels, hard, chocolate coated | code 1.0: `usda:2708259` ~ `usda:173156`<br>code 1.0: `usda:2708260` ~ `usda:173156` |
| `usda:173157` | `usda:173157` Snacks, peas, roasted, wasabi-flavored<br>`usda:2707422` Wasabi peas | code 1.0: `usda:2707422` ~ `usda:173157` |
| `usda:173158` | `usda:173158` Formulated Bar, SOUTH BEACH protein bar<br>`usda:2708124` Nutrition bar (South Beach Living High Protein Bar) | code 1.0: `usda:2708124` ~ `usda:173158` |
| `usda:173159` | `usda:173159` Snack, BALANCE, original bar<br>`usda:2708117` Nutrition bar (Balance Original Bar) | code 1.0: `usda:2708117` ~ `usda:173159` |
| `usda:173160` | `usda:173160` Snacks, shrimp cracker<br>`usda:2708246` Shrimp chips | code 1.0: `usda:2708246` ~ `usda:173160` |
| `usda:173161` | `usda:173161` Rice crackers<br>`usda:2708163` Crackers, rice | code 1.0: `usda:2708163` ~ `usda:173161` |
| `usda:173162` | `usda:173162` Beverages, MONSTER energy drink, low carb<br>`usda:2710757` Energy drink, low calorie (Monster)<br>`usda:2710758` Energy drink, sugar free (Monster) | code 1.0: `usda:2710757` ~ `usda:173162`<br>code 1.0: `usda:2710758` ~ `usda:173162` |
| `usda:173165` | `usda:173165` Beverages, THE COCA-COLA COMPANY, NOS energy drink, Original, grape, loaded cherry, charged citrus, fortified with vitamins B6 and B12<br>`usda:2710751` Energy drink (NOS) | code 1.0: `usda:2710751` ~ `usda:173165` |
| `usda:173167` | `usda:173167` Beverages, ABBOTT, EAS whey protein powder<br>`usda:2710731` Nutritional powder mix (EAS Whey Protein Powder) | code 1.0: `usda:2710731` ~ `usda:173167` |
| `usda:173169` | `usda:173169` Beverages, NESTLE, Boost plus, nutritional drink, ready-to-drink<br>`usda:2710715` Nutritional drink or shake, ready-to-drink (Boost Plus)<br>`usda:2710727` Nutritional drink or shake, high protein, light, ready-to-drink, NFS<br>`usda:2710728` Nutritional drink or shake, liquid, soy-based | code 1.0: `usda:2710715` ~ `usda:173169`<br>code 1.0: `usda:2710727` ~ `usda:173169`<br>code 1.0: `usda:2710728` ~ `usda:173169` |
| `usda:173170` | `usda:173170` Beverages, SLIMFAST, Meal replacement,  High Protein Shake, Ready-To-Drink, 3-2-1 plan<br>`usda:2710724` Nutritional drink or shake, high protein, ready-to-drink (Slim Fast)<br>`usda:2710726` Nutritional drink or shake, high protein, ready-to-drink, NFS | code 1.0: `usda:2710724` ~ `usda:173170`<br>code 1.0: `usda:2710726` ~ `usda:173170` |
| `usda:173171` | `usda:173171` Beverages, UNILEVER, SLIMFAST, meal replacement, regular, ready-to-drink,  3-2-1 Plan<br>`usda:2710722` Nutritional drink or shake, ready-to-drink (Slim Fast)<br>`usda:2710723` Nutritional drink or shake, ready-to-drink, sugar free (Slim Fast) | code 1.0: `usda:2710722` ~ `usda:173171`<br>code 1.0: `usda:2710723` ~ `usda:173171` |
| `usda:173172` | `usda:173172` Beverages, UNILEVER, SLIMFAST Shake Mix, powder, 3-2-1 Plan<br>`usda:2710737` Nutritional powder mix (Slim Fast)<br>`usda:2710738` Nutritional powder mix, sugar free (Slim Fast) | code 1.0: `usda:2710737` ~ `usda:173172`<br>code 1.0: `usda:2710738` ~ `usda:173172` |
| `usda:173174` | `usda:173174` Beverages, UNILEVER, SLIMFAST Shake Mix, high protein, whey powder, 3-2-1 Plan,<br>`usda:2710739` Nutritional powder mix, high protein (Slim Fast) | code 1.0: `usda:2710739` ~ `usda:173174` |
| `usda:173175` | `usda:173175` Beverages, Acai berry drink, fortified<br>`usda:2710777` Fruit juice, acai blend | code 1.0: `usda:2710777` ~ `usda:173175` |
| `usda:173176` | `usda:173176` Alcoholic beverage, wine, dessert, sweet<br>`usda:2710692` Wine, dessert, sweet | code 1.0: `usda:2710692` ~ `usda:173176` |
| `usda:173177` | `usda:173177` Beverages, Whey protein powder isolate<br>`usda:2710734` Nutritional powder mix (Isopure) | code 1.0: `usda:2710734` ~ `usda:173177` |
| `usda:173178` | `usda:173178` Beverages, Orange juice, light, No pulp<br>`usda:2710590` Orange juice beverage, 40-50% juice, light | code 1.0: `usda:2710590` ~ `usda:173178` |
| `usda:173180` | `usda:173180` Beverages, Protein powder whey based<br>`usda:2710742` Nutritional powder mix, whey based, NFS<br>`usda:2710745` Nutritional powder mix, protein, NFS | code 1.0: `usda:2710742` ~ `usda:173180`<br>code 1.0: `usda:2710745` ~ `usda:173180` |
| `usda:173181` | `usda:173181` Beverages, Protein powder soy based<br>`usda:2710743` Nutritional powder mix, protein, soy based, NFS | code 1.0: `usda:2710743` ~ `usda:173181` |
| `usda:173188` | `usda:173188` Beverages, The COCA-COLA company, Glaceau Vitamin Water, Revive Fruit Punch, fortified<br>`usda:2710712` Water, enhanced, diet | code 1.0: `usda:2710712` ~ `usda:173188` |
| `usda:173197` | `usda:173197` Beverages, Mixed vegetable and fruit juice drink, with added nutrients<br>`usda:2710581` Vegetable and fruit juice drink, with high vitamin C | code 1.0: `usda:2710581` ~ `usda:173197` |
| `usda:173199` | `usda:173199` Carbonated beverage, cream soda<br>`usda:2710549` Soft drink, cream soda | code 1.0: `usda:2710549` ~ `usda:173199` |
| `usda:173204` | `usda:173204` Beverages, carbonated, low calorie, other than cola or pepper,  without caffeine<br>`usda:2710540` Water, carbonated, flavored<br>`usda:2710550` Soft drink, cream soda, diet<br>`usda:2710552` Soft drink, fruit flavored, diet, caffeine free<br>`usda:2710556` Soft drink, ginger ale, diet<br>`usda:2710558` Soft drink, root beer, diet | code 1.0: `usda:2710540` ~ `usda:173204`<br>code 1.0: `usda:2710550` ~ `usda:173204`<br>code 1.0: `usda:2710552` ~ `usda:173204`<br>code 1.0: `usda:2710556` ~ `usda:173204`<br>code 1.0: `usda:2710558` ~ `usda:173204` |
| `usda:173206` | `usda:173206` Beverages, carbonated, SPRITE, lemon-lime, without caffeine<br>`usda:2710551` Soft drink, fruit flavored, caffeine free | code 1.0: `usda:2710551` ~ `usda:173206` |
| `usda:173207` | `usda:173207` Beverages, carbonated, low calorie, other than cola or pepper, with aspartame, contains caffeine<br>`usda:2710554` Soft drink, fruit flavored, caffeine containing, diet | code 1.0: `usda:2710554` ~ `usda:173207` |
| `usda:173210` | `usda:173210` Beverages, Energy drink, RED BULL<br>`usda:2710752` Energy drink (Red Bull)<br>`usda:2710756` Energy Drink | code 1.0: `usda:2710752` ~ `usda:173210`<br>code 1.0: `usda:2710756` ~ `usda:173210` |
| `usda:173211` | `usda:173211` Beverages, tea, black, ready to drink, decaffeinated, diet<br>`usda:2710530` Tea, iced, bottled, black, decaffeinated, diet | code 1.0: `usda:2710530` ~ `usda:173211` |
| `usda:173212` | `usda:173212` Beverages, tea, black, ready to drink, decaffeinated<br>`usda:2710528` Tea, iced, bottled, black, decaffeinated | code 1.0: `usda:2710528` ~ `usda:173212` |
| `usda:173216` | `usda:173216` Lemonade, frozen concentrate, white<br>`usda:2710572` Lemonade, frozen concentrate, not reconstituted | code 1.0: `usda:2710572` ~ `usda:173216` |
| `usda:173222` | `usda:173222` Beverages, OVALTINE, chocolate malt powder<br>`usda:2705590` Milk, malted, dry mix, not reconstituted | code 1.0: `usda:2705590` ~ `usda:173222` |
| `usda:173226` | `usda:173226` Shake, fast food, vanilla<br>`usda:2705509` Milk shake, fast food, flavors other than chocolate<br>`usda:2705511` Milk shake, bottled, flavors other than chocolate | code 1.0: `usda:2705509` ~ `usda:173226`<br>code 1.0: `usda:2705511` ~ `usda:173226` |
| `usda:173227` | `usda:173227` Beverages, tea, black, brewed, prepared with tap water<br>`usda:2710488` Tea, hot, leaf, black<br>`usda:2710517` Tea, iced, brewed, black, unsweetened | code 1.0: `usda:2710488` ~ `usda:173227`<br>code 1.0: `usda:2710517` ~ `usda:173227` |
| `usda:173230` | `usda:173230` Beverages, tea, instant, unsweetened, powder<br>`usda:2710510` Tea, iced, instant, black, unsweetened, dry | code 1.0: `usda:2710510` ~ `usda:173230` |
| `usda:173231` | `usda:173231` Beverages, tea, instant, lemon, diet<br>`usda:2710496` Tea, iced, instant, black, pre-sweetened with low calorie sweetener | code 1.0: `usda:2710496` ~ `usda:173231` |
| `usda:173232` | `usda:173232` Beverages, tea, herb, other than chamomile, brewed<br>`usda:2710502` Tea, hot, herbal | code 1.0: `usda:2710502` ~ `usda:173232` |
| `usda:173235` | `usda:173235` Beverages, orange-flavor drink, breakfast type, powder<br>`usda:2710612` Fruit flavored drink, with high vitamin C, powdered, not reconstituted | code 1.0: `usda:2710612` ~ `usda:173235` |
| `usda:173265` | `usda:173265` Pasta, gluten-free, corn and rice flour, cooked<br>`usda:2708359` Pasta, gluten free | code 1.0: `usda:2708359` ~ `usda:173265` |
| `usda:173273` | `usda:173273` Fast foods, potatoes, hash browns, round pieces or patty<br>`usda:2709478` Potato, hash brown, from fast food<br>`usda:2709480` Potato, hash brown, from restaurant | code 1.0: `usda:2709478` ~ `usda:173273`<br>code 1.0: `usda:2709480` ~ `usda:173273` |
| `usda:173292` | `usda:173292` Fast Food, Pizza Chain, 14" pizza, cheese topping, regular crust<br>`usda:2708614` Pizza, cheese, from restaurant or fast food, NS as to type of crust<br>`usda:2708615` Pizza, cheese, from restaurant or fast food, thin crust<br>`usda:2708616` Pizza, cheese, from restaurant or fast food, medium crust | code 1.0: `usda:2708614` ~ `usda:173292`<br>code 1.0: `usda:2708615` ~ `usda:173292`<br>code 1.0: `usda:2708616` ~ `usda:173292` |
| `usda:173293` | `usda:173293` Fast Food, Pizza Chain, 14" pizza, cheese topping, thick crust<br>`usda:2708617` Pizza, cheese, from restaurant or fast food, thick crust | code 1.0: `usda:2708617` ~ `usda:173293` |
| `usda:173295` | `usda:173295` Fast Food, Pizza Chain, 14" pizza, pepperoni topping, regular crust<br>`usda:2708638` Pizza with pepperoni, from restaurant or fast food, NS as to type of crust<br>`usda:2708639` Pizza with pepperoni, from restaurant or fast food, thin crust<br>`usda:2708640` Pizza with pepperoni, from restaurant or fast food,  medium crust | code 1.0: `usda:2708638` ~ `usda:173295`<br>code 1.0: `usda:2708639` ~ `usda:173295`<br>code 1.0: `usda:2708640` ~ `usda:173295` |
| `usda:173296` | `usda:173296` Fast Food, Pizza Chain, 14" pizza, pepperoni topping, thick crust<br>`usda:2708641` Pizza with pepperoni, from restaurant or fast food, thick crust | code 1.0: `usda:2708641` ~ `usda:173296` |
| `usda:173317` | `usda:173317` Fast foods, hamburger; single, large patty; with condiments, vegetables and mayonnaise<br>`usda:2706931` Whopper (Burger King) | code 1.0: `usda:2706931` ~ `usda:173317` |
| `usda:173319` | `usda:173319` Fast foods, cheeseburger; double, regular patty; with condiments<br>`usda:2706914` Double cheeseburger (McDonalds)<br>`usda:2706915` McDouble (McDonalds) | code 1.0: `usda:2706914` ~ `usda:173319`<br>code 1.0: `usda:2706915` ~ `usda:173319` |
| `usda:173321` | `usda:173321` Fast foods, chicken tenders<br>`usda:2706099` Chicken tenders or strips, breaded, from fast food | code 1.0: `usda:2706099` ~ `usda:173321` |
| `usda:173325` | `usda:173325` Macaroni and Cheese, canned entree<br>`usda:2708814` Macaroni or noodles with cheese, canned | code 1.0: `usda:2708814` ~ `usda:173325` |
| `usda:173328` | `usda:173328` Ravioli, cheese-filled, canned<br>`usda:2708769` Ravioli, cheese-filled, with tomato sauce, canned | code 1.0: `usda:2708769` ~ `usda:173328` |
| `usda:173332` | `usda:173332` Beef, corned beef hash, with potato, canned<br>`usda:2706477` Corned beef hash<br>`usda:2706502` Corned beef patty<br>`usda:2706584` Hash, NS as to type of meat | code 1.0: `usda:2706477` ~ `usda:173332`<br>code 1.0: `usda:2706502` ~ `usda:173332`<br>code 1.0: `usda:2706584` ~ `usda:173332` |
| `usda:173333` | `usda:173333` Lasagna, cheese, frozen, prepared<br>`usda:2708758` Lasagna, meatless | code 1.0: `usda:2708758` ~ `usda:173333` |
| `usda:173334` | `usda:173334` Lasagna with meat & sauce, frozen entree<br>`usda:2708750` Lasagna with meat<br>`usda:2708754` Lasagna with meat, frozen | code 1.0: `usda:2708750` ~ `usda:173334`<br>code 1.0: `usda:2708754` ~ `usda:173334` |
| `usda:173338` | `usda:173338` Turkey, stuffing, mashed potatoes w/gravy, assorted vegetables, frozen, microwaved<br>`usda:2707118` Turkey with gravy, dressing, potatoes, vegetable, frozen meal | code 1.0: `usda:2707118` ~ `usda:173338` |
| `usda:173339` | `usda:173339` Rice bowl with chicken, frozen entree, prepared (includes fried, teriyaki, and sweet and sour varieties)<br>`usda:2707109` Teriyaki chicken with rice and vegetable, diet frozen meal | code 1.0: `usda:2707109` ~ `usda:173339` |
| `usda:173343` | `usda:173343` Potato salad with egg<br>`usda:2709532` Potato salad with egg, made with mayonnaise | code 1.0: `usda:2709532` ~ `usda:173343` |
| `usda:173345` | `usda:173345` Corn dogs, frozen, prepared<br>`usda:2707044` Corn dog | code 1.0: `usda:2707044` ~ `usda:173345` |
| `usda:173346` | `usda:173346` Chicken tenders, breaded, frozen, prepared<br>`usda:2706089` Chicken fillet, breaded<br>`usda:2706102` Chicken tenders or strips, breaded, from frozen | code 1.0: `usda:2706089` ~ `usda:173346`<br>code 1.0: `usda:2706102` ~ `usda:173346` |
| `usda:173411` | `usda:173411` Butter, whipped, with salt<br>`usda:2710156` Butter, tub | code 1.0: `usda:2710156` ~ `usda:173411` |
| `usda:173412` | `usda:173412` Butter oil, anhydrous<br>`usda:2710168` Ghee, clarified butter | code 1.0: `usda:2710168` ~ `usda:173412` |
| `usda:328637` | `usda:173414` Cheese, cheddar (Includes foods for USDA's Food Distribution Program)<br>`usda:2705709` Cheese, Cheddar<br>`usda:328637` Cheese, cheddar | code 1.0: `usda:328637` ~ `usda:173414`<br>code 1.0: `usda:2705709` ~ `usda:173414` |
| `usda:173416` | `usda:173416` Cheese, colby<br>`usda:2705712` Cheese, Colby | code 1.0: `usda:2705712` ~ `usda:173416` |
| `usda:2346385` | `usda:173418` Cheese, cream<br>`usda:2346385` Cream cheese, full fat, block<br>`usda:2705760` Cream cheese, regular, plain | code 1.0: `usda:2346385` ~ `usda:173418`<br>code 1.0: `usda:2705760` ~ `usda:173418` |
| `usda:329596` | `usda:173421` Egg, yolk, raw, frozen, pasteurized<br>`usda:329596` Egg, yolk, raw, frozen, pasteurized | code 1.0: `usda:329596` ~ `usda:173421` |
| `usda:329716` | `usda:173428` Egg, yolk, dried<br>`usda:329716` Egg, yolk, dried | code 1.0: `usda:329716` ~ `usda:173428` |
| `usda:789828` | `usda:173430` Butter, without salt<br>`usda:789828` Butter, stick, unsalted | code 1.0: `usda:789828` ~ `usda:173430` |
| `usda:173433` | `usda:173433` Cheese, goat, semisoft type<br>`usda:2705716` Cheese, goat | code 1.0: `usda:2705716` ~ `usda:173433` |
| `usda:173440` | `usda:173440` Cheese, low-sodium, cheddar or colby<br>`usda:2705739` Cheese, Cheddar, reduced sodium | code 1.0: `usda:2705739` ~ `usda:173440` |
| `usda:173443` | `usda:173443` Sour cream, light<br>`usda:2705615` Sour cream, light | code 1.0: `usda:2705615` ~ `usda:173443` |
| `usda:173444` | `usda:173444` Sour cream, fat free<br>`usda:2705616` Sour cream, fat free | code 1.0: `usda:2705616` ~ `usda:173444` |
| `usda:173452` | `usda:173452` Cheese, parmesan, dry grated, reduced fat<br>`usda:2705729` Cheese, Parmesan, dry grated, reduced fat | same 1.0: `usda:173452` ~ `usda:2705729` |
| `usda:173453` | `usda:173453` Cream substitute, flavored, liquid<br>`usda:2705601` Coffee creamer, liquid, flavored | code 1.0: `usda:2705601` ~ `usda:173453` |
| `usda:173455` | `usda:173455` Cheese product, pasteurized process, American, reduced fat, fortified with vitamin D<br>`usda:2705765` Cheese, American, reduced fat | code 1.0: `usda:2705765` ~ `usda:173455` |
| `usda:173459` | `usda:173459` Protein supplement, milk based, Muscle Milk, powder<br>`usda:2710735` Nutritional powder mix (Muscle Milk) | code 1.0: `usda:2710735` ~ `usda:173459` |
| `usda:173460` | `usda:173460` Protein supplement, milk based, Muscle Milk Light, powder<br>`usda:2710736` Nutritional powder mix, light (Muscle Milk)<br>`usda:2710744` Nutritional powder mix, protein, light, NFS | code 1.0: `usda:2710736` ~ `usda:173460`<br>code 1.0: `usda:2710744` ~ `usda:173460` |
| `usda:173461` | `usda:173461` Dulce de Leche<br>`usda:2705699` Dulce de leche | code 1.0: `usda:2705699` ~ `usda:173461` |
| `usda:173466` | `usda:173466` Ice cream, bar or stick, chocolate covered<br>`usda:2705639` Ice cream bar, vanilla, chocolate coated | code 1.0: `usda:2705639` ~ `usda:173466` |
| `usda:746775` | `usda:173468` Salt, table<br>`usda:746775` Salt, table, iodized | code 1.0: `usda:746775` ~ `usda:173468` |
| `usda:173472` | `usda:173472` Horseradish, prepared<br>`usda:2710083` Horseradish | code 1.0: `usda:2710083` ~ `usda:173472` |
| `usda:173477` | `usda:173477` Clif Z bar<br>`usda:2708119` Nutrition bar (Clif Kids Organic Zbar) | code 1.0: `usda:2708119` ~ `usda:173477` |
| `usda:173479` | `usda:173479` Babyfood, meat, beef, strained<br>`usda:2705861` Baby Toddler beef | code 1.0: `usda:2705861` ~ `usda:173479` |
| `usda:173483` | `usda:173483` Babyfood, meat, chicken, strained<br>`usda:2706151` Baby Toddler chicken | code 1.0: `usda:2706151` ~ `usda:173483` |
| `usda:173484` | `usda:173484` Babyfood, meat, turkey sticks, junior<br>`usda:2705904` Baby Toddler meat stick | code 1.0: `usda:2705904` ~ `usda:173484` |
| `usda:173505` | `usda:173505` Babyfood, vegetables, beets, strained<br>`usda:2710126` Baby Toddler beets | code 1.0: `usda:2710126` ~ `usda:173505` |
| `usda:173506` | `usda:173506` Babyfood, vegetables, carrots, strained<br>`usda:2710118` Baby Toddler carrots, Stage 1 | code 1.0: `usda:2710118` ~ `usda:173506` |
| `usda:173507` | `usda:173507` Babyfood, vegetables, carrots, junior<br>`usda:2710119` Baby Toddler carrots, Stage 2 | code 1.0: `usda:2710119` ~ `usda:173507` |
| `usda:173512` | `usda:173512` Babyfood, fruit, applesauce, strained<br>`usda:2709363` Baby Toddler apples, Stage 1 | code 1.0: `usda:2709363` ~ `usda:173512` |
| `usda:173520` | `usda:173520` Babyfood, snack, GERBER, GRADUATES, YOGURT MELTS<br>`usda:2709381` Baby Toddler yogurt melts | code 1.0: `usda:2709381` ~ `usda:173520` |
| `usda:173562` | `usda:173562` Salad dressing, blue or roquefort cheese dressing, commercial, regular<br>`usda:2710197` Blue or roquefort cheese dressing | code 1.0: `usda:2710197` ~ `usda:173562` |
| `usda:173581` | `usda:173581` Butter, light, stick, with salt<br>`usda:2710157` Butter, light | code 1.0: `usda:2710157` ~ `usda:173581` |
| `usda:173582` | `usda:173582` Margarine-like, vegetable oil spread, 60% fat, tub, with salt<br>`usda:2710161` Butter replacement, liquid | code 1.0: `usda:2710161` ~ `usda:173582` |
| `usda:173584` | `usda:173584` Shortening, vegetable, household, composite<br>`usda:2710167` Shortening, NS as to vegetable or animal | code 1.0: `usda:2710167` ~ `usda:173584` |
| `usda:173590` | `usda:173590` Salad dressing, italian dressing, fat-free<br>`usda:2710234` Italian dressing, fat free | code 1.0: `usda:2710234` ~ `usda:173590` |
| `usda:2758988` | `usda:173592` Salad dressing, ranch dressing, regular<br>`usda:2710195` Salad dressing, NFS, for salads<br>`usda:2710212` Ranch dressing<br>`usda:2758988` Dressing, Ranch | code 1.0: `usda:2758988` ~ `usda:173592`<br>code 1.0: `usda:2710195` ~ `usda:173592`<br>code 1.0: `usda:2710212` ~ `usda:173592` |
| `usda:173594` | `usda:173594` Salad dressing, mayonnaise, light<br>`usda:2710220` Mayonnaise, light | code 1.0: `usda:2710220` ~ `usda:173594` |
| `usda:173647` | `usda:173647` Beverages, water, tap, drinking<br>`usda:2710707` Water, tap | code 1.0: `usda:2710707` ~ `usda:173647` |
| `usda:173660` | `usda:173660` Beverages, PEPSICO QUAKER, Gatorade, G performance O 2, ready-to-drink.<br>`usda:2710769` Sports drink (Gatorade G)<br>`usda:2710771` Sports drink, NFS | code 1.0: `usda:2710769` ~ `usda:173660`<br>code 1.0: `usda:2710771` ~ `usda:173660` |
| `usda:173687` | `usda:173687` Fish, salmon, chinook, smoked<br>`usda:2706292` Fish, salmon, smoked | code 1.0: `usda:2706292` ~ `usda:173687` |
| `usda:334194` | `usda:173709` Fish, tuna, light, canned in water, drained solids (Includes foods for USDA's Food Distribution Program)<br>`usda:2706311` Fish, tuna, canned<br>`usda:334194` Fish, tuna, light, canned in water, drained solids | code 1.0: `usda:334194` ~ `usda:173709`<br>code 1.0: `usda:2706311` ~ `usda:173709` |
| `usda:173724` | `usda:173724` Fish, Salmon, pink, canned, drained solids, without skin and bones<br>`usda:2706291` Fish, salmon, canned | code 1.0: `usda:2706291` ~ `usda:173724` |
| `usda:173732` | `usda:173732` Beans, baked, canned, with pork and sweet sauce<br>`usda:2707390` Baked beans<br>`usda:2707406` Pork and beans | code 1.0: `usda:2707390` ~ `usda:173732`<br>code 1.0: `usda:2707406` ~ `usda:173732` |
| `usda:173806` | `usda:173806` Peanuts, all types, dry-roasted, without salt<br>`usda:2707519` Peanuts, dry roasted, unsalted | code 1.0: `usda:2707519` ~ `usda:173806` |
| `usda:323121` | `usda:173862` Frankfurter, beef, unheated<br>`usda:2706166` Hot dog, NFS<br>`usda:2706167` Hot dog, beef<br>`usda:323121` Frankfurter, beef, unheated | code 1.0: `usda:323121` ~ `usda:173862`<br>code 1.0: `usda:2706166` ~ `usda:173862`<br>code 1.0: `usda:2706167` ~ `usda:173862` |
| `usda:332397` | `usda:173863` Ham, sliced, pre-packaged, deli meat (96%fat free, water added)<br>`usda:2706205` Luncheon meat, NFS<br>`usda:2706206` Ham, prepackaged or deli, luncheon meat<br>`usda:332397` Ham, sliced, pre-packaged, deli meat (96%fat free, water added) | code 1.0: `usda:332397` ~ `usda:173863`<br>code 1.0: `usda:2706205` ~ `usda:173863`<br>code 1.0: `usda:2706206` ~ `usda:173863` |
| `usda:173866` | `usda:173866` Ham salad spread<br>`usda:2706222` Ham salad spread | code 1.0: `usda:2706222` ~ `usda:173866` |
| `usda:173867` | `usda:173867` Knackwurst, knockwurst, pork, beef<br>`usda:2706181` Knockwurst | code 1.0: `usda:2706181` ~ `usda:173867` |
| `usda:173874` | `usda:173874` Chicken breast, deli, rotisserie seasoned, sliced, prepackaged<br>`usda:2706208` Chicken, prepackaged or deli, luncheon meat | code 1.0: `usda:2706208` ~ `usda:173874` |
| `usda:173875` | `usda:173875` Frankfurter, meat and poultry, unheated<br>`usda:2706168` Hot dog, meat and poultry | code 1.0: `usda:2706168` ~ `usda:173875` |
| `usda:173877` | `usda:173877` Kielbasa, fully cooked, grilled<br>`usda:2706188` Polish sausage | code 1.0: `usda:2706188` ~ `usda:173877` |
| `usda:173933` | `usda:173933` Apple juice, canned or bottled, unsweetened, without added ascorbic acid<br>`usda:2709319` Apple cider | code 1.0: `usda:2709319` ~ `usda:173933` |
| `usda:173947` | `usda:173947` Blackberry juice, canned<br>`usda:2709322` Blackberry juice, 100% | code 1.0: `usda:2709322` ~ `usda:173947` |
| `usda:173950` | `usda:173950` Blueberries, frozen, unsweetened (Includes foods for USDA's Food Distribution Program)<br>`usda:2709277` Blueberries, frozen | code 1.0: `usda:2709277` ~ `usda:173950` |
| `usda:173961` | `usda:173961` Cranberry sauce, canned, sweetened<br>`usda:2709280` Cranberry sauce | code 1.0: `usda:2709280` ~ `usda:173961` |
| `usda:746761` | `usda:173997` Beef, round, top round roast, boneless, separable lean only, trimmed to 0" fat, select, raw<br>`usda:746761` Beef, round, top round roast, boneless, separable lean only, trimmed to 0" fat, select, raw | code 1.0: `usda:746761` ~ `usda:173997` |
| `usda:746758` | `usda:174006` Beef, loin, tenderloin roast, separable lean only, boneless, trimmed to 0" fat, select, cooked, roasted<br>`usda:746758` Beef, loin, tenderloin roast, separable lean only, boneless, trimmed to 0" fat, select, cooked, roasted | code 1.0: `usda:746758` ~ `usda:174006` |
| `usda:746759` | `usda:174010` Beef, loin, top loin steak, boneless, lip-on, separable lean only, trimmed to 1/8" fat, choice, raw<br>`usda:746759` Beef, loin, top loin steak, boneless, lip-on, separable lean only, trimmed to 1/8" fat, choice, raw | code 1.0: `usda:746759` ~ `usda:174010` |
| `usda:2514743` | `usda:174030` Beef, ground, 90% lean meat / 10% fat, raw<br>`usda:2514743` Beef, ground, 90% lean meat / 10% fat, raw | code 1.0: `usda:2514743` ~ `usda:174030` |
| `usda:2514744` | `usda:174036` Beef, ground, 80% lean meat / 20% fat, raw<br>`usda:2514744` Beef, ground, 80% lean meat / 20% fat, raw | code 1.0: `usda:2514744` ~ `usda:174036` |
| `usda:174066` | `usda:174066` Sauce, sweet and sour, ready-to-serve<br>`usda:2710296` Sweet and sour sauce | code 1.0: `usda:2710296` ~ `usda:174066` |
| `usda:174067` | `usda:174067` Sauce, cocktail, ready-to-serve<br>`usda:2709753` Cocktail sauce | code 1.0: `usda:2709753` ~ `usda:174067` |
| `usda:174068` | `usda:174068` Dip, salsa con queso, cheese and salsa- medium<br>`usda:2705785` Cheese dip with chili pepper | code 1.0: `usda:2705785` ~ `usda:174068` |
| `usda:174070` | `usda:174070` Sauce, peanut, made from peanut butter, water, soy sauce<br>`usda:2707546` Peanut sauce | code 1.0: `usda:2707546` ~ `usda:174070` |
| `usda:174074` | `usda:174074` Sauce, enchilada, red, mild, ready to serve<br>`usda:2709741` Enchilada sauce, red | code 1.0: `usda:2709741` ~ `usda:174074` |
| `usda:174075` | `usda:174075` Bread, chapati or roti, whole wheat, commercially prepared, frozen<br>`usda:2707713` Bread, chappatti or roti | code 1.0: `usda:2707713` ~ `usda:174075` |
| `usda:174076` | `usda:174076` Bread, paratha, whole wheat, commercially prepared, frozen<br>`usda:2707715` Bread, paratha | code 1.0: `usda:2707715` ~ `usda:174076` |
| `usda:174077` | `usda:174077` Bread, naan, whole wheat, commercially prepared, refrigerated<br>`usda:2707613` Bread, naan | code 1.0: `usda:2707613` ~ `usda:174077` |
| `usda:174078` | `usda:174078` Bread, roll, Mexican, bollilo<br>`usda:2707664` Roll, Mexican, bolillo | code 1.0: `usda:2707664` ~ `usda:174078` |
| `usda:174079` | `usda:174079` Cookie, butter or sugar, with chocolate icing or filling<br>`usda:2707978` Cookie, butter or sugar, with chocolate icing or filling | code 1.0: `usda:2707978` ~ `usda:174079` |
| `usda:174080` | `usda:174080` Cookie, chocolate, with icing or coating<br>`usda:2707918` Cookie, chocolate, with icing or coating | code 1.0: `usda:2707918` ~ `usda:174080` |
| `usda:174081` | `usda:174081` Tortillas, ready-to-bake or -fry, whole wheat<br>`usda:2707825` Tortilla, whole wheat | code 1.0: `usda:2707825` ~ `usda:174081` |
| `usda:174083` | `usda:174083` Cookies, graham crackers, plain or honey, lowfat<br>`usda:2708138` Graham crackers, reduced fat | code 1.0: `usda:2708138` ~ `usda:174083` |
| `usda:174084` | `usda:174084` Crackers, cheese, whole grain<br>`usda:2708155` Crackers, cheese, whole grain | code 1.0: `usda:2708155` ~ `usda:174084` |
| `usda:174085` | `usda:174085` Waffles, whole wheat, lowfat, frozen, ready-to-heat<br>`usda:2708318` Waffle, whole grain, reduced fat<br>`usda:2708324` Waffle, school | code 1.0: `usda:2708318` ~ `usda:174085`<br>code 1.0: `usda:2708324` ~ `usda:174085` |
| `usda:174086` | `usda:174086` Pancakes, plain, reduced fat<br>`usda:2708305` Pancakes, plain, reduced fat | same 1.0: `usda:174086` ~ `usda:2708305` |
| `usda:174087` | `usda:174087` Cookies, shortbread, reduced fat<br>`usda:2707965` Cookie, shortbread, reduced fat | code 1.0: `usda:2707965` ~ `usda:174087` |
| `usda:174088` | `usda:174088` Cookies, sugar wafer, chocolate-covered<br>`usda:2707919` Cookie, sugar wafer, chocolate-covered | code 1.0: `usda:2707919` ~ `usda:174088` |
| `usda:174089` | `usda:174089` Rolls, hamburger or hot dog, wheat/cracked wheat<br>`usda:2707747` Roll, wheat or cracked wheat, hot dog bun<br>`usda:2707748` Roll, wheat or cracked wheat, hamburger bun | code 1.0: `usda:2707747` ~ `usda:174089`<br>code 1.0: `usda:2707748` ~ `usda:174089` |
| `usda:174090` | `usda:174090` Rolls, hamburger or hot dog, whole wheat<br>`usda:2707750` Roll, whole wheat, hot dog bun<br>`usda:2707751` Roll, whole wheat, hamburger bun | code 1.0: `usda:2707750` ~ `usda:174090`<br>code 1.0: `usda:2707751` ~ `usda:174090` |
| `usda:174091` | `usda:174091` Bread, french or vienna, whole wheat<br>`usda:2707728` Bread, French or Vienna, whole wheat | code 1.0: `usda:2707728` ~ `usda:174091` |
| `usda:174094` | `usda:174094` Rolls, hamburger, whole grain white, calcium-fortified<br>`usda:2707752` Roll, whole grain white<br>`usda:2707753` Roll, whole grain white, hot dog bun<br>`usda:2707754` Roll, whole grain white, hamburger bun | code 1.0: `usda:2707752` ~ `usda:174094`<br>code 1.0: `usda:2707753` ~ `usda:174094`<br>code 1.0: `usda:2707754` ~ `usda:174094` |
| `usda:174095` | `usda:174095` Cookies, chocolate chip sandwich, with creme filling<br>`usda:2707912` Cookie, chocolate chip sandwich | code 1.0: `usda:2707912` ~ `usda:174095` |
| `usda:174096` | `usda:174096` Cookies, chocolate, made with rice cereal<br>`usda:2707913` Cookie, chocolate, made with rice cereal | code 1.0: `usda:2707913` ~ `usda:174096` |
| `usda:174097` | `usda:174097` Cookies, marshmallow, with rice cereal and chocolate chips<br>`usda:2707939` Cookie, marshmallow, with rice cereal and chocolate chips | code 1.0: `usda:2707939` ~ `usda:174097` |
| `usda:174100` | `usda:174100` Bread, gluten-free, white, made with rice flour, corn starch, and/or tapioca<br>`usda:2707794` Bread, rice<br>`usda:2707795` Bread, rice, toasted<br>`usda:2707797` Bread, gluten free<br>`usda:2707798` Bread, gluten free, toasted | code 1.0: `usda:2707794` ~ `usda:174100`<br>code 1.0: `usda:2707795` ~ `usda:174100`<br>code 1.0: `usda:2707797` ~ `usda:174100`<br>code 1.0: `usda:2707798` ~ `usda:174100` |
| `usda:174104` | `usda:174104` Crackers, gluten-free, multi-seeded and multigrain<br>`usda:2707799` Breadsticks, hard, gluten free<br>`usda:2708188` Crackers, gluten free, plain<br>`usda:2708189` Crackers, gluten free, flavored | code 1.0: `usda:2707799` ~ `usda:174104`<br>code 1.0: `usda:2708188` ~ `usda:174104`<br>code 1.0: `usda:2708189` ~ `usda:174104` |
| `usda:174105` | `usda:174105` Waffles, gluten-free, frozen, ready-to-heat<br>`usda:2708330` Waffle, gluten free | code 1.0: `usda:2708330` ~ `usda:174105` |
| `usda:174106` | `usda:174106` Pancakes, gluten-free, frozen, ready-to-heat<br>`usda:2708311` Pancakes, gluten free | code 1.0: `usda:2708311` ~ `usda:174106` |
| `usda:174107` | `usda:174107` Rolls, dinner, sweet<br>`usda:2707666` Roll, sweet, no frosting | code 1.0: `usda:2707666` ~ `usda:174107` |
| `usda:174108` | `usda:174108` Beverages,  Energy drink, Citrus<br>`usda:2710754` Energy drink (SoBe Energize Energy Juice Drink) | code 1.0: `usda:2710754` ~ `usda:174108` |
| `usda:174112` | `usda:174112` Beverages, Apple juice drink, light, fortified with vitamin C<br>`usda:2710591` Apple juice beverage, 40-50% juice, light | code 1.0: `usda:2710591` ~ `usda:174112` |
| `usda:174113` | `usda:174113` Beverages, POWERADE, Zero, Mixed Berry<br>`usda:2710773` Sports drink, low calorie (Powerade Zero) | code 1.0: `usda:2710773` ~ `usda:174113` |
| `usda:174120` | `usda:174120` Beverages, tea, Oolong, brewed<br>`usda:2710492` Tea, hot, leaf, oolong | code 1.0: `usda:2710492` ~ `usda:174120` |
| `usda:174125` | `usda:174125` Beverages, coffee, brewed, espresso, restaurant-prepared, decaffeinated<br>`usda:2710379` Coffee, espresso, decaffeinated | code 1.0: `usda:2710379` ~ `usda:174125` |
| `usda:174128` | `usda:174128` Beverages, tea, green, ready-to-drink, sweetened<br>`usda:2710500` Tea, iced, instant, green, pre-sweetened with sugar<br>`usda:2710533` Tea, iced, bottled, green | code 1.0: `usda:2710500` ~ `usda:174128`<br>code 1.0: `usda:2710533` ~ `usda:174128` |
| `usda:174131` | `usda:174131` Beverages, aloe vera juice drink, fortified with Vitamin C<br>`usda:2709833` Aloe vera juice drink | code 1.0: `usda:2709833` ~ `usda:174131` |
| `usda:174133` | `usda:174133` Beverages, coffee, instant, decaffeinated, powder<br>`usda:2710481` Coffee, instant, decaffeinated, not reconstituted | code 1.0: `usda:2710481` ~ `usda:174133` |
| `usda:174139` | `usda:174139` Beverages, coffee substitute, cereal grain beverage, prepared with water<br>`usda:2710486` Coffee substitute | code 1.0: `usda:2710486` ~ `usda:174139` |
| `usda:174141` | `usda:174141` Alcoholic beverage, malt beer, hard lemonade<br>`usda:2710619` Alcoholic malt beverage, sweetened<br>`usda:2710694` Wine cooler | code 1.0: `usda:2710619` ~ `usda:174141`<br>code 1.0: `usda:2710694` ~ `usda:174141` |
| `usda:174144` | `usda:174144` Beverages, tea, black, ready to drink<br>`usda:2710531` Tea, iced, bottled, black, unsweetened | code 1.0: `usda:2710531` ~ `usda:174144` |
| `usda:174146` | `usda:174146` Beverages, AMBER, hard cider<br>`usda:2710621` Hard cider | code 1.0: `usda:2710621` ~ `usda:174146` |
| `usda:174154` | `usda:174154` Beverages, coffee, instant, vanilla, sweetened, decaffeinated, with non dairy creamer<br>`usda:2710484` Coffee, instant, decaffeinated, pre-lightened and pre-sweetened with sugar, not reconstituted | code 1.0: `usda:2710484` ~ `usda:174154` |
| `usda:174156` | `usda:174156` Beverages, tea, herb, brewed, chamomile<br>`usda:2710505` Tea, hot, chamomile | code 1.0: `usda:2710505` ~ `usda:174156` |
| `usda:174157` | `usda:174157` Beverages, Wine, non-alcoholic<br>`usda:2710609` Wine, nonalcoholic | code 1.0: `usda:2710609` ~ `usda:174157` |
| `usda:174158` | `usda:174158` Water, bottled, generic<br>`usda:2710708` Water, bottled, plain | code 1.0: `usda:2710708` ~ `usda:174158` |
| `usda:174159` | `usda:174159` Beverages, chocolate-flavor beverage mix for milk, powder, with added nutrients<br>`usda:2705588` Chocolate beverage powder, dry mix, not reconstituted | code 1.0: `usda:2705588` ~ `usda:174159` |
| `usda:174161` | `usda:174161` Beverages, Water with added vitamins and minerals, bottles, sweetened, assorted fruit flavors<br>`usda:2710711` Water, enhanced, regular | code 1.0: `usda:2710711` ~ `usda:174161` |
| `usda:174171` | `usda:174171` Beverages, Energy drink, AMP<br>`usda:2710748` Energy drink (Mountain Dew AMP) | code 1.0: `usda:2710748` ~ `usda:174171` |
| `usda:174172` | `usda:174172` Beverages, Energy drink, FULL THROTTLE<br>`usda:2710746` Energy drink (Full Throttle) | code 1.0: `usda:2710746` ~ `usda:174172` |
| `usda:174173` | `usda:174173` Beverages, Vegetable and fruit juice drink, reduced calorie, with low-calorie sweetener, added vitamin C<br>`usda:2710594` Vegetable and fruit juice drink, with high vitamin C, diet<br>`usda:2710595` Vegetable and fruit juice drink, with high vitamin C, light | code 1.0: `usda:2710594` ~ `usda:174173`<br>code 1.0: `usda:2710595` ~ `usda:174173` |
| `usda:174175` | `usda:174175` Beverages, vegetable and fruit juice blend, 100% juice, with added vitamins A, C, E<br>`usda:2710145` Vegetable and fruit juice, 100% juice, with high vitamin C | code 1.0: `usda:2710145` ~ `usda:174175` |
| `usda:174176` | `usda:174176` Beverages, fruit juice drink, reduced sugar, with vitamin E added<br>`usda:2710586` Fruit juice drink, light<br>`usda:2710600` Fruit juice drink (Capri Sun) | code 1.0: `usda:2710586` ~ `usda:174176`<br>code 1.0: `usda:2710600` ~ `usda:174176` |
| `usda:174177` | `usda:174177` Beverages, Energy drink, VAULT Zero, sugar-free, citrus flavor<br>`usda:2710765` Energy drink, sugar free (Vault) | code 1.0: `usda:2710765` ~ `usda:174177` |
| `usda:174178` | `usda:174178` Beverages, PEPSICO QUAKER, Gatorade G2, low calorie<br>`usda:2710772` Sports drink, low calorie (Gatorade G2)<br>`usda:2710774` Sports drink, low calorie | code 1.0: `usda:2710772` ~ `usda:174178`<br>code 1.0: `usda:2710774` ~ `usda:174178` |
| `usda:174179` | `usda:174179` Beverages, Fruit flavored drink, less than 3% juice, not fortified with vitamin C<br>`usda:2710573` Fruit flavored drink | code 1.0: `usda:2710573` ~ `usda:174179` |
| `usda:174180` | `usda:174180` Beverages, Fruit flavored drink containing less than 3% fruit juice, with high vitamin C<br>`usda:2710578` Fruit flavored drink, with high vitamin C | code 1.0: `usda:2710578` ~ `usda:174180` |
| `usda:174181` | `usda:174181` Beverages, nutritional shake mix, high protein, powder<br>`usda:2710733` Nutritional powder mix, high protein (Herbalife)<br>`usda:2710741` Nutritional powder mix, high protein, NFS | code 1.0: `usda:2710733` ~ `usda:174181`<br>code 1.0: `usda:2710741` ~ `usda:174181` |
| `usda:174183` | `usda:174183` Fish, anchovy, european, canned in oil, drained solids<br>`usda:2706232` Fish, anchovy | code 1.0: `usda:2706232` ~ `usda:174183` |
| `usda:174188` | `usda:174188` Fish, caviar, black and red, granular<br>`usda:2706332` Caviar | code 1.0: `usda:2706332` ~ `usda:174188` |
| `usda:174195` | `usda:174195` Fish, fish sticks, frozen, prepared<br>`usda:2706231` Fish, stick | code 1.0: `usda:2706231` ~ `usda:174195` |
| `usda:174199` | `usda:174199` Fish, haddock, smoked<br>`usda:2706230` Fish, smoked | code 1.0: `usda:2706230` ~ `usda:174199` |
| `usda:174203` | `usda:174203` Crustaceans, crab, alaska king, imitation, made from surimi<br>`usda:2706568` Imitation crab meat | code 1.0: `usda:2706568` ~ `usda:174203` |
| `usda:174205` | `usda:174205` Crustaceans, crab, blue, cooked, moist heat<br>`usda:2706344` Crab | code 1.0: `usda:2706344` ~ `usda:174205` |
| `usda:174208` | `usda:174208` Crustaceans, lobster, northern, raw<br>`usda:2706349` Lobster | code 1.0: `usda:2706349` ~ `usda:174208` |
| `usda:174216` | `usda:174216` Mollusks, mussel, blue, raw<br>`usda:2706350` Mussels | code 1.0: `usda:2706350` ~ `usda:174216` |
| `usda:174260` | `usda:174260` Peanuts, all types, cooked, boiled, with salt<br>`usda:2707513` Peanuts, boiled | code 1.0: `usda:2707513` ~ `usda:174260` |
| `usda:174262` | `usda:174262` Peanuts, all types, dry-roasted, with salt<br>`usda:2707512` Peanuts, NFS<br>`usda:2707517` Peanuts, dry roasted, salted | code 1.0: `usda:2707512` ~ `usda:174262`<br>code 1.0: `usda:2707517` ~ `usda:174262` |
| `usda:2262072` | `usda:174266` Peanut butter, smooth style, with salt (Includes foods for USDA's Food Distribution Program)<br>`usda:174294` Peanut Butter, smooth (Includes foods for USDA's Food Distribution Program)<br>`usda:2262072` Peanut butter, creamy<br>`usda:2707537` Peanut butter<br>`usda:2758989` Peanut butter, Creamy | code 1.0: `usda:2262072` ~ `usda:174266`<br>code 1.0: `usda:2707537` ~ `usda:174266`<br>code 1.0: `usda:2758989` ~ `usda:174294`<br>same 1.0: `usda:2262072` ~ `usda:2758989` |
| `usda:174269` | `usda:174269` Sausage, meatless<br>`usda:2707467` Breakfast link, pattie, or slice, meatless | code 1.0: `usda:2707467` ~ `usda:174269` |
| `usda:174277` | `usda:174277` Soy sauce made from soy and wheat (shoyu)<br>`usda:2707442` Soy sauce | code 1.0: `usda:2707442` ~ `usda:174277` |
| `usda:174287` | `usda:174287` Veggie burgers or soyburgers, unprepared<br>`usda:2707473` Veggie burger patty, no bun | code 1.0: `usda:2707473` ~ `usda:174287` |
| `usda:321358` | `usda:174289` Hummus, commercial<br>`usda:2707402` Hummus, plain<br>`usda:321358` Hummus, commercial | code 1.0: `usda:321358` ~ `usda:174289`<br>code 1.0: `usda:2707402` ~ `usda:174289` |
| `usda:2758985` | `usda:174296` Refried beans, canned, vegetarian<br>`usda:2758985` Refried beans, canned, vegetarian | code 1.0: `usda:2758985` ~ `usda:174296` |
| `usda:174298` | `usda:174298` Refried beans, canned, traditional, reduced sodium<br>`usda:2707399` Refried beans, from canned, reduced sodium | code 1.0: `usda:2707399` ~ `usda:174298` |
| `usda:2727570` | `usda:174370` Lamb, ground, raw<br>`usda:2727570` Lamb, ground, raw | code 1.0: `usda:2727570` ~ `usda:174370` |
| `usda:746777` | `usda:174524` Sauce, salsa, ready-to-serve<br>`usda:2709738` Salsa, red<br>`usda:2709739` Salsa, red, homemade<br>`usda:746777` Sauce, salsa, ready-to-serve | code 1.0: `usda:746777` ~ `usda:174524`<br>code 1.0: `usda:2709738` ~ `usda:174524`<br>code 1.0: `usda:2709739` ~ `usda:174524` |
| `usda:174528` | `usda:174528` Sauce, ready-to-serve, pepper, TABASCO<br>`usda:2710093` Hot pepper sauce | code 1.0: `usda:2710093` ~ `usda:174528` |
| `usda:174529` | `usda:174529` Sauce, oyster, ready-to-serve<br>`usda:2707150` Oyster sauce | code 1.0: `usda:2707150` ~ `usda:174529` |
| `usda:174531` | `usda:174531` Sauce, fish, ready-to-serve<br>`usda:2706457` Fish sauce | code 1.0: `usda:2706457` ~ `usda:174531` |
| `usda:2759003` | `usda:174570` Roast beef, deli style, prepackaged, sliced<br>`usda:2706184` Pastrami, made from any kind of meat, reduced fat<br>`usda:2706218` Beef, prepackaged or deli, luncheon meat<br>`usda:2759003` Lunchmeat, roast beef, sliced, prepackaged | code 1.0: `usda:2759003` ~ `usda:174570`<br>code 1.0: `usda:2706184` ~ `usda:174570`<br>code 1.0: `usda:2706218` ~ `usda:174570` |
| `usda:2759006` | `usda:174575` Pepperoni, beef and pork, sliced<br>`usda:2706185` Pepperoni, NFS<br>`usda:2759006` Pepperoni, beef and pork, sliced | code 1.0: `usda:2759006` ~ `usda:174575`<br>code 1.0: `usda:2706185` ~ `usda:174575` |
| `usda:174576` | `usda:174576` Pickle and pimiento loaf, pork<br>`usda:2706214` Luncheon meat, loaf type | code 1.0: `usda:2706214` ~ `usda:174576` |
| `usda:174581` | `usda:174581` Poultry salad sandwich spread<br>`usda:2706221` Chicken salad spread | code 1.0: `usda:2706221` ~ `usda:174581` |
| `usda:174583` | `usda:174583` Sandwich spread, pork, beef<br>`usda:2706220` Meat spread or potted meat, NFS | code 1.0: `usda:2706220` ~ `usda:174583` |
| `usda:746780` | `usda:174586` Sausage, Italian, pork, mild, cooked, pan-fried<br>`usda:2706189` Italian sausage<br>`usda:746780` Sausage, Italian, pork, mild, cooked, pan-fried | code 1.0: `usda:746780` ~ `usda:174586`<br>code 1.0: `usda:2706189` ~ `usda:174586` |
| `usda:746783` | `usda:174600` Sausage, turkey, breakfast links, mild, raw<br>`usda:2706200` Turkey or chicken sausage<br>`usda:746783` Sausage, turkey, breakfast links, mild, raw | code 1.0: `usda:746783` ~ `usda:174600`<br>code 1.0: `usda:2706200` ~ `usda:174600` |
| `usda:746779` | `usda:174616` Sausage, breakfast sausage, beef, pre-cooked, unprepared<br>`usda:2706171` Beef sausage<br>`usda:746779` Sausage, breakfast sausage, beef, pre-cooked, unprepared | code 1.0: `usda:746779` ~ `usda:174616`<br>code 1.0: `usda:2706171` ~ `usda:174616` |
| `usda:174650` | `usda:174650` Milk and cereal bar<br>`usda:2708086` Milk 'n Cereal bar | code 1.0: `usda:2708086` ~ `usda:174650` |
| `usda:2758977` | `usda:174673` Grapefruit, raw, pink and red, all areas<br>`usda:2709165` Grapefruit, raw<br>`usda:2758977` Grapefruit, raw | code 1.0: `usda:2709165` ~ `usda:174673`<br>same 1.0: `usda:2709165` ~ `usda:2758977` |
| `usda:325287` | `usda:174678` Grapefruit juice, white, canned or bottled, unsweetened<br>`usda:325287` Grapefruit juice, white, canned or bottled, unsweetened | code 1.0: `usda:325287` ~ `usda:174678` |
| `usda:174784` | `usda:174784` Snacks, FRITOLAY, SUNCHIPS, Multigrain Snack, original flavor<br>`usda:2708290` Multigrain chips (Sun Chips)<br>`usda:2708293` Cracker chips | code 1.0: `usda:2708290` ~ `usda:174784`<br>code 1.0: `usda:2708293` ~ `usda:174784` |
| `usda:174786` | `usda:174786` Formulated bar, MARS SNACKFOOD US, SNICKERS MARATHON Protein Performance Bar, Caramel Nut Rush<br>`usda:2708122` Nutrition bar (Snickers Marathon Protein Bar) | code 1.0: `usda:2708122` ~ `usda:174786` |
| `usda:174790` | `usda:174790` Pretzels, soft, unsalted<br>`usda:2708272` Pretzels, soft, ready-to-eat, unsalted, no butter<br>`usda:2708279` Pretzels, soft, from frozen, unsalted | code 1.0: `usda:2708272` ~ `usda:174790`<br>code 1.0: `usda:2708279` ~ `usda:174790` |
| `usda:174792` | `usda:174792` Formulated bar, ZONE PERFECT CLASSIC CRUNCH BAR, mixed flavors<br>`usda:2708126` Nutrition bar (Zone Perfect Classic Crunch) | code 1.0: `usda:2708126` ~ `usda:174792` |
| `usda:174793` | `usda:174793` Snacks, granola bar, KASHI GOLEAN, chewy, mixed flavors<br>`usda:2708088` Cereal or granola bar (Kashi Chewy) | code 1.0: `usda:2708088` ~ `usda:174793` |
| `usda:174794` | `usda:174794` Snacks, granola bar, KASHI TLC Bar, chewy, mixed flavors<br>`usda:2708089` Cereal or granola bar (Kashi Crunchy) | code 1.0: `usda:2708089` ~ `usda:174794` |
| `usda:174795` | `usda:174795` Snacks, granola bars, QUAKER OATMEAL TO GO, all flavors<br>`usda:2708100` Snack bar, oatmeal | code 1.0: `usda:2708100` ~ `usda:174795` |
| `usda:174799` | `usda:174799` Snacks, CLIF BAR, mixed flavors<br>`usda:2708118` Nutrition bar (Clif Bar) | code 1.0: `usda:2708118` ~ `usda:174799` |
| `usda:174800` | `usda:174800` Snacks, granola bar, QUAKER, chewy, 90 Calorie Bar<br>`usda:2708096` Cereal or granola bar (Quaker Chewy 90 Calorie Granola Bar)<br>`usda:2708102` Cereal or granola bar, lowfat, NFS | code 1.0: `usda:2708096` ~ `usda:174800`<br>code 1.0: `usda:2708102` ~ `usda:174800` |
| `usda:174801` | `usda:174801` Snacks, granola bar, GENERAL MILLS NATURE VALLEY, SWEET&SALTY NUT, peanut<br>`usda:2708093` Cereal or granola bar (General Mills Nature Valley Sweet and Salty Granola Bar) | code 1.0: `usda:2708093` ~ `usda:174801` |
| `usda:174802` | `usda:174802` Snacks, granola bar, GENERAL MILLS, NATURE VALLEY, with yogurt coating<br>`usda:2708092` Cereal or granola bar, with yogurt coating (General Mills Nature Valley Chewy Granola Bar) | code 1.0: `usda:2708092` ~ `usda:174802` |
| `usda:174804` | `usda:174804` Snacks, potato chips, made from dried potatoes (preformed), multigrain<br>`usda:2708214` Potato chips, restructured, multigrain | code 1.0: `usda:2708214` ~ `usda:174804` |
| `usda:174806` | `usda:174806` Snacks, Pretzels, gluten- free made with cornstarch and potato flour<br>`usda:2708254` Pretzels, hard, plain, gluten free | code 1.0: `usda:2708254` ~ `usda:174806` |
| `usda:174807` | `usda:174807` Soup, egg drop, Chinese restaurant<br>`usda:2707282` Soup, egg drop | code 1.0: `usda:2707282` ~ `usda:174807` |
| `usda:174808` | `usda:174808` Soup, hot and sour, Chinese restaurant<br>`usda:2707136` Soup, hot and sour | code 1.0: `usda:2707136` ~ `usda:174808` |
| `usda:174809` | `usda:174809` Beverages, THE COCA-COLA COMPANY, NOS Zero, energy drink, sugar-free with guarana, fortified with vitamins B6 and B12<br>`usda:2710761` Energy drink, sugar-free (NOS) | code 1.0: `usda:2710761` ~ `usda:174809` |
| `usda:174811` | `usda:174811` Beverages, Whiskey sour mix, bottled<br>`usda:2710575` Margarita mix, nonalcoholic | code 1.0: `usda:2710575` ~ `usda:174811` |
| `usda:174813` | `usda:174813` Beverages, ABBOTT, EAS soy protein powder<br>`usda:2710732` Nutritional powder mix (EAS Soy Protein Powder) | code 1.0: `usda:2710732` ~ `usda:174813` |
| `usda:174814` | `usda:174814` Beverages, CYTOSPORT, Muscle Milk, ready-to-drink<br>`usda:2710720` Nutritional drink or shake, ready-to-drink (Muscle Milk) | code 1.0: `usda:2710720` ~ `usda:174814` |
| `usda:174816` | `usda:174816` Beverages, OCEAN SPRAY, Cran-Energy, Cranberry Energy Juice Drink<br>`usda:2710762` Energy drink (Ocean Spray Cran-Energy Juice Drink) | code 1.0: `usda:2710762` ~ `usda:174816` |
| `usda:174821` | `usda:174821` Beverages, Energy Drink with carbonated water and high fructose corn syrup<br>`usda:2710749` Energy drink (No Fear)<br>`usda:2710750` Energy drink (No Fear Motherload) | code 1.0: `usda:2710749` ~ `usda:174821`<br>code 1.0: `usda:2710750` ~ `usda:174821` |
| `usda:174822` | `usda:174822` Beverages, Energy Drink, sugar free<br>`usda:2710760` Energy drink, sugar free (No Fear) | code 1.0: `usda:2710760` ~ `usda:174822` |
| `usda:174823` | `usda:174823` Beverages, ABBOTT, ENSURE, Nutritional Shake, Ready-to-Drink<br>`usda:2710717` Nutritional drink or shake, ready-to-drink (Ensure)<br>`usda:2710725` Nutritional drink or shake, ready-to-drink, NFS | code 1.0: `usda:2710717` ~ `usda:174823`<br>code 1.0: `usda:2710725` ~ `usda:174823` |
| `usda:174824` | `usda:174824` Beverages, chocolate powder, no sugar added<br>`usda:2705589` Chocolate beverage powder, light, dry mix, not reconstituted | code 1.0: `usda:2705589` ~ `usda:174824` |
| `usda:174828` | `usda:174828` Beverages, yellow green colored citrus soft drink with caffeine<br>`usda:2710553` Soft drink, fruit flavored, caffeine containing | code 1.0: `usda:2710553` ~ `usda:174828` |
| `usda:174831` | `usda:174831` Beverages, Coconut water, ready-to-drink, unsweetened<br>`usda:2707572` Coconut water, unsweetened | code 1.0: `usda:2707572` ~ `usda:174831` |
| `usda:1999631` | `usda:174832` Beverages, almond milk, unsweetened, shelf stable<br>`usda:1999631` Almond milk, unsweetened, plain, shelf stable<br>`usda:2705409` Almond milk, unsweetened | code 1.0: `usda:1999631` ~ `usda:174832`<br>code 1.0: `usda:2705409` ~ `usda:174832` |
| `usda:174837` | `usda:174837` Alcoholic beverage, wine, table, white<br>`usda:2710689` Wine, white | code 1.0: `usda:2710689` ~ `usda:174837` |
| `usda:174842` | `usda:174842` Beverages, carbonated, club soda<br>`usda:2710539` Water, carbonated, plain | code 1.0: `usda:2710539` ~ `usda:174842` |
| `usda:174846` | `usda:174846` Beverages, carbonated, ginger ale<br>`usda:2710555` Soft drink, ginger ale | code 1.0: `usda:2710555` ~ `usda:174846` |
| `usda:174850` | `usda:174850` Beverages, carbonated, low calorie, cola or pepper-type, with aspartame, without caffeine<br>`usda:2710544` Soft drink, cola, decaffeinated, diet<br>`usda:2710548` Soft drink, pepper type, decaffeinated, diet | code 1.0: `usda:2710544` ~ `usda:174850`<br>code 1.0: `usda:2710548` ~ `usda:174850` |
| `usda:174851` | `usda:174851` Beverages, carbonated, cola, without caffeine<br>`usda:2710543` Soft drink, cola, decaffeinated<br>`usda:2710547` Soft drink, pepper type, decaffeinated | code 1.0: `usda:2710543` ~ `usda:174851`<br>code 1.0: `usda:2710547` ~ `usda:174851` |
| `usda:174852` | `usda:174852` Beverages, carbonated, cola, regular<br>`usda:2710536` Soft drink, NFS<br>`usda:2710541` Soft drink, cola<br>`usda:2710545` Soft drink, pepper type<br>`usda:2710561` Soft drink, cola, fruit or vanilla flavored<br>`usda:2710562` Soft drink, cola, chocolate flavored | code 1.0: `usda:2710536` ~ `usda:174852`<br>code 1.0: `usda:2710541` ~ `usda:174852`<br>code 1.0: `usda:2710545` ~ `usda:174852`<br>code 1.0: `usda:2710561` ~ `usda:174852`<br>code 1.0: `usda:2710562` ~ `usda:174852` |
| `usda:174860` | `usda:174860` Beverages, lemonade-flavor drink, powder<br>`usda:2710613` Fruit flavored drink, powdered, not reconstituted<br>`usda:2710615` Sports drink, dry concentrate, not reconstituted | code 1.0: `usda:2710613` ~ `usda:174860`<br>code 1.0: `usda:2710615` ~ `usda:174860` |
| `usda:174863` | `usda:174863` Malt beverage, includes non-alcoholic beer<br>`usda:2710610` Beer, nonalcoholic | code 1.0: `usda:2710610` ~ `usda:174863` |
| `usda:174869` | `usda:174869` Strawberry-flavor beverage mix, powder<br>`usda:2705591` Strawberry beverage powder, dry mix, not reconstituted | code 1.0: `usda:2705591` ~ `usda:174869` |
| `usda:174871` | `usda:174871` Beverages, tea, black, brewed, prepared with tap water, decaffeinated<br>`usda:2710489` Tea, hot, leaf, black, decaffeinated<br>`usda:2710520` Tea, iced, brewed, black, decaffeinated, unsweetened<br>`usda:2710532` Tea, iced, bottled, black, decaffeinated, unsweetened | code 1.0: `usda:2710489` ~ `usda:174871`<br>code 1.0: `usda:2710520` ~ `usda:174871`<br>code 1.0: `usda:2710532` ~ `usda:174871` |
| `usda:174909` | `usda:174909` Bread, cornbread, dry mix, prepared with 2% milk, 80% margarine, and eggs<br>`usda:2707810` Cornbread, prepared from mix | code 1.0: `usda:2707810` ~ `usda:174909` |
| `usda:174913` | `usda:174913` Bread, Italian<br>`usda:2707614` Bread, Italian, Grecian, Armenian<br>`usda:2707615` Bread, Italian, Grecian, Armenian, toasted | code 1.0: `usda:2707614` ~ `usda:174913`<br>code 1.0: `usda:2707615` ~ `usda:174913` |
| `usda:174916` | `usda:174916` Bread, pita, whole-wheat<br>`usda:2707730` Bread, pita, whole wheat<br>`usda:2707731` Bread, pita, wheat or cracked wheat | code 1.0: `usda:2707730` ~ `usda:174916`<br>code 1.0: `usda:2707731` ~ `usda:174916` |
| `usda:174917` | `usda:174917` Bread, protein (includes gluten)<br>`usda:2707641` Bread, high protein, toasted | code 1.0: `usda:2707641` ~ `usda:174917` |
| `usda:174922` | `usda:174922` Bread, reduced-calorie, white<br>`usda:2707635` Bread, reduced calorie and/or high fiber, white or NFS<br>`usda:2707636` Bread, reduced calorie and/or high fiber, white or NFS, toasted | code 1.0: `usda:2707635` ~ `usda:174922`<br>code 1.0: `usda:2707636` ~ `usda:174922` |
| `usda:174929` | `usda:174929` Bread, sticks, plain<br>`usda:2707690` Breadsticks, hard, NFS | code 1.0: `usda:2707690` ~ `usda:174929` |
| `usda:174939` | `usda:174939` Cake, fruitcake, commercially prepared<br>`usda:2707875` Cake, fruit cake | code 1.0: `usda:2707875` ~ `usda:174939` |
| `usda:174942` | `usda:174942` Cake, snack cakes, creme-filled, chocolate with frosting<br>`usda:2707873` Snack cake, chocolate | code 1.0: `usda:2707873` ~ `usda:174942` |
| `usda:174943` | `usda:174943` Cake, snack cakes, creme-filled, sponge<br>`usda:2707874` Snack cake, white | code 1.0: `usda:2707874` ~ `usda:174943` |
| `usda:174956` | `usda:174956` Cookies, gingersnaps<br>`usda:2707932` Cookie, gingersnaps | code 1.0: `usda:2707932` ~ `usda:174956` |
| `usda:174957` | `usda:174957` Cookies, graham crackers, plain or honey (includes cinnamon)<br>`usda:2708133` Graham crackers<br>`usda:2708134` Graham crackers (Teddy Grahams) | code 1.0: `usda:2708133` ~ `usda:174957`<br>code 1.0: `usda:2708134` ~ `usda:174957` |
| `usda:174958` | `usda:174958` Cookies, graham crackers, chocolate-coated<br>`usda:2708135` Graham crackers, chocolate covered | code 1.0: `usda:2708135` ~ `usda:174958` |
| `usda:174959` | `usda:174959` Cookies, ladyfingers, with lemon juice and rind<br>`usda:2707934` Cookie, ladyfinger | code 1.0: `usda:2707934` ~ `usda:174959` |
| `usda:174965` | `usda:174965` Cookies, peanut butter sandwich, regular<br>`usda:2707955` Cookie, peanut butter sandwich | code 1.0: `usda:2707955` ~ `usda:174965` |
| `usda:174966` | `usda:174966` Cookies, raisin, soft-type<br>`usda:2707960` Cookie, raisin | code 1.0: `usda:2707960` ~ `usda:174966` |
| `usda:174967` | `usda:174967` Cookies, shortbread, commercially prepared, plain<br>`usda:2707900` Cookie, almond<br>`usda:2707957` Cookie, Pfeffernusse<br>`usda:2707962` Cookie, rum ball, no bake<br>`usda:2707964` Cookie, shortbread | code 1.0: `usda:2707900` ~ `usda:174967`<br>code 1.0: `usda:2707957` ~ `usda:174967`<br>code 1.0: `usda:2707962` ~ `usda:174967`<br>code 1.0: `usda:2707964` ~ `usda:174967` |
| `usda:174970` | `usda:174970` Cookies, sugar wafer, with creme filling, sugar free<br>`usda:2707989` Cookie, sugar wafer, sugar free | code 1.0: `usda:2707989` ~ `usda:174970` |
| `usda:174971` | `usda:174971` Cookies, sugar, commercially prepared, regular (includes vanilla)<br>`usda:2707970` Cookie, butter or sugar | code 1.0: `usda:2707970` ~ `usda:174971` |
| `usda:174973` | `usda:174973` Cookies, vanilla wafers, lower fat<br>`usda:2707982` Cookie, vanilla wafer, reduced fat | code 1.0: `usda:2707982` ~ `usda:174973` |
| `usda:174974` | `usda:174974` Cookies, vanilla wafers, higher fat<br>`usda:2707981` Cookie, vanilla wafer | code 1.0: `usda:2707981` ~ `usda:174974` |
| `usda:174975` | `usda:174975` Crackers, cheese, regular<br>`usda:2708150` Crackers, cheese<br>`usda:2708151` Crackers, cheese (Cheez-It)<br>`usda:2708152` Crackers, cheese (Goldfish) | code 1.0: `usda:2708150` ~ `usda:174975`<br>code 1.0: `usda:2708151` ~ `usda:174975`<br>code 1.0: `usda:2708152` ~ `usda:174975` |
| `usda:174977` | `usda:174977` Crackers, melba toast, plain<br>`usda:2707702` Melba toast | code 1.0: `usda:2707702` ~ `usda:174977` |
| `usda:174980` | `usda:174980` Crackers, milk<br>`usda:2708159` Crackers, milk | code 1.0: `usda:2708159` ~ `usda:174980` |
| `usda:174982` | `usda:174982` Crackers, standard snack-type, regular<br>`usda:2708132` Crackers, NFS<br>`usda:2708146` Crackers, butter, plain<br>`usda:2708147` Crackers, butter, flavored<br>`usda:2708148` Crackers, butter (Ritz) | code 1.0: `usda:2708132` ~ `usda:174982`<br>code 1.0: `usda:2708146` ~ `usda:174982`<br>code 1.0: `usda:2708147` ~ `usda:174982`<br>code 1.0: `usda:2708148` ~ `usda:174982` |
| `usda:174983` | `usda:174983` Crackers, standard snack-type, sandwich, with cheese filling<br>`usda:2708176` Crackers, sandwich, cheese filled | code 1.0: `usda:2708176` ~ `usda:174983` |
| `usda:174984` | `usda:174984` Crackers, standard snack-type, sandwich, with peanut butter filling<br>`usda:2708171` Crackers, sandwich<br>`usda:2708172` Crackers, sandwich, peanut butter filled | code 1.0: `usda:2708171` ~ `usda:174984`<br>code 1.0: `usda:2708172` ~ `usda:174984` |
| `usda:174985` | `usda:174985` Crackers, wheat, regular<br>`usda:2708136` Crackers, oatmeal | code 1.0: `usda:2708136` ~ `usda:174985` |
| `usda:174986` | `usda:174986` Cream puff shell, prepared from recipe<br>`usda:2708033` Cream puff, no filling or icing | code 1.0: `usda:2708033` ~ `usda:174986` |
| `usda:174989` | `usda:174989` Croissants, cheese<br>`usda:2707679` Croissant, cheese | code 1.0: `usda:2707679` ~ `usda:174989` |
| `usda:174990` | `usda:174990` Doughnuts, cake-type, plain (includes unsugared, old-fashioned)<br>`usda:2708063` Doughnut, cake type, plain | code 1.0: `usda:2708063` ~ `usda:174990` |
| `usda:174994` | `usda:174994` Muffins, English, plain, enriched, with ca prop (includes sourdough)<br>`usda:2707698` Muffin, English | code 1.0: `usda:2707698` ~ `usda:174994` |
| `usda:175000` | `usda:175000` Ice cream cones, cake or wafer-type<br>`usda:2707931` Cookie, cone shell, ice cream type, wafer or cake<br>`usda:2707958` Cookie, Pizzelle | code 1.0: `usda:2707931` ~ `usda:175000`<br>code 1.0: `usda:2707958` ~ `usda:175000` |
| `usda:175002` | `usda:175002` Muffins, corn, commercially prepared<br>`usda:2707813` Cornbread muffin, stick, round | code 1.0: `usda:2707813` ~ `usda:175002` |
| `usda:175020` | `usda:175020` Pie, peach<br>`usda:2708002` Pie, peach | same 1.0: `usda:175020` ~ `usda:2708002` |
| `usda:175025` | `usda:175025` Pie crust, standard-type, frozen, ready-to-bake, enriched, baked<br>`usda:2708017` Pie shell | code 1.0: `usda:2708017` ~ `usda:175025` |
| `usda:175030` | `usda:175030` Rolls, dinner, wheat<br>`usda:2707746` Roll, wheat or cracked wheat<br>`usda:2707749` Roll, whole wheat | code 1.0: `usda:2707746` ~ `usda:175030`<br>code 1.0: `usda:2707749` ~ `usda:175030` |
| `usda:175031` | `usda:175031` Rolls, hard (includes kaiser)<br>`usda:2707596` Roll, hard, NS as to major flour<br>`usda:2707655` Roll, white, hard | code 1.0: `usda:2707596` ~ `usda:175031`<br>code 1.0: `usda:2707655` ~ `usda:175031` |
| `usda:175032` | `usda:175032` Strudel, apple<br>`usda:2708039` Strudel, apple | same 1.0: `usda:175032` ~ `usda:2708039` |
| `usda:175034` | `usda:175034` Sweet rolls, cinnamon, commercially prepared with raisins<br>`usda:2707667` Roll, sweet, cinnamon bun, no frosting<br>`usda:2707670` Pan Dulce, with fruit, no frosting<br>`usda:2707677` Coffee cake, yeast type | code 1.0: `usda:2707667` ~ `usda:175034`<br>code 1.0: `usda:2707670` ~ `usda:175034`<br>code 1.0: `usda:2707677` ~ `usda:175034` |
| `usda:2758997` | `usda:175036` Tortillas, ready-to-bake or -fry, corn<br>`usda:2707823` Tortilla, corn<br>`usda:2758997` Tortilla, corn, shelf stable | code 1.0: `usda:2758997` ~ `usda:175036`<br>code 1.0: `usda:2707823` ~ `usda:175036` |
| `usda:175037` | `usda:175037` Tortillas, ready-to-bake or -fry, flour, refrigerated<br>`usda:2707824` Tortilla, flour | code 1.0: `usda:2707824` ~ `usda:175037` |
| `usda:175043` | `usda:175043` Leavening agents, yeast, baker's, active dry<br>`usda:2710005` Yeast | code 1.0: `usda:2710005` ~ `usda:175043` |
| `usda:175060` | `usda:175060` Crackers, cheese, low sodium<br>`usda:2708154` Crackers, cheese, reduced sodium | code 1.0: `usda:2708154` ~ `usda:175060` |
| `usda:175068` | `usda:175068` Crackers, saltines, fat-free, low-sodium<br>`usda:2708168` Crackers, saltine, reduced fat | code 1.0: `usda:2708168` ~ `usda:175068` |
| `usda:175069` | `usda:175069` Tart, breakfast, low fat<br>`usda:2708078` Breakfast tart, lowfat | code 1.0: `usda:2708078` ~ `usda:175069` |
| `usda:175089` | `usda:175089` Beverages, tea, instant, lemon, sweetened, powder<br>`usda:2710511` Tea, iced, instant, black, pre-sweetened, dry | code 1.0: `usda:2710511` ~ `usda:175089` |
| `usda:175097` | `usda:175097` Alcoholic beverage, liqueur, coffee, 53 proof<br>`usda:2710625` Liqueur, coffee flavored | code 1.0: `usda:2710625` ~ `usda:175097` |
| `usda:175099` | `usda:175099` Beverages, carbonated, low calorie, cola or pepper-type, with aspartame, contains caffeine<br>`usda:2710537` Soft drink, NFS, diet<br>`usda:2710542` Soft drink, cola, diet<br>`usda:2710546` Soft drink, pepper type, diet<br>`usda:2710560` Soft drink, chocolate flavored, diet<br>`usda:2710563` Soft drink, cola, fruit or vanilla flavored, diet<br>`usda:2710564` Soft drink, cola, chocolate flavored, diet | code 1.0: `usda:2710537` ~ `usda:175099`<br>code 1.0: `usda:2710542` ~ `usda:175099`<br>code 1.0: `usda:2710546` ~ `usda:175099`<br>code 1.0: `usda:2710560` ~ `usda:175099`<br>code 1.0: `usda:2710563` ~ `usda:175099`<br>code 1.0: `usda:2710564` ~ `usda:175099` |
| `usda:175105` | `usda:175105` Beverages, orange breakfast drink, ready-to-drink, with added nutrients<br>`usda:2710601` Fruit juice drink, added calcium (Sunny D) | code 1.0: `usda:2710601` ~ `usda:175105` |
| `usda:175108` | `usda:175108` Beverages, COCA-COLA, POWERADE, lemon-lime flavored, ready-to-drink<br>`usda:2710770` Sports drink (Powerade) | code 1.0: `usda:2710770` ~ `usda:175108` |
| `usda:175118` | `usda:175118` Fish, herring, Atlantic, pickled<br>`usda:2706262` Fish, pickled | code 1.0: `usda:2706262` ~ `usda:175118` |
| `usda:175121` | `usda:175121` Fish, mackerel, jack, canned, drained solids<br>`usda:2706229` Fish, canned<br>`usda:2706268` Fish, mackerel, canned | code 1.0: `usda:2706229` ~ `usda:175121`<br>code 1.0: `usda:2706268` ~ `usda:175121` |
| `usda:333476` | `usda:175130` Fish, pollock, Alaska, raw (may contain additives to retain moisture)<br>`usda:333476` Fish, pollock, raw | code 1.0: `usda:333476` ~ `usda:175130` |
| `usda:175139` | `usda:175139` Fish, sardine, Atlantic, canned in oil, drained solids with bone<br>`usda:2706293` Fish, sardines, canned | code 1.0: `usda:2706293` ~ `usda:175139` |
| `usda:175159` | `usda:175159` Fish, tuna, fresh, yellowfin, raw<br>`usda:2706308` Fish, tuna, raw | code 1.0: `usda:2706308` ~ `usda:175159` |
| `usda:2684445` | `usda:175165` Fish, catfish, channel, farmed, raw<br>`usda:2684445` Fish, catfish, farm raised, raw | code 1.0: `usda:2684445` ~ `usda:175165` |
| `usda:2684441` | `usda:175167` Fish, salmon, Atlantic, farmed, raw<br>`usda:2684441` Fish, salmon, Atlantic, farm raised, raw | code 1.0: `usda:2684441` ~ `usda:175167` |
| `usda:2758983` | `usda:175182` Beans, baked, canned, plain or vegetarian<br>`usda:2707391` Baked beans, vegetarian<br>`usda:2758983` Beans, baked, canned, vegetarian | code 1.0: `usda:2758983` ~ `usda:175182`<br>code 1.0: `usda:2707391` ~ `usda:175182` |
| `usda:2758982` | `usda:175185` Beans, baked, canned, with pork<br>`usda:2758982` Baked beans, Original, canned, with pork | code 1.0: `usda:2758982` ~ `usda:175185` |
| `usda:1999630` | `usda:175215` Soymilk (all flavors), unsweetened, with added calcium, vitamins A and D<br>`usda:1999630` Soy milk, unsweetened, plain, shelf stable<br>`usda:2705405` Soy milk, unsweetened | code 1.0: `usda:1999630` ~ `usda:175215`<br>code 1.0: `usda:2705405` ~ `usda:175215` |
| `usda:175258` | `usda:175258` Peanuts, all types, oil-roasted, without salt<br>`usda:2707516` Peanuts, roasted, unsalted | code 1.0: `usda:2707516` ~ `usda:175258` |
| `usda:2705929` | `usda:2705929` Chicken, NS as to part and cooking method, NS as to skin eaten<br>`usda:2705930` Chicken, NS as to part and cooking method, skin eaten | same 1.0: `usda:2705929` ~ `usda:2705930` |
| `usda:2705932` | `usda:2705932` Chicken, NS as to part, baked, broiled, or roasted, NS as to skin eaten<br>`usda:2705933` Chicken, NS as to part, baked, broiled, or roasted, skin eaten | same 1.0: `usda:2705932` ~ `usda:2705933` |
| `usda:2705935` | `usda:2705935` Chicken, NS as to part, rotisserie, NS as to skin eaten<br>`usda:2705936` Chicken, NS as to part, rotisserie, skin eaten | same 1.0: `usda:2705935` ~ `usda:2705936` |
| `usda:2705938` | `usda:2705938` Chicken, NS as to part, stewed, NS as to skin eaten<br>`usda:2705939` Chicken, NS as to part, stewed, skin eaten | same 1.0: `usda:2705938` ~ `usda:2705939` |
| `usda:2705941` | `usda:2705941` Chicken, NS as to part, grilled without sauce, NS as to skin eaten<br>`usda:2705942` Chicken, NS as to part, grilled without sauce, skin eaten | same 1.0: `usda:2705941` ~ `usda:2705942` |
| `usda:2705944` | `usda:2705944` Chicken, NS as to part, grilled with sauce, NS as to skin eaten<br>`usda:2705945` Chicken, NS as to part, grilled with sauce, skin eaten | same 1.0: `usda:2705944` ~ `usda:2705945` |
| `usda:2707155` | `usda:2707155` Egg, whole, fried, NS as to fat<br>`usda:2707162` Egg, whole, fried, NS as to fat type | unsure 0.8: `usda:2707155` ~ `usda:2707162` |
| `usda:2707198` | `usda:2707198` Egg omelet or scrambled egg, NS as to fat<br>`usda:2707204` Egg omelet or scrambled egg, NS as to fat type | unsure 0.8: `usda:2707198` ~ `usda:2707204` |
| `usda:2707202` | `usda:2707202` Egg omelet or scrambled egg, made with animal fat or meat drippings<br>`usda:2707217` Egg omelet or scrambled egg, with meat, made with animal fat or meat drippings | unsure 1.0: `usda:2707202` ~ `usda:2707217` |
| `usda:2707210` | `usda:2707210` Egg omelet or scrambled egg, with cheese, made with animal fat or meat drippings<br>`usda:2707225` Egg omelet or scrambled egg, with cheese and meat, made with animal fat or meat drippings | unsure 1.0: `usda:2707210` ~ `usda:2707225` |
| `usda:2707213` | `usda:2707213` Egg omelet or scrambled egg, with meat, NS as to fat<br>`usda:2707219` Egg omelet or scrambled egg, with meat, NS as to fat type | unsure 0.83: `usda:2707213` ~ `usda:2707219` |
| `usda:2707221` | `usda:2707221` Egg omelet or scrambled egg, with cheese and meat, NS as to fat<br>`usda:2707227` Egg omelet or scrambled egg, with cheese and meat, NS as to fat type | unsure 0.86: `usda:2707221` ~ `usda:2707227` |
| `usda:2707283` | `usda:2707283` Egg white omelet, scrambled, or fried, NS as to fat<br>`usda:2707288` Egg white omelet, scrambled, or fried, NS as to fat type | unsure 0.86: `usda:2707283` ~ `usda:2707288` |
| `usda:2707864` | `usda:2707864` Cake or cupcake, chocolate with white icing, bakery<br>`usda:2707893` Cake or cupcake, white with chocolate icing, bakery | same 1.0: `usda:2707864` ~ `usda:2707893` |
| `usda:2707865` | `usda:2707865` Cake or cupcake, chocolate with white icing, from mix<br>`usda:2707894` Cake or cupcake, white with chocolate icing, from mix | same 1.0: `usda:2707865` ~ `usda:2707894` |
| `usda:2708223` | `usda:2708223` Popcorn, microwave, NFS<br>`usda:2708224` Popcorn, microwave, plain | unsure 0.67: `usda:2708223` ~ `usda:2708224` |
| `usda:2708294` | `usda:2708294` Pancakes, NFS<br>`usda:2708304` Pancakes, plain | unsure 0.5: `usda:2708294` ~ `usda:2708304` |
| `usda:2708341` | `usda:2708341` Crepe, NFS<br>`usda:2708342` Crepe, plain | unsure 0.5: `usda:2708341` ~ `usda:2708342` |
