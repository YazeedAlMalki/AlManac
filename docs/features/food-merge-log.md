# Food merge log

Written by `python3 -m almanac_nutrition merge`; do not edit by hand. Bundle: `almanac.sqlite` sha256 `0877c2914543`.

Rule (owner, 2026-10-19): one record per real food across every source. Foods are matched on USDA's own codes (**code**: a Foundation and an SR Legacy food with one NDB number, an FNDDS food whose only ingredient is an SR Legacy food), on equal normalised English names (**same**), or on names that differ only by words naming nothing about the food (*all*, *average*, *commercial*, *fresh*, *generic*, *mean*, *plain*, *regular*, *standard*, *type*, *typical*, *variety*) and whose nutrient profiles agree (**unsure**; energy within 25 kcal or 12 %, protein, fat and carbohydrate within 1.5–2 g or 15 %, per 100 g). Every member keeps its own rows and licence; the search shows the record (USDA first, then CoFID, CIQUAL, AFCD). Almanac's own dishes are never merged.

| | Count |
|---|---:|
| foods read (almanac: excluded) | 8354 |
| records with more than one source row | 193 |
| foods merged into another food's record | 228 |
| matches: code | 0 |
| matches: same name | 209 |
| matches: unsure | 19 |
| records with a conflict | 63 |

## Conflicts

Members whose values differ by more than the tolerance. Both values are kept, each on its own source's row; nothing is picked. Carbohydrate is compared as a total (by difference, or available plus fibre) and is not a stored value.

| Record | Nutrient | Values per 100 g |
|---|---|---|
| `cofid:14-031` Apricots, dried | energy_kcal | 232.314 (`afcd:F000130`); 188 (`cofid:14-031`) |
| `cofid:13-153` Artichoke, globe, raw | energy_kcal | 34.6558 (`afcd:F000144`); 45.4 (`ciqual:20052`); 18 (`cofid:13-153`) |
| `cofid:18-064` Beef, sirloin steak, raw, lean | fat_total | 1.9 (`afcd:F000810`); 4.5 (`cofid:18-064`) |
| `usda:2727581` Blackberries, raw | carbohydrate | 11.9 (`afcd:F001267`); 11.73 (`ciqual:13029`); 8.733 (`cofid:14-388`) |
| `cofid:12-345` Cheese, Camembert | fat_total | 27.9 (`afcd:F002408`); 22.7 (`cofid:12-345`) |
| `cofid:18-411` Liver, chicken, raw | fat_total | 4.8 (`afcd:F002709`); 4.83 (`ciqual:40111`); 2.3 (`cofid:18-411`) |
| `cofid:12-545` Cocoa powder | protein | 22.1 (`afcd:F002980`); 18.5 (`cofid:12-545`) |
| `cofid:12-545` Cocoa powder | fat_total | 15.2 (`afcd:F002980`); 21.7 (`cofid:12-545`) |
| `ciqual:13113` Cranberry, raw | carbohydrate | 7.9 (`afcd:F003249`); 13.25 (`ciqual:13113`) |
| `cofid:13-876` Curry powder | energy_kcal | 294.216 (`afcd:F003337`); 233 (`cofid:13-876`) |
| `cofid:13-876` Curry powder | protein | 14.3 (`afcd:F003337`); 9.5 (`cofid:13-876`) |
| `cofid:13-876` Curry powder | fat_total | 14 (`afcd:F003337`); 10.8 (`cofid:13-876`) |
| `cofid:12-943` Eggs, chicken, whole, poached | fat_total | 8.8 (`afcd:F003725`); 10.6 (`cofid:12-943`) |
| `usda:2512375` Flour, rye | protein | 11.4 (`afcd:F004000`); 7.3 (`cofid:11-897`); 8.3952 (`usda:2512375`) |
| `cofid:17-050` Honey | energy_kcal | 277.725 (`afcd:F004380`); 331 (`ciqual:31008`); 288 (`cofid:17-050`) |
| `cofid:18-481` Lamb, mince, raw | energy_kcal | 143.881 (`afcd:F005049`); 196 (`cofid:18-481`) |
| `cofid:18-481` Lamb, mince, raw | fat_total | 6.9 (`afcd:F005049`); 13.3 (`cofid:18-481`) |
| `ciqual:26051` Mackerel, raw | energy_kcal | 134.082 (`afcd:F005268`); 198 (`ciqual:26051`) |
| `ciqual:26051` Mackerel, raw | fat_total | 6.3 (`afcd:F005268`); 13.5 (`ciqual:26051`) |
| `cofid:17-362` Mustard powder | energy_kcal | 547.084 (`afcd:F005972`); 452 (`cofid:17-362`) |
| `cofid:17-362` Mustard powder | fat_total | 39.5 (`afcd:F005972`); 28.7 (`cofid:17-362`) |
| `cofid:16-259` Octopus, raw | protein | 14.9 (`afcd:F006150`); 17.9 (`cofid:16-259`) |
| `usda:2346410` Raspberries, raw | energy_kcal | 48.0402 (`afcd:F007619`); 47.9 (`ciqual:13015`); 25 (`cofid:14-375`); 51.4124 (`usda:2346410`) |
| `usda:2346410` Raspberries, raw | carbohydrate | 11.8 (`afcd:F007619`); 10.13 (`ciqual:13015`); 8.557 (`cofid:14-375`); 12.904 (`usda:2346410`) |
| `cofid:13-882` Rosemary, dried | carbohydrate | 63 (`afcd:F007715`); 64.1 (`ciqual:11036`); 86.79 (`cofid:13-882`) |
| `cofid:16-418` Salmon, red, canned in brine, drained | fat_total | 5.5 (`afcd:F007860`); 7.3 (`cofid:16-418`) |
| `cofid:19-656` Sausages, beef, raw | carbohydrate | 2.9 (`afcd:F008112`); 9.5 (`cofid:19-656`) |
| `cofid:11-958` Scones, plain, homemade | fat_total | 9.5 (`afcd:F008174`); 12.7 (`cofid:11-958`) |
| `ciqual:15047` Chia, seed, dried | protein | 23.8 (`afcd:F008209`); 16.5 (`ciqual:15047`) |
| `ciqual:11061` Poppy, seed | protein | 18 (`afcd:F008211`); 21.2 (`ciqual:11061`) |
| `ciqual:11061` Poppy, seed | carbohydrate | 28.1 (`afcd:F008211`); 23.7 (`ciqual:11061`) |
| `ciqual:15011` Sunflower, seed | energy_kcal | 564.532 (`afcd:F008215`); 653 (`ciqual:15011`) |
| `usda:2346409` Strawberries, raw | carbohydrate | 7.7 (`afcd:F008952`); 9.83 (`ciqual:13014`); 9.61 (`cofid:14-324`); 7.964 (`usda:2346409`) |
| `cofid:14-263` Sultanas | energy_kcal | 312.62 (`afcd:F008983`); 275 (`cofid:14-263`) |
| `cofid:13-883` Thyme, dried, ground | carbohydrate | 63.9 (`afcd:F009160`); 80.143 (`cofid:13-883`) |
| `cofid:13-519` Tomatoes, cherry, raw | carbohydrate | 5.2 (`afcd:F009190`); 6.82 (`ciqual:20172`); 4.729 (`cofid:13-519`) |
| `cofid:16-416` Tuna, canned in brine, drained | energy_kcal | 129.063 (`afcd:F009285`); 143 (`ciqual:26039`); 109 (`cofid:16-416`) |
| `cofid:16-416` Tuna, canned in brine, drained | fat_total | 2.6 (`afcd:F009285`); 3.94 (`ciqual:26039`); 1 (`cofid:16-416`) |
| `cofid:13-669@row2827` Watercress, raw | carbohydrate | 4.6 (`afcd:F009532`); 1.61 (`ciqual:20022`) |
| `ciqual:9660` Wheat germ | energy_kcal | 307.122 (`afcd:F009536`); 375 (`ciqual:9660`) |
| `ciqual:9660` Wheat germ | protein | 20.6 (`afcd:F009536`); 27.2 (`ciqual:9660`) |
| `ciqual:9660` Wheat germ | fat_total | 6.1 (`afcd:F009536`); 9.5 (`ciqual:9660`) |
| `cofid:16-260` Oysters, raw | protein | 8.64 (`ciqual:10011`); 10.8 (`cofid:16-260`) |
| `cofid:13-811` Chervil, dried | energy_kcal | 302 (`ciqual:10999`); 237 (`cofid:13-811`) |
| `usda:1104647` Garlic, raw | energy_kcal | 109 (`ciqual:11000`); 98 (`cofid:13-244`); 143 (`usda:1104647`) |
| `usda:1104647` Garlic, raw | protein | 5.31 (`ciqual:11000`); 7.9 (`cofid:13-244`); 6.62 (`usda:1104647`) |
| `cofid:13-845` Parsley, dried | energy_kcal | 291 (`ciqual:11024`); 181 (`cofid:13-845`) |
| `cofid:13-845` Parsley, dried | protein | 29 (`ciqual:11024`); 15.8 (`cofid:13-845`) |
| `cofid:13-845` Parsley, dried | fat_total | 5.34 (`ciqual:11024`); 7 (`cofid:13-845`) |
| `cofid:13-837` Mint, dried | protein | 19.9 (`ciqual:11029`); 24.8 (`cofid:13-837`) |
| `cofid:13-825` Dill, dried | energy_kcal | 315 (`ciqual:11063`); 253 (`cofid:13-825`) |
| `cofid:13-892` Rosemary, fresh | protein | 3.31 (`ciqual:11068`); 1.4 (`cofid:13-892`) |
| `cofid:13-892` Rosemary, fresh | carbohydrate | 20.7 (`ciqual:11068`); 25.257 (`cofid:13-892`) |
| `cofid:13-853` Sage, fresh | energy_kcal | 34.9 (`ciqual:11069`); 119 (`cofid:13-853`) |
| `cofid:13-853` Sage, fresh | fat_total | 0.5 (`ciqual:11069`); 4.6 (`cofid:13-853`) |
| `cofid:13-893` Thyme, fresh | protein | 5.56 (`ciqual:11070`); 3 (`cofid:13-893`) |
| `ciqual:13161` Dairy and cereal-based beverage for baby's dinner, with vegetables, from 4/6 months | fat_total | 2.83 (`ciqual:13161`); 8.93 (`ciqual:13172`) |
| `ciqual:13161` Dairy and cereal-based beverage for baby's dinner, with vegetables, from 4/6 months | carbohydrate | 12.5 (`ciqual:13161`); 25.05 (`ciqual:13172`) |
| `cofid:17-158` Coffee, powder, instant | energy_kcal | 291 (`ciqual:18005`); 75 (`cofid:17-158`) |
| `cofid:17-158` Coffee, powder, instant | protein | 18.5 (`ciqual:18005`); 14.6 (`cofid:17-158`) |
| `cofid:17-158` Coffee, powder, instant | carbohydrate | 61.9 (`ciqual:18005`); 4.286 (`cofid:17-158`) |
| `cofid:14-820` Coconut milk | energy_kcal | 199 (`ciqual:18041`); 22 (`cofid:14-820`) |
| `cofid:14-820` Coconut milk | protein | 1.94 (`ciqual:18041`); 0.3 (`cofid:14-820`) |
| `cofid:14-820` Coconut milk | fat_total | 19.2 (`ciqual:18041`); 0.3 (`cofid:14-820`) |
| `cofid:12-555` Yogurt, Greek style, plain | energy_kcal | 103 (`ciqual:19860`); 133 (`cofid:12-555`) |
| `cofid:12-555` Yogurt, Greek style, plain | protein | 3.02 (`ciqual:19860`); 5.7 (`cofid:12-555`) |
| `cofid:12-555` Yogurt, Greek style, plain | fat_total | 8.16 (`ciqual:19860`); 10.2 (`cofid:12-555`) |
| `cofid:13-342` Shallots, raw | energy_kcal | 61.7 (`ciqual:20097`); 20 (`cofid:13-342`) |
| `cofid:13-118` Tempeh | protein | 16.1 (`ciqual:20917`); 20.7 (`cofid:13-118`) |
| `cofid:13-118` Tempeh | fat_total | 4.7 (`ciqual:20917`); 6.4 (`cofid:13-118`) |
| `cofid:12-946` Omelette, plain, homemade | protein | 13.8 (`ciqual:22500`); 10.9 (`cofid:12-946`) |
| `cofid:16-142` Shark, raw | fat_total | 2.91 (`ciqual:26162`); 1.1 (`cofid:16-142`) |
| `ciqual:30150` Merguez sausage, raw | energy_kcal | 301 (`ciqual:30150`); 381 (`ciqual:30151`) |
| `ciqual:30150` Merguez sausage, raw | fat_total | 26.8 (`ciqual:30150`); 36.3 (`ciqual:30151`) |
| `cofid:19-106` Liver sausage | energy_kcal | 374 (`ciqual:30176`); 226 (`cofid:19-106`) |
| `cofid:19-106` Liver sausage | fat_total | 35.9 (`ciqual:30176`); 16.7 (`cofid:19-106`) |
| `cofid:19-517` Salami | protein | 17.7 (`ciqual:30350`); 20.9 (`cofid:19-517`) |
| `usda:2727569` Chicken, breast, meat and skin, raw | energy_kcal | 167 (`ciqual:36029`); 132.836 (`usda:2727569`) |
| `usda:2727569` Chicken, breast, meat and skin, raw | fat_total | 9.25 (`ciqual:36029`); 4.777 (`usda:2727569`) |
| `cofid:18-409` Liver, calf, raw | protein | 15.5 (`ciqual:40106`); 18.3 (`cofid:18-409`) |
| `cofid:18-423` Tongue, lamb, raw | energy_kcal | 167 (`ciqual:40207`); 193 (`cofid:18-423`) |
| `cofid:18-423` Tongue, lamb, raw | fat_total | 10.9 (`ciqual:40207`); 14.6 (`cofid:18-423`) |
| `cofid:18-421` Sweetbread, lamb, raw | fat_total | 9.82 (`ciqual:40302`); 7.8 (`cofid:18-421`) |
| `cofid:18-486` Veal, escalope, raw | fat_total | 3.28 (`ciqual:6521`); 1.7 (`cofid:18-486`) |
| `cofid:11-940` Rusks | protein | 10 (`ciqual:7300`); 6.5 (`cofid:11-940`) |
| `cofid:11-940` Rusks | fat_total | 5.43 (`ciqual:7300`); 10.7 (`cofid:11-940`) |
| `cofid:11-988` Croissants | protein | 6.56 (`ciqual:7603`); 8.3 (`cofid:11-988`) |
| `cofid:14-843` Quinoa, raw | energy_kcal | 358 (`ciqual:9340`); 309 (`cofid:14-843`) |
| `usda:2259793` Yogurt, plain, whole milk | protein | 5.7 (`cofid:12-184`); 3.82417 (`usda:2259793`) |
| `cofid:15-776` Curry, pea and potato, homemade | energy_kcal | 147 (`cofid:15-776`); 92 (`cofid:15-781`) |
| `cofid:15-776` Curry, pea and potato, homemade | fat_total | 11 (`cofid:15-776`); 3.7 (`cofid:15-781`) |
| `cofid:15-776` Curry, pea and potato, homemade | carbohydrate | 12.514 (`cofid:15-776`); 15.481 (`cofid:15-781`) |
| `cofid:16-127` Red snapper, flesh only, fried in blended oil, weighed with bones and skin | energy_kcal | 126 (`cofid:16-127`); 64 (`cofid:16-128`) |
| `cofid:16-127` Red snapper, flesh only, fried in blended oil, weighed with bones and skin | protein | 24.5 (`cofid:16-127`); 12.5 (`cofid:16-128`) |
| `cofid:18-470` Beef, mince, stewed | energy_kcal | 209 (`cofid:18-470`); 139 (`cofid:19-607`) |
| `cofid:18-470` Beef, mince, stewed | protein | 21.8 (`cofid:18-470`); 10.9 (`cofid:19-607`) |
| `cofid:18-470` Beef, mince, stewed | fat_total | 13.5 (`cofid:18-470`); 9.9 (`cofid:19-607`) |
| `cofid:18-470` Beef, mince, stewed | carbohydrate | 0 (`cofid:18-470`); 2.681 (`cofid:19-607`) |

## Merges

| Record | Members | Matches |
|---|---|---|
| `cofid:16-448` | `afcd:F000074` Anchovy, canned in oil, drained<br>`cofid:16-448` Anchovies, canned in oil, drained | same 1.0: `afcd:F000074` ~ `cofid:16-448` |
| `ciqual:13111` | `afcd:F000089` Apple, dried<br>`ciqual:13111` Apple, dried | same 1.0: `afcd:F000089` ~ `ciqual:13111` |
| `cofid:14-031` | `afcd:F000130` Apricot, dried<br>`cofid:14-031` Apricots, dried | same 1.0: `afcd:F000130` ~ `cofid:14-031` |
| `cofid:13-153` | `afcd:F000144` Artichoke, globe, raw<br>`ciqual:20052` Artichoke, globe, raw<br>`cofid:13-153` Artichoke, globe, raw | same 1.0: `afcd:F000144` ~ `ciqual:20052`<br>same 1.0: `afcd:F000144` ~ `cofid:13-153` |
| `usda:2710823` | `afcd:F000155` Asparagus, green, raw<br>`ciqual:20279` Asparagus, green, raw<br>`usda:2710823` Asparagus, green, raw | same 1.0: `afcd:F000155` ~ `ciqual:20279`<br>same 1.0: `afcd:F000155` ~ `usda:2710823` |
| `cofid:13-532` | `afcd:F000243` Baked beans, canned in tomato sauce<br>`cofid:13-532` Baked beans, canned in tomato sauce | same 1.0: `afcd:F000243` ~ `cofid:13-532` |
| `cofid:13-514` | `afcd:F000431` Bean, green, fresh, raw<br>`cofid:13-514` Beans, green, raw | unsure 0.75: `afcd:F000431` ~ `cofid:13-514` |
| `cofid:18-043` | `afcd:F000739` Beef, rump steak, lean, raw<br>`cofid:18-043` Beef, rump steak, raw, lean | same 1.0: `afcd:F000739` ~ `cofid:18-043` |
| `cofid:18-064` | `afcd:F000810` Beef, sirloin steak, lean, raw<br>`cofid:18-064` Beef, sirloin steak, raw, lean | same 1.0: `afcd:F000810` ~ `cofid:18-064` |
| `usda:2727581` | `afcd:F001267` Blackberry, raw<br>`ciqual:13029` Blackberry, raw<br>`cofid:14-388` Blackberries, raw<br>`usda:2727581` Blackberries, raw | same 1.0: `afcd:F001267` ~ `ciqual:13029`<br>same 1.0: `afcd:F001267` ~ `cofid:14-388`<br>same 1.0: `afcd:F001267` ~ `usda:2727581` |
| `usda:2346411` | `afcd:F001290` Blueberry, raw<br>`ciqual:13028` Blueberry, raw<br>`usda:2346411` Blueberries, raw | same 1.0: `afcd:F001290` ~ `ciqual:13028`<br>same 1.0: `afcd:F001290` ~ `usda:2346411` |
| `usda:747447` | `afcd:F001905` Broccoli, fresh, raw<br>`ciqual:20057` Broccoli, raw<br>`usda:747447` Broccoli, raw | unsure 0.67: `afcd:F001905` ~ `ciqual:20057`<br>same 1.0: `ciqual:20057` ~ `usda:747447` |
| `usda:2685575` | `afcd:F001914` Brussels sprout, fresh, raw<br>`ciqual:20058` Brussels sprout, raw<br>`cofid:13-177` Brussels sprouts, raw<br>`usda:2685575` Brussels sprouts, raw | unsure 0.75: `afcd:F001914` ~ `ciqual:20058`<br>same 1.0: `ciqual:20058` ~ `cofid:13-177`<br>same 1.0: `ciqual:20058` ~ `usda:2685575` |
| `cofid:17-685` | `afcd:F001973` Butter, plain, salted<br>`cofid:17-685` Butter, salted | unsure 0.67: `afcd:F001973` ~ `cofid:17-685` |
| `cofid:13-187` | `afcd:F001996` Cabbage, Chinese, raw<br>`cofid:13-187` Cabbage, Chinese, raw | same 1.0: `afcd:F001996` ~ `cofid:13-187` |
| `usda:2346408` | `afcd:F002006` Cabbage, red, raw<br>`cofid:13-190` Cabbage, red, raw<br>`usda:2346408` Cabbage, red, raw | same 1.0: `afcd:F002006` ~ `cofid:13-190`<br>same 1.0: `afcd:F002006` ~ `usda:2346408` |
| `cofid:13-509` | `afcd:F002015` Cabbage, white, raw<br>`cofid:13-509` Cabbage, white, raw | same 1.0: `afcd:F002015` ~ `cofid:13-509` |
| `usda:2685573` | `afcd:F002378` Cauliflower, fresh, raw<br>`ciqual:20016` Cauliflower, raw<br>`cofid:13-512` Cauliflower, raw<br>`usda:2685573` Cauliflower, raw | unsure 0.67: `afcd:F002378` ~ `ciqual:20016`<br>same 1.0: `ciqual:20016` ~ `cofid:13-512`<br>same 1.0: `ciqual:20016` ~ `usda:2685573` |
| `usda:2346405` | `afcd:F002390` Celery, fresh, raw<br>`cofid:13-636` Celery, raw<br>`usda:2346405` Celery, raw | unsure 0.67: `afcd:F002390` ~ `cofid:13-636`<br>same 1.0: `cofid:13-636` ~ `usda:2346405` |
| `cofid:12-345` | `afcd:F002408` Cheese, camembert<br>`cofid:12-345` Cheese, Camembert | same 1.0: `afcd:F002408` ~ `cofid:12-345` |
| `cofid:12-355` | `afcd:F002448` Cheese, edam<br>`cofid:12-355` Cheese, Edam | same 1.0: `afcd:F002448` ~ `cofid:12-355` |
| `cofid:12-176` | `afcd:F002488` Cheese, ricotta<br>`cofid:12-176` Cheese, Ricotta | same 1.0: `afcd:F002488` ~ `cofid:12-176` |
| `cofid:18-411` | `afcd:F002709` Chicken, liver, raw<br>`ciqual:40111` Liver, chicken, raw<br>`cofid:18-411` Liver, chicken, raw | same 1.0: `afcd:F002709` ~ `ciqual:40111`<br>same 1.0: `afcd:F002709` ~ `cofid:18-411` |
| `ciqual:20026` | `afcd:F002884` Chicory, raw<br>`ciqual:20026` Chicory, raw | same 1.0: `afcd:F002884` ~ `ciqual:20026` |
| `cofid:17-648` | `afcd:F002929` Chocolate, milk<br>`cofid:17-648` Chocolate, milk | same 1.0: `afcd:F002929` ~ `cofid:17-648` |
| `cofid:17-091` | `afcd:F002946` Chocolate, white<br>`cofid:17-091` Chocolate, white | same 1.0: `afcd:F002946` ~ `cofid:17-091` |
| `cofid:12-545` | `afcd:F002980` Cocoa powder<br>`cofid:12-545` Cocoa powder | same 1.0: `afcd:F002980` ~ `cofid:12-545` |
| `usda:2758976` | `afcd:F003248` Cranberry, dried, sweetened<br>`usda:2758976` Cranberries, dried, sweetened | same 1.0: `afcd:F003248` ~ `usda:2758976` |
| `ciqual:13113` | `afcd:F003249` Cranberry, raw<br>`ciqual:13113` Cranberry, raw | same 1.0: `afcd:F003249` ~ `ciqual:13113` |
| `cofid:13-876` | `afcd:F003337` Curry powder<br>`cofid:13-876` Curry powder | same 1.0: `afcd:F003337` ~ `cofid:13-876` |
| `cofid:17-487` | `afcd:F003627` Dripping, beef<br>`cofid:17-487` Dripping, beef | same 1.0: `afcd:F003627` ~ `cofid:17-487` |
| `cofid:12-943` | `afcd:F003725` Egg, chicken, whole, poached<br>`cofid:12-943` Eggs, chicken, whole, poached | same 1.0: `afcd:F003725` ~ `cofid:12-943` |
| `cofid:12-937` | `afcd:F003729` Egg, chicken, whole, raw<br>`cofid:12-937` Eggs, chicken, whole, raw | same 1.0: `afcd:F003729` ~ `cofid:12-937` |
| `cofid:12-939` | `afcd:F003737` Egg, chicken, yolk, raw<br>`cofid:12-939` Eggs, chicken, yolk, raw | same 1.0: `afcd:F003737` ~ `cofid:12-939` |
| `cofid:13-240` | `afcd:F003784` Endive, fresh, raw<br>`cofid:13-240` Endive, raw | unsure 0.67: `afcd:F003784` ~ `cofid:13-240` |
| `ciqual:20028` | `afcd:F003820` Fennel, fresh, raw<br>`ciqual:20028` Fennel, raw | unsure 0.67: `afcd:F003820` ~ `ciqual:20028` |
| `ciqual:13013` | `afcd:F003832` Fig, dried<br>`ciqual:13013` Fig, dried | same 1.0: `afcd:F003832` ~ `ciqual:13013` |
| `cofid:11-021` | `afcd:F003998` Flour, rice<br>`cofid:11-021` Flour, rice | same 1.0: `afcd:F003998` ~ `cofid:11-021` |
| `usda:2512375` | `afcd:F004000` Flour, rye<br>`cofid:11-897` Flour, rye<br>`usda:2512375` Flour, rye | same 1.0: `afcd:F004000` ~ `cofid:11-897`<br>same 1.0: `afcd:F004000` ~ `usda:2512375` |
| `cofid:11-888` | `afcd:F004009` Flour, wheat, white, self-raising<br>`cofid:11-888` Flour, wheat, white, self raising | same 1.0: `afcd:F004009` ~ `cofid:11-888` |
| `cofid:11-889` | `afcd:F004014` Flour, wheat, wholemeal, plain<br>`cofid:11-889` Flour, wheat, wholemeal | unsure 0.75: `afcd:F004014` ~ `cofid:11-889` |
| `cofid:11-891` | `afcd:F004015` Flour, wheat, wholemeal, self-raising<br>`cofid:11-891` Flour, wheat, wholemeal, self raising | same 1.0: `afcd:F004015` ~ `cofid:11-891` |
| `cofid:17-360` | `afcd:F004196` Gelatine, all types<br>`cofid:17-360` Gelatine | unsure 0.33: `afcd:F004196` ~ `cofid:17-360` |
| `ciqual:13183` | `afcd:F004244` Goji berry, dried<br>`ciqual:13183` Goji berry, dried | same 1.0: `afcd:F004244` ~ `ciqual:13183` |
| `cofid:17-050` | `afcd:F004380` Honey<br>`ciqual:31008` Honey<br>`cofid:17-050` Honey | same 1.0: `afcd:F004380` ~ `ciqual:31008`<br>same 1.0: `afcd:F004380` ~ `cofid:17-050` |
| `ciqual:31053` | `afcd:F004604` Jam, plum<br>`ciqual:31053` Jam, plum | same 1.0: `afcd:F004604` ~ `ciqual:31053` |
| `cofid:17-688` | `afcd:F004607` Jam, stone fruit<br>`cofid:17-688` Jam, stone fruit | same 1.0: `afcd:F004607` ~ `cofid:17-688` |
| `usda:323505` | `afcd:F004781` Kale, raw<br>`ciqual:20346` Kale, raw<br>`usda:323505` Kale, raw | same 1.0: `afcd:F004781` ~ `ciqual:20346`<br>same 1.0: `afcd:F004781` ~ `usda:323505` |
| `cofid:18-481` | `afcd:F005049` Lamb, mince, raw<br>`cofid:18-481` Lamb, mince, raw | same 1.0: `afcd:F005049` ~ `cofid:18-481` |
| `cofid:13-624` | `afcd:F005164` Leek, fresh, raw<br>`ciqual:20039` Leek, raw<br>`cofid:13-624` Leeks, raw | unsure 0.67: `afcd:F005164` ~ `ciqual:20039`<br>same 1.0: `ciqual:20039` ~ `cofid:13-624` |
| `usda:2346388` | `afcd:F005192` Lettuce, iceberg, raw<br>`usda:2346388` Lettuce, iceberg, raw | same 1.0: `afcd:F005192` ~ `usda:2346388` |
| `ciqual:26051` | `afcd:F005268` Mackerel, raw<br>`ciqual:26051` Mackerel, raw | same 1.0: `afcd:F005268` ~ `ciqual:26051` |
| `cofid:14-087` | `afcd:F005712` Mixed dried fruit<br>`cofid:14-087` Dried mixed fruit | same 1.0: `afcd:F005712` ~ `cofid:14-087` |
| `cofid:17-362` | `afcd:F005972` Mustard powder<br>`cofid:17-362` Mustard powder | same 1.0: `afcd:F005972` ~ `cofid:17-362` |
| `cofid:16-259` | `afcd:F006150` Octopus, raw<br>`cofid:16-259` Octopus, raw | same 1.0: `afcd:F006150` ~ `cofid:16-259` |
| `usda:748278` | `afcd:F006159` Oil, canola<br>`usda:748278` Oil, canola | same 1.0: `afcd:F006159` ~ `usda:748278` |
| `usda:330458` | `afcd:F006163` Oil, coconut<br>`cofid:17-031` Oil, coconut<br>`usda:330458` Oil, coconut | same 1.0: `afcd:F006163` ~ `cofid:17-031`<br>same 1.0: `afcd:F006163` ~ `usda:330458` |
| `cofid:17-034` | `afcd:F006166` Oil, cottonseed<br>`cofid:17-034` Oil, cottonseed | same 1.0: `afcd:F006166` ~ `cofid:17-034` |
| `cofid:17-036` | `afcd:F006167` Oil, grapeseed<br>`cofid:17-036` Oil, grapeseed | same 1.0: `afcd:F006167` ~ `cofid:17-036` |
| `cofid:17-038` | `afcd:F006177` Oil, olive<br>`cofid:17-038` Oil, olive | same 1.0: `afcd:F006177` ~ `cofid:17-038` |
| `cofid:17-039` | `afcd:F006181` Oil, palm<br>`cofid:17-039` Oil, palm | same 1.0: `afcd:F006181` ~ `cofid:17-039` |
| `usda:1750348` | `afcd:F006183` Oil, peanut<br>`usda:1750348` Oil, peanut | same 1.0: `afcd:F006183` ~ `usda:1750348` |
| `usda:1750350` | `afcd:F006186` Oil, safflower<br>`cofid:17-042` Oil, safflower<br>`usda:1750350` Oil, safflower | same 1.0: `afcd:F006186` ~ `cofid:17-042`<br>same 1.0: `afcd:F006186` ~ `usda:1750350` |
| `cofid:17-043` | `afcd:F006187` Oil, sesame<br>`cofid:17-043` Oil, sesame | same 1.0: `afcd:F006187` ~ `cofid:17-043` |
| `usda:748366` | `afcd:F006188` Oil, soybean<br>`usda:748366` Oil, soybean | same 1.0: `afcd:F006188` ~ `usda:748366` |
| `usda:1750349` | `afcd:F006189` Oil, sunflower<br>`cofid:17-045` Oil, sunflower<br>`usda:1750349` Oil, sunflower | same 1.0: `afcd:F006189` ~ `cofid:17-045`<br>same 1.0: `afcd:F006189` ~ `usda:1750349` |
| `cofid:17-686` | `afcd:F006191` Oil, vegetable<br>`cofid:17-686` Oil, vegetable, average | same 1.0: `afcd:F006191` ~ `cofid:17-686` |
| `cofid:13-300` | `afcd:F006195` Okra, raw<br>`ciqual:58100` Okra, raw<br>`cofid:13-300` Okra, raw | same 1.0: `afcd:F006195` ~ `ciqual:58100`<br>same 1.0: `afcd:F006195` ~ `cofid:13-300` |
| `ciqual:11035` | `afcd:F006281` Oregano, dried<br>`ciqual:11035` Oregano, dried | same 1.0: `afcd:F006281` ~ `ciqual:11035` |
| `ciqual:13046` | `afcd:F007610` Raisin<br>`ciqual:13046` Raisin | same 1.0: `afcd:F007610` ~ `ciqual:13046` |
| `usda:2346410` | `afcd:F007619` Raspberry, raw<br>`ciqual:13015` Raspberry, raw<br>`cofid:14-375` Raspberries, raw<br>`usda:2346410` Raspberries, raw | same 1.0: `afcd:F007619` ~ `ciqual:13015`<br>same 1.0: `afcd:F007619` ~ `cofid:14-375`<br>same 1.0: `afcd:F007619` ~ `usda:2346410` |
| `usda:2758975` | `afcd:F007628` Rhubarb, stalk, raw<br>`ciqual:13047` Rhubarb, stalk, raw<br>`usda:2758975` Rhubarb, stalk, raw | same 1.0: `afcd:F007628` ~ `ciqual:13047`<br>same 1.0: `afcd:F007628` ~ `usda:2758975` |
| `cofid:13-522` | `afcd:F007712` Rocket, fresh, raw<br>`cofid:13-522` Rocket, raw | unsure 0.67: `afcd:F007712` ~ `cofid:13-522` |
| `cofid:13-882` | `afcd:F007715` Rosemary, dried<br>`ciqual:11036` Rosemary, dried<br>`cofid:13-882` Rosemary, dried | same 1.0: `afcd:F007715` ~ `ciqual:11036`<br>same 1.0: `afcd:F007715` ~ `cofid:13-882` |
| `ciqual:11037` | `afcd:F007726` Sage, dried<br>`ciqual:11037` Sage, dried | same 1.0: `afcd:F007726` ~ `ciqual:11037` |
| `cofid:16-420` | `afcd:F007853` Salmon, pink, canned in brine, drained<br>`cofid:16-420` Salmon, pink, canned in brine, drained | same 1.0: `afcd:F007853` ~ `cofid:16-420` |
| `cofid:16-418` | `afcd:F007860` Salmon, red, canned in brine, drained<br>`cofid:16-418` Salmon, red, canned in brine, drained | same 1.0: `afcd:F007860` ~ `cofid:16-418` |
| `cofid:19-656` | `afcd:F008112` Sausage, beef, raw<br>`cofid:19-656` Sausages, beef, raw | same 1.0: `afcd:F008112` ~ `cofid:19-656` |
| `cofid:11-958` | `afcd:F008174` Scone, plain, homemade<br>`cofid:11-958` Scones, plain, homemade | same 1.0: `afcd:F008174` ~ `cofid:11-958` |
| `ciqual:15047` | `afcd:F008209` Seed, chia, dried<br>`ciqual:15047` Chia, seed, dried | same 1.0: `afcd:F008209` ~ `ciqual:15047` |
| `ciqual:11061` | `afcd:F008211` Seed, poppy<br>`ciqual:11061` Poppy, seed | same 1.0: `afcd:F008211` ~ `ciqual:11061` |
| `ciqual:15011` | `afcd:F008215` Seed, sunflower<br>`ciqual:15011` Sunflower, seed | same 1.0: `afcd:F008215` ~ `ciqual:15011` |
| `ciqual:20173` | `afcd:F008373` Snow pea, fresh, raw<br>`ciqual:20173` Snow pea, raw | unsure 0.75: `afcd:F008373` ~ `ciqual:20173` |
| `cofid:13-521` | `afcd:F008749` Spinach, baby, fresh, raw<br>`cofid:13-521` Spinach, baby, raw | unsure 0.75: `afcd:F008749` ~ `cofid:13-521` |
| `usda:2346409` | `afcd:F008952` Strawberry, raw<br>`ciqual:13014` Strawberry, raw<br>`cofid:14-324` Strawberries, raw<br>`usda:2346409` Strawberries, raw | same 1.0: `afcd:F008952` ~ `ciqual:13014`<br>same 1.0: `afcd:F008952` ~ `cofid:14-324`<br>same 1.0: `afcd:F008952` ~ `usda:2346409` |
| `cofid:17-060` | `afcd:F008969` Sugar, brown<br>`ciqual:31017` Sugar, brown<br>`cofid:17-060` Sugar, brown | same 1.0: `afcd:F008969` ~ `ciqual:31017`<br>same 1.0: `afcd:F008969` ~ `cofid:17-060` |
| `cofid:14-263` | `afcd:F008983` Sultana<br>`cofid:14-263` Sultanas | same 1.0: `afcd:F008983` ~ `cofid:14-263` |
| `cofid:17-065` | `afcd:F009049` Syrup, golden<br>`cofid:17-065` Syrup, golden | same 1.0: `afcd:F009049` ~ `cofid:17-065` |
| `cofid:13-883` | `afcd:F009160` Thyme, dried, ground<br>`cofid:13-883` Thyme, dried, ground | same 1.0: `afcd:F009160` ~ `cofid:13-883` |
| `cofid:13-519` | `afcd:F009190` Tomato, cherry, raw<br>`ciqual:20172` Tomato, cherry, raw<br>`cofid:13-519` Tomatoes, cherry, raw | same 1.0: `afcd:F009190` ~ `ciqual:20172`<br>same 1.0: `afcd:F009190` ~ `cofid:13-519` |
| `cofid:16-416` | `afcd:F009285` Tuna, canned in brine, drained<br>`ciqual:26039` Tuna,  canned in brine, drained<br>`cofid:16-416` Tuna, canned in brine, drained | same 1.0: `afcd:F009285` ~ `ciqual:26039`<br>same 1.0: `afcd:F009285` ~ `cofid:16-416` |
| `ciqual:11091` | `afcd:F009499` Vinegar, balsamic<br>`ciqual:11091` Vinegar, balsamic | same 1.0: `afcd:F009499` ~ `ciqual:11091` |
| `cofid:13-669@row2827` | `afcd:F009532` Watercress, raw<br>`ciqual:20022` Watercress, raw<br>`cofid:13-669@row2827` Watercress, raw | same 1.0: `afcd:F009532` ~ `ciqual:20022`<br>same 1.0: `afcd:F009532` ~ `cofid:13-669@row2827` |
| `ciqual:9660` | `afcd:F009536` Wheat germ<br>`ciqual:9660` Wheat germ | same 1.0: `afcd:F009536` ~ `ciqual:9660` |
| `cofid:17-752` | `afcd:F009571` Wine, red<br>`ciqual:5214` Wine, red<br>`cofid:17-752` Wine, red | same 1.0: `afcd:F009571` ~ `ciqual:5214`<br>same 1.0: `afcd:F009571` ~ `cofid:17-752` |
| `ciqual:5216` | `afcd:F009579` Wine, rose<br>`ciqual:5216` Wine, rose | same 1.0: `afcd:F009579` ~ `ciqual:5216` |
| `cofid:17-757` | `afcd:F009590` Wine, white, sparkling<br>`ciqual:5201` Wine, white, sparkling<br>`cofid:17-757` Wine, white, sparkling | same 1.0: `afcd:F009590` ~ `ciqual:5201`<br>same 1.0: `afcd:F009590` ~ `cofid:17-757` |
| `cofid:16-263` | `ciqual:10001` Squid, raw<br>`cofid:16-263` Squid, raw | same 1.0: `ciqual:10001` ~ `cofid:16-263` |
| `cofid:16-260` | `ciqual:10011` Oyster, raw<br>`cofid:16-260` Oysters, raw | same 1.0: `ciqual:10011` ~ `cofid:16-260` |
| `cofid:16-254` | `ciqual:10016` Cuttlefish, raw<br>`cofid:16-254` Cuttlefish, raw | same 1.0: `ciqual:10016` ~ `cofid:16-254` |
| `cofid:16-235` | `ciqual:10030` Crayfish, raw<br>`cofid:16-235` Crayfish, raw | same 1.0: `ciqual:10030` ~ `cofid:16-235` |
| `cofid:13-811` | `ciqual:10999` Chervil, dried<br>`cofid:13-811` Chervil, dried | same 1.0: `ciqual:10999` ~ `cofid:13-811` |
| `usda:1104647` | `ciqual:11000` Garlic, raw<br>`cofid:13-244` Garlic, raw<br>`usda:1104647` Garlic, raw | same 1.0: `ciqual:11000` ~ `cofid:13-244`<br>same 1.0: `ciqual:11000` ~ `usda:1104647` |
| `cofid:13-844` | `ciqual:11014` Parsley, fresh<br>`cofid:13-844` Parsley, fresh | same 1.0: `ciqual:11014` ~ `cofid:13-844` |
| `cofid:13-258` | `ciqual:11016` Horseradish, raw<br>`cofid:13-258` Horseradish, raw | same 1.0: `ciqual:11016` ~ `cofid:13-258` |
| `cofid:17-339` | `ciqual:11018` Vinegar<br>`cofid:17-339` Vinegar | same 1.0: `ciqual:11018` ~ `cofid:17-339` |
| `cofid:13-845` | `ciqual:11024` Parsley, dried<br>`cofid:13-845` Parsley, dried | same 1.0: `ciqual:11024` ~ `cofid:13-845` |
| `cofid:13-836` | `ciqual:11027` Mint, fresh<br>`cofid:13-836` Mint, fresh | same 1.0: `ciqual:11027` ~ `cofid:13-836` |
| `cofid:13-837` | `ciqual:11029` Mint, dried<br>`cofid:13-837` Mint, dried | same 1.0: `ciqual:11029` ~ `cofid:13-837` |
| `cofid:13-804` | `ciqual:11033` Basil, fresh<br>`cofid:13-804` Basil, fresh | same 1.0: `ciqual:11033` ~ `cofid:13-804` |
| `cofid:13-835` | `ciqual:11034` Marjoram, dried<br>`cofid:13-835` Marjoram, dried | same 1.0: `ciqual:11034` ~ `cofid:13-835` |
| `cofid:13-852` | `ciqual:11039` Saffron<br>`cofid:13-852` Saffron | same 1.0: `ciqual:11039` ~ `cofid:13-852` |
| `cofid:13-825` | `ciqual:11063` Dill, dried<br>`cofid:13-825` Dill, dried | same 1.0: `ciqual:11063` ~ `cofid:13-825` |
| `cofid:13-892` | `ciqual:11068` Rosemary, fresh<br>`cofid:13-892` Rosemary, fresh | same 1.0: `ciqual:11068` ~ `cofid:13-892` |
| `cofid:13-853` | `ciqual:11069` Sage, fresh<br>`cofid:13-853` Sage, fresh | same 1.0: `ciqual:11069` ~ `cofid:13-853` |
| `cofid:13-893` | `ciqual:11070` Thyme, fresh<br>`cofid:13-893` Thyme, fresh | same 1.0: `ciqual:11070` ~ `cofid:13-893` |
| `cofid:13-857` | `ciqual:11092` Tarragon, fresh<br>`cofid:13-857` Tarragon, fresh | same 1.0: `ciqual:11092` ~ `cofid:13-857` |
| `cofid:13-824` | `ciqual:11093` Dill, fresh<br>`cofid:13-824` Dill, fresh | same 1.0: `ciqual:11093` ~ `cofid:13-824` |
| `cofid:14-321` | `ciqual:13037` Pear, flesh and skin, raw<br>`cofid:14-321` Pears, raw, flesh and skin | same 1.0: `ciqual:13037` ~ `cofid:14-321` |
| `ciqual:13161` | `ciqual:13161` Dairy and cereal-based beverage for baby's dinner, with vegetables, from 4/6 months<br>`ciqual:13172` Dairy and cereal-based beverage for baby's dinner, with vegetables, from 4/6 months | same 1.0: `ciqual:13161` ~ `ciqual:13172` |
| `cofid:14-844` | `ciqual:15010` Sesame seed<br>`cofid:14-844` Sesame seeds | same 1.0: `ciqual:15010` ~ `cofid:14-844` |
| `cofid:17-002` | `ciqual:16030` Cocoa butter<br>`cofid:17-002` Cocoa butter | same 1.0: `ciqual:16030` ~ `cofid:17-002` |
| `cofid:17-158` | `ciqual:18005` Coffee, powder, instant<br>`cofid:17-158` Coffee, powder, instant | same 1.0: `ciqual:18005` ~ `cofid:17-158` |
| `ciqual:18028` | `ciqual:18028` Bottled water, flavoured, no added sugars and no sweetener(s)<br>`ciqual:18030` Bottled water, flavoured, no added sugars and with sweetener(s) | same 1.0: `ciqual:18028` ~ `ciqual:18030` |
| `cofid:14-820` | `ciqual:18041` Coconut milk<br>`cofid:14-820` Coconut milk | same 1.0: `ciqual:18041` ~ `cofid:14-820` |
| `ciqual:18340` | `ciqual:18340` Carbonated beverage or fruit soft drink, fruit content < 10% , no added sugars and with sweetener(s)<br>`ciqual:18345` Carbonated beverage or fruit soft drink, fruit content < 10% , no added sugars and no sweetener(s) | same 1.0: `ciqual:18340` ~ `ciqual:18345` |
| `cofid:12-320` | `ciqual:19023` Milk, whole, UHT<br>`cofid:12-320` Milk, whole, UHT | same 1.0: `ciqual:19023` ~ `cofid:12-320` |
| `cofid:12-596` | `ciqual:19024` Milk, whole, pasteurised<br>`cofid:12-596` Milk, whole, pasteurised, average | same 1.0: `ciqual:19024` ~ `cofid:12-596` |
| `cofid:12-314` | `ciqual:19041` Milk, semi-skimmed, UHT<br>`cofid:12-314` Milk, semi-skimmed, UHT | same 1.0: `ciqual:19041` ~ `cofid:12-314` |
| `cofid:12-313` | `ciqual:19042` Milk, semi-skimmed, pasteurised<br>`cofid:12-313` Milk, semi-skimmed, pasteurised, average | same 1.0: `ciqual:19042` ~ `cofid:12-313` |
| `cofid:12-554` | `ciqual:19050` Milk, skimmed, UHT<br>`cofid:12-554` Milk, skimmed, UHT | same 1.0: `ciqual:19050` ~ `cofid:12-554` |
| `cofid:12-307` | `ciqual:19051` Milk, skimmed, pasteurised<br>`cofid:12-307` Milk, skimmed, pasteurised, average | same 1.0: `ciqual:19051` ~ `cofid:12-307` |
| `ciqual:19593` | `ciqual:19593` Yogurt or fermented milk, plain<br>`ciqual:19600` Yoghurt or fermented milk, plain (average) | same 1.0: `ciqual:19593` ~ `ciqual:19600` |
| `cofid:12-555` | `ciqual:19860` Yogurt, Greek-style, plain<br>`cofid:12-555` Yogurt, Greek style, plain | same 1.0: `ciqual:19860` ~ `cofid:12-555` |
| `cofid:13-523` | `ciqual:20019` Cucumber, flesh and skin, raw<br>`cofid:13-523` Cucumber, raw, flesh and skin | same 1.0: `ciqual:20019` ~ `cofid:13-523` |
| `cofid:13-520` | `ciqual:20031` Lettuce, raw<br>`cofid:13-520` Lettuce, average, raw | same 1.0: `ciqual:20031` ~ `cofid:13-520` |
| `cofid:13-499` | `ciqual:20034` Onion, raw<br>`cofid:13-499` Onions, raw | same 1.0: `ciqual:20034` ~ `cofid:13-499` |
| `usda:2685577` | `ciqual:20053` Eggplant, raw<br>`usda:2685577` Eggplant, raw | same 1.0: `ciqual:20053` ~ `usda:2685577` |
| `cofid:13-219` | `ciqual:20055` Celeriac, raw<br>`cofid:13-219` Celeriac, raw | same 1.0: `ciqual:20055` ~ `cofid:13-219` |
| `cofid:13-164` | `ciqual:20091` Beetroot, raw<br>`cofid:13-164` Beetroot, raw | same 1.0: `ciqual:20091` ~ `cofid:13-164` |
| `cofid:13-342` | `ciqual:20097` Shallot, raw<br>`cofid:13-342` Shallots, raw | same 1.0: `ciqual:20097` ~ `cofid:13-342` |
| `usda:2685582` | `ciqual:20170` Tomato puree, canned<br>`usda:2685582` Tomato, puree, canned | unsure 1.0: `ciqual:20170` ~ `usda:2685582` |
| `cofid:14-289` | `ciqual:2018` Prune juice<br>`cofid:14-289` Prune juice | same 1.0: `ciqual:2018` ~ `cofid:14-289` |
| `usda:2747659` | `ciqual:20181` Parsnip, raw<br>`cofid:13-312` Parsnip, raw<br>`usda:2747659` Parsnips, raw | same 1.0: `ciqual:20181` ~ `cofid:13-312`<br>same 1.0: `ciqual:20181` ~ `usda:2747659` |
| `cofid:13-234` | `ciqual:20218` Curly kale, raw<br>`cofid:13-234` Curly kale, raw | same 1.0: `ciqual:20218` ~ `cofid:13-234` |
| `cofid:14-285` | `ciqual:2024` Passion fruit juice, fresh<br>`cofid:14-285` Passion fruit juice | unsure 0.75: `ciqual:2024` ~ `cofid:14-285` |
| `cofid:14-279` | `ciqual:2030` Lime juice, fresh<br>`cofid:14-279` Lime juice, fresh | same 1.0: `ciqual:2030` ~ `cofid:14-279` |
| `cofid:13-517` | `ciqual:20385` Tomato, raw (average)<br>`cofid:13-517` Tomatoes, standard, raw | unsure 0.67: `ciqual:20385` ~ `cofid:13-517` |
| `cofid:13-118` | `ciqual:20917` Tempeh<br>`cofid:13-118` Tempeh | same 1.0: `ciqual:20917` ~ `cofid:13-118` |
| `cofid:12-946` | `ciqual:22500` Omelette, plain, homemade<br>`cofid:12-946` Omelette, plain, homemade | same 1.0: `ciqual:22500` ~ `cofid:12-946` |
| `cofid:12-947` | `ciqual:22506` Omelette with cheese, homemade<br>`cofid:12-947` Omelette, cheese, homemade | unsure 1.0: `ciqual:22506` ~ `cofid:12-947` |
| `usda:2768188` | `ciqual:26006` Alaska pollock, raw<br>`usda:2768188` Alaska Pollock, raw | same 1.0: `ciqual:26006` ~ `usda:2768188` |
| `cofid:16-080` | `ciqual:26104` John dory, raw<br>`cofid:16-080` John Dory, raw | same 1.0: `ciqual:26104` ~ `cofid:16-080` |
| `cofid:16-091` | `ciqual:26130` Ling, raw<br>`cofid:16-091` Ling, raw | same 1.0: `ciqual:26130` ~ `cofid:16-091` |
| `cofid:16-142` | `ciqual:26162` Shark, raw<br>`cofid:16-142` Shark, raw | same 1.0: `ciqual:26162` ~ `cofid:16-142` |
| `cofid:16-154` | `ciqual:27019` Tilapia, raw<br>`cofid:16-154` Tilapia, raw | same 1.0: `ciqual:27019` ~ `cofid:16-154` |
| `cofid:19-128` | `ciqual:28505` Corned-beef, canned<br>`cofid:19-128` Corned beef, canned | same 1.0: `ciqual:28505` ~ `cofid:19-128` |
| `ciqual:30150` | `ciqual:30150` Merguez sausage, raw<br>`ciqual:30151` Merguez sausage, raw (average) | same 1.0: `ciqual:30150` ~ `ciqual:30151` |
| `cofid:19-106` | `ciqual:30176` Liver sausage<br>`cofid:19-106` Liver sausage | same 1.0: `ciqual:30176` ~ `cofid:19-106` |
| `cofid:19-517` | `ciqual:30350` Salami<br>`cofid:19-517` Salami | same 1.0: `ciqual:30350` ~ `cofid:19-517` |
| `cofid:17-063` | `ciqual:31016` Sugar, white<br>`cofid:17-063` Sugar, white | same 1.0: `ciqual:31016` ~ `cofid:17-063` |
| `cofid:17-114` | `ciqual:31050` Marshmallow<br>`cofid:17-114` Marshmallows | same 1.0: `ciqual:31050` ~ `cofid:17-114` |
| `cofid:18-488` | `ciqual:36003` Chicken, meat, raw<br>`cofid:18-488` Chicken, meat, average, raw | same 1.0: `ciqual:36003` ~ `cofid:18-488` |
| `usda:2727568` | `ciqual:36023` Chicken, wing, meat and skin, raw<br>`usda:2727568` Chicken, wing, meat and skin, raw | same 1.0: `ciqual:36023` ~ `usda:2727568` |
| `usda:2727569` | `ciqual:36029` Chicken, breast, meat and skin, raw<br>`usda:2727569` Chicken, breast, meat and skin, raw | same 1.0: `ciqual:36029` ~ `usda:2727569` |
| `cofid:18-350` | `ciqual:36301` Turkey, meat, raw<br>`cofid:18-350` Turkey, meat, average, raw | same 1.0: `ciqual:36301` ~ `cofid:18-350` |
| `cofid:11-027` | `ciqual:4000` Tapioca, raw<br>`cofid:11-027` Tapioca, raw | same 1.0: `ciqual:4000` ~ `cofid:11-027` |
| `cofid:18-396` | `ciqual:40058` Heart, lamb, raw<br>`cofid:18-396` Heart, lamb, raw | same 1.0: `ciqual:40058` ~ `cofid:18-396` |
| `cofid:18-413` | `ciqual:40102` Liver, lamb, raw<br>`cofid:18-413` Liver, lamb, raw | same 1.0: `ciqual:40102` ~ `cofid:18-413` |
| `cofid:18-409` | `ciqual:40106` Liver, calf, raw<br>`cofid:18-409` Liver, calf, raw | same 1.0: `ciqual:40106` ~ `cofid:18-409` |
| `cofid:18-423` | `ciqual:40207` Tongue, lamb, raw<br>`cofid:18-423` Tongue, lamb, raw | same 1.0: `ciqual:40207` ~ `cofid:18-423` |
| `cofid:18-421` | `ciqual:40302` Sweetbread, lamb, raw<br>`cofid:18-421` Sweetbread, lamb, raw | same 1.0: `ciqual:40302` ~ `cofid:18-421` |
| `cofid:18-402` | `ciqual:40407` Kidney, lamb, raw<br>`cofid:18-402` Kidney, lamb, raw | same 1.0: `ciqual:40407` ~ `cofid:18-402` |
| `cofid:17-222` | `ciqual:5006` Cider, dry<br>`cofid:17-222` Cider, dry | same 1.0: `ciqual:5006` ~ `cofid:17-222` |
| `cofid:17-224` | `ciqual:5007` Cider, sweet<br>`cofid:17-224` Cider, sweet | same 1.0: `ciqual:5007` ~ `cofid:17-224` |
| `cofid:17-755` | `ciqual:5215` Wine, white, dry<br>`cofid:17-755` Wine, white, dry | same 1.0: `ciqual:5215` ~ `cofid:17-755` |
| `cofid:13-167` | `ciqual:54500` Breadfruit, raw<br>`cofid:13-167` Breadfruit, raw | same 1.0: `ciqual:54500` ~ `cofid:13-167` |
| `cofid:18-486` | `ciqual:6521` Veal, escalope, raw<br>`cofid:18-486` Veal, escalope, raw | same 1.0: `ciqual:6521` ~ `cofid:18-486` |
| `cofid:11-940` | `ciqual:7300` Rusk<br>`cofid:11-940` Rusks | same 1.0: `ciqual:7300` ~ `cofid:11-940` |
| `cofid:11-988` | `ciqual:7603` Croissant (average)<br>`cofid:11-988` Croissants | same 1.0: `ciqual:7603` ~ `cofid:11-988` |
| `cofid:11-872` | `ciqual:9108` Rice, wild, raw<br>`cofid:11-872` Rice, wild, raw | same 1.0: `ciqual:9108` ~ `cofid:11-872` |
| `cofid:11-876` | `ciqual:9109` Rice, red, raw<br>`cofid:11-876` Rice, red, raw | same 1.0: `ciqual:9109` ~ `cofid:11-876` |
| `cofid:14-843` | `ciqual:9340` Quinoa, raw<br>`cofid:14-843` Quinoa, raw | same 1.0: `ciqual:9340` ~ `cofid:14-843` |
| `cofid:11-904` | `ciqual:9690` Wheat, bulgur, raw<br>`cofid:11-904` Wheat, bulgur, raw | same 1.0: `ciqual:9690` ~ `cofid:11-904` |
| `cofid:11-726` | `ciqual:9815` Pasta, fresh, with egg, raw<br>`cofid:11-726` Pasta, egg, fresh, raw | same 1.0: `ciqual:9815` ~ `cofid:11-726` |
| `usda:2259793` | `cofid:12-184` Yogurt, whole milk, plain<br>`usda:2259793` Yogurt, plain, whole milk | same 1.0: `cofid:12-184` ~ `usda:2259793` |
| `usda:2346407` | `cofid:13-510` Cabbage, green, raw<br>`usda:2346407` Cabbage, green, raw | same 1.0: `cofid:13-510` ~ `usda:2346407` |
| `cofid:15-776` | `cofid:15-776` Curry, pea and potato, homemade<br>`cofid:15-781` Curry, potato and pea, homemade | same 1.0: `cofid:15-776` ~ `cofid:15-781` |
| `cofid:16-127` | `cofid:16-127` Red snapper, flesh only, fried in blended oil, weighed with bones and skin<br>`cofid:16-128` Red snapper, flesh only, fried in blended oil, weighed with bones and skin | same 1.0: `cofid:16-127` ~ `cofid:16-128` |
| `usda:748323` | `cofid:17-033` Oil, corn<br>`usda:748323` Oil, corn | same 1.0: `cofid:17-033` ~ `usda:748323` |
| `cofid:18-470` | `cofid:18-470` Beef, mince, stewed<br>`cofid:19-607` Beef, mince, stewed | same 1.0: `cofid:18-470` ~ `cofid:19-607` |
| `usda:2003591` | `usda:2003591` Orange juice, no pulp, not fortified, from concentrate, refrigerated<br>`usda:2003597` Orange juice, no pulp, not fortified, not from concentrate, refrigerated | unsure 1.0: `usda:2003591` ~ `usda:2003597` |
| `usda:2262072` | `usda:2262072` Peanut butter, creamy<br>`usda:2758989` Peanut butter, Creamy | same 1.0: `usda:2262072` ~ `usda:2758989` |
