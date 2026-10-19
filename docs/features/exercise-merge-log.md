# Exercise merge log

Written by `tools/exercises` (`python3 -m almanac_exercises build`); do not edit by hand.
Sources: free-exercise-db `f00c92c7dcf1`, wger `8f72cb2feba9`, and the 302 workout-guide rows already shipped.

Rule (owner, 2026-10-19): one record per real exercise. Rows are matched on the name (normalised: case, plurals, equipment words, `push-up`/`pushup`…) plus muscle group plus equipment. Equal names are **same**; a name overlap of 0.75 or more is **unsure** and is merged too, unless the names differ by a word that makes a different variation (incline, seated, weighted, one-arm…). Every source's fields are kept on the record, tagged with the source; where they disagree both values are kept and listed under Conflicts.

| | Count |
|---|---:|
| workout-guide rows | 302 |
| free-exercise-db rows | 876 |
| wger rows | 872 |
| new records shipped | 783 |
| merges into workout-guide rows | 132 |
| records with more than one source | 182 |
| records with a conflict | 34 |
| held (no graphic) | 679 |
| workout-guide pairs kept apart | 0 |

## Conflicts

Both values are kept. The record shows its base row's value until the owner says otherwise.

| Record | Field | Values |
|---|---|---|
| `workout-guide:exercise-deadlift` | primaryMuscle | Lats (wger:184); Lower Back (free-exercise-db:Barbell_Deadlift); Posterior Chain (workout-guide:exercise-deadlift) |
| `free-exercise-db:Barbell_Full_Squat` | primaryMuscle | Hamstrings (wger:1801); Quads (free-exercise-db:Barbell_Full_Squat) |
| `workout-guide:exercise-shrug` | primaryMuscle | Traps (free-exercise-db:Barbell_Shrug); Upper Back (workout-guide:exercise-shrug) |
| `workout-guide:exercise-squat` | primaryMuscle | Hamstrings (wger:1627); Quads (workout-guide:exercise-squat, free-exercise-db:Barbell_Squat, wger:615) |
| `workout-guide:exercise-dumbbell-bent-over-row` | primaryMuscle | Lats (wger:81); Upper Back (free-exercise-db:Bent_Over_Two-Dumbbell_Row) |
| `workout-guide:exercise-bodyweight-squat` | primaryMuscle | Glutes (wger:1315); Quads (workout-guide:exercise-bodyweight-squat, free-exercise-db:Bodyweight_Squat, wger:1312) |
| `workout-guide:exercise-cable-rear-delt-fly` | primaryMuscle | Rear Delts (workout-guide:exercise-cable-rear-delt-fly); Shoulders (free-exercise-db:Cable_Rear_Delt_Fly, wger:822) |
| `free-exercise-db:Clean` | primaryMuscle | Glutes (wger:1438); Hamstrings (free-exercise-db:Clean) |
| `free-exercise-db:Dumbbell_Rear_Lunge` | primaryMuscle | Glutes (wger:1651); Quads (free-exercise-db:Dumbbell_Rear_Lunge) |
| `workout-guide:exercise-dumbbell-shrug` | primaryMuscle | Traps (free-exercise-db:Dumbbell_Shrug); Upper Back (workout-guide:exercise-dumbbell-shrug) |
| `workout-guide:exercise-front-squat` | primaryMuscle | Glutes (wger:257); Quads (workout-guide:exercise-front-squat, free-exercise-db:Front_Barbell_Squat) |
| `workout-guide:exercise-leg-press` | primaryMuscle | Hamstrings (wger:371); Quads (workout-guide:exercise-leg-press, free-exercise-db:Leg_Press) |
| `workout-guide:exercise-one-arm-dumbbell-row` | primaryMuscle | Lats (wger:1701); Upper Back (free-exercise-db:One-Arm_Dumbbell_Row) |
| `free-exercise-db:Recumbent_Bike` | primaryMuscle | Hamstrings (wger:1376); Quads (free-exercise-db:Recumbent_Bike) |
| `workout-guide:exercise-reverse-curl` | primaryMuscle | Biceps (free-exercise-db:Reverse_Barbell_Curl, wger:495); Forearms (workout-guide:exercise-reverse-curl) |
| `workout-guide:exercise-reverse-hyperextension` | primaryMuscle | Glutes (workout-guide:exercise-reverse-hyperextension); Hamstrings (free-exercise-db:Reverse_Hyperextension) |
| `workout-guide:exercise-scapular-pull-up` | primaryMuscle | Lats (workout-guide:exercise-scapular-pull-up); Traps (free-exercise-db:Scapular_Pull-Up) |
| `workout-guide:exercise-seated-row` | primaryMuscle | Lats (wger:921); Upper Back (free-exercise-db:Seated_Cable_Rows) |
| `free-exercise-db:Sled_Push` | primaryMuscle | Calves (wger:1523); Quads (free-exercise-db:Sled_Push) |
| `workout-guide:exercise-smith-machine-squat` | primaryMuscle | Glutes (wger:1747); Quads (workout-guide:exercise-smith-machine-squat, free-exercise-db:Smith_Machine_Squat) |
| `workout-guide:exercise-split-squat` | primaryMuscle | Hamstrings (free-exercise-db:Split_Squats); Quads (workout-guide:exercise-split-squat) |
| `workout-guide:exercise-sumo-deadlift` | primaryMuscle | Hamstrings (free-exercise-db:Sumo_Deadlift); Posterior Chain (workout-guide:exercise-sumo-deadlift); Quads (wger:630) |
| `workout-guide:exercise-superman` | primaryMuscle | Glutes (wger:636); Lower Back (workout-guide:exercise-superman, free-exercise-db:Superman) |
| `free-exercise-db:T-Bar_Row_with_Handle` | primaryMuscle | Lats (wger:919); Upper Back (free-exercise-db:T-Bar_Row_with_Handle) |
| `workout-guide:exercise-trap-bar-deadlift` | primaryMuscle | Posterior Chain (workout-guide:exercise-trap-bar-deadlift); Quads (free-exercise-db:Trap_Bar_Deadlift) |
| `workout-guide:exercise-worlds-greatest-stretch` | primaryMuscle | Hamstrings (free-exercise-db:Worlds_Greatest_Stretch); Mobility (workout-guide:exercise-worlds-greatest-stretch) |
| `workout-guide:exercise-reverse-snow-angel` | primaryMuscle | Traps (wger:1215); Upper Back (workout-guide:exercise-reverse-snow-angel) |
| `workout-guide:exercise-jumping-jack` | primaryMuscle | Calves (wger:1316, wger:1669); Quads (wger:320, wger:1314) |
| `workout-guide:exercise-torso-twist-stretch` | primaryMuscle | Core (wger:1377); Mobility (workout-guide:exercise-torso-twist-stretch) |
| `workout-guide:exercise-cossack-squat` | primaryMuscle | Glutes (wger:1407); Quads (workout-guide:exercise-cossack-squat) |
| `workout-guide:exercise-wall-sit` | primaryMuscle | Glutes (wger:1408); Quads (workout-guide:exercise-wall-sit) |
| `workout-guide:exercise-dumbbell-romanian-deadlift` | primaryMuscle | Glutes (wger:1750); Hamstrings (workout-guide:exercise-dumbbell-romanian-deadlift, wger:1652) |
| `workout-guide:exercise-belt-squat` | primaryMuscle | Glutes (wger:1935); Quads (workout-guide:exercise-belt-squat) |
| `workout-guide:exercise-pistol-squat` | primaryMuscle | Hamstrings (wger:456); Quads (workout-guide:exercise-pistol-squat) |

## Merges

| Record | Members (name) | Matches |
|---|---|---|
| `workout-guide:exercise-arm-circles` | `free-exercise-db:Arm_Circles` Arm Circles<br>`workout-guide:exercise-arm-circles` Arm Circles | same 1.0: `workout-guide:exercise-arm-circles` ~ `free-exercise-db:Arm_Circles` |
| `workout-guide:exercise-arnold-press` | `free-exercise-db:Arnold_Dumbbell_Press` Arnold Dumbbell Press<br>`workout-guide:exercise-arnold-press` Arnold Press | same 1.0: `workout-guide:exercise-arnold-press` ~ `free-exercise-db:Arnold_Dumbbell_Press` |
| `free-exercise-db:Band_Assisted_Pull-Up` | `free-exercise-db:Band_Assisted_Pull-Up` Band Assisted Pull-Up<br>`wger:1929` Assisted Pull-Up | same 1.0: `free-exercise-db:Band_Assisted_Pull-Up` ~ `wger:1929` |
| `free-exercise-db:Barbell_Ab_Rollout` | `free-exercise-db:Barbell_Ab_Rollout` Barbell Ab Rollout<br>`wger:41` Barbell Ab Rollout | same 1.0: `free-exercise-db:Barbell_Ab_Rollout` ~ `wger:41` |
| `workout-guide:exercise-bench-press` | `free-exercise-db:Barbell_Bench_Press_-_Medium_Grip` Barbell Bench Press - Medium Grip<br>`wger:1295` Barbell Bench Press - NB<br>`wger:73` Bench Press<br>`workout-guide:exercise-bench-press` Bench Press | same 1.0: `workout-guide:exercise-bench-press` ~ `free-exercise-db:Barbell_Bench_Press_-_Medium_Grip`<br>unsure 0.67: `workout-guide:exercise-bench-press` ~ `wger:1295`<br>same 1.0: `workout-guide:exercise-bench-press` ~ `wger:73` |
| `workout-guide:exercise-ez-bar-curl` | `free-exercise-db:Barbell_Curl` Barbell Curl<br>`workout-guide:exercise-ez-bar-curl` EZ-Bar Curl | same 1.0: `workout-guide:exercise-ez-bar-curl` ~ `free-exercise-db:Barbell_Curl` |
| `workout-guide:exercise-deadlift` | `free-exercise-db:Barbell_Deadlift` Barbell Deadlift<br>`wger:184` Deadlifts<br>`workout-guide:exercise-deadlift` Deadlift | same 1.0: `workout-guide:exercise-deadlift` ~ `free-exercise-db:Barbell_Deadlift`<br>same 1.0: `workout-guide:exercise-deadlift` ~ `wger:184` |
| `free-exercise-db:Barbell_Full_Squat` | `free-exercise-db:Barbell_Full_Squat` Barbell Full Squat<br>`wger:1801` Barbell Full Squat | same 1.0: `free-exercise-db:Barbell_Full_Squat` ~ `wger:1801` |
| `workout-guide:exercise-barbell-glute-bridge` | `free-exercise-db:Barbell_Glute_Bridge` Barbell Glute Bridge<br>`workout-guide:exercise-barbell-glute-bridge` Barbell Glute Bridge | same 1.0: `workout-guide:exercise-barbell-glute-bridge` ~ `free-exercise-db:Barbell_Glute_Bridge` |
| `free-exercise-db:Barbell_Hack_Squat` | `free-exercise-db:Barbell_Hack_Squat` Barbell Hack Squat<br>`wger:43` Barbell Hack Squats | same 1.0: `free-exercise-db:Barbell_Hack_Squat` ~ `wger:43` |
| `workout-guide:exercise-hip-thrust` | `free-exercise-db:Barbell_Hip_Thrust` Barbell Hip Thrust<br>`wger:294` Hip Thrust<br>`wger:901` Barbell Hip Thrust<br>`workout-guide:exercise-hip-thrust` Hip Thrust | same 1.0: `workout-guide:exercise-hip-thrust` ~ `free-exercise-db:Barbell_Hip_Thrust`<br>same 1.0: `workout-guide:exercise-hip-thrust` ~ `wger:294`<br>same 1.0: `workout-guide:exercise-hip-thrust` ~ `wger:901` |
| `workout-guide:exercise-incline-bench-press` | `free-exercise-db:Barbell_Incline_Bench_Press_-_Medium_Grip` Barbell Incline Bench Press - Medium Grip<br>`wger:538` Incline Bench Press - Barbell<br>`wger:539` Incline Bench Press - MP<br>`workout-guide:exercise-incline-bench-press` Incline Bench Press | same 1.0: `workout-guide:exercise-incline-bench-press` ~ `free-exercise-db:Barbell_Incline_Bench_Press_-_Medium_Grip`<br>same 1.0: `workout-guide:exercise-incline-bench-press` ~ `wger:538`<br>unsure 0.75: `workout-guide:exercise-incline-bench-press` ~ `wger:539` |
| `free-exercise-db:Barbell_Shoulder_Press` | `free-exercise-db:Barbell_Shoulder_Press` Barbell Shoulder Press<br>`wger:566` Shoulder Press, Barbell | same 1.0: `free-exercise-db:Barbell_Shoulder_Press` ~ `wger:566` |
| `workout-guide:exercise-shrug` | `free-exercise-db:Barbell_Shrug` Barbell Shrug<br>`workout-guide:exercise-shrug` Barbell Shrug | same 1.0: `workout-guide:exercise-shrug` ~ `free-exercise-db:Barbell_Shrug` |
| `workout-guide:exercise-squat` | `free-exercise-db:Barbell_Squat` Barbell Squat<br>`wger:1627` Barbell squat<br>`wger:1805` Barbell Squat<br>`wger:615` Squats<br>`workout-guide:exercise-squat` Squat | same 1.0: `workout-guide:exercise-squat` ~ `free-exercise-db:Barbell_Squat`<br>same 1.0: `workout-guide:exercise-squat` ~ `wger:1627`<br>same 1.0: `workout-guide:exercise-squat` ~ `wger:1805`<br>same 1.0: `workout-guide:exercise-squat` ~ `wger:615` |
| `free-exercise-db:Barbell_Walking_Lunge` | `free-exercise-db:Barbell_Walking_Lunge` Barbell Walking Lunge<br>`wger:802` Barbell Lunges Walking | same 1.0: `free-exercise-db:Barbell_Walking_Lunge` ~ `wger:802` |
| `workout-guide:exercise-bench-dip` | `free-exercise-db:Bench_Dips` Bench Dips<br>`workout-guide:exercise-bench-dip` Bench Dip | same 1.0: `workout-guide:exercise-bench-dip` ~ `free-exercise-db:Bench_Dips` |
| `workout-guide:exercise-dumbbell-bent-over-row` | `free-exercise-db:Bent_Over_Two-Dumbbell_Row` Bent Over Two-Dumbbell Row<br>`wger:81` Bent Over Dumbbell Rows<br>`workout-guide:exercise-dumbbell-bent-over-row` Dumbbell Bent Over Row | unsure 0.75: `workout-guide:exercise-dumbbell-bent-over-row` ~ `free-exercise-db:Bent_Over_Two-Dumbbell_Row`<br>same 1.0: `workout-guide:exercise-dumbbell-bent-over-row` ~ `wger:81` |
| `workout-guide:exercise-bodyweight-squat` | `free-exercise-db:Bodyweight_Squat` Bodyweight Squat<br>`wger:1312` Bodyweight Squat HD<br>`wger:1315` Bodyweight Squat HD<br>`workout-guide:exercise-bodyweight-squat` Bodyweight Squat | same 1.0: `workout-guide:exercise-bodyweight-squat` ~ `free-exercise-db:Bodyweight_Squat`<br>same 1.0: `wger:1312` ~ `wger:1315`<br>unsure 0.67: `workout-guide:exercise-bodyweight-squat` ~ `wger:1312` |
| `free-exercise-db:Butterfly` | `free-exercise-db:Butterfly` Butterfly<br>`wger:135` Butterfly | same 1.0: `free-exercise-db:Butterfly` ~ `wger:135` |
| `workout-guide:exercise-cable-crunch` | `free-exercise-db:Cable_Crunch` Cable Crunch<br>`wger:173` Crunches With Cable<br>`workout-guide:exercise-cable-crunch` Cable Crunch | same 1.0: `workout-guide:exercise-cable-crunch` ~ `free-exercise-db:Cable_Crunch`<br>same 1.0: `workout-guide:exercise-cable-crunch` ~ `wger:173` |
| `workout-guide:exercise-rope-hammer-curl` | `free-exercise-db:Cable_Hammer_Curls_-_Rope_Attachment` Cable Hammer Curls - Rope Attachment<br>`workout-guide:exercise-rope-hammer-curl` Rope Hammer Curl | unsure 0.75: `workout-guide:exercise-rope-hammer-curl` ~ `free-exercise-db:Cable_Hammer_Curls_-_Rope_Attachment` |
| `free-exercise-db:Cable_One_Arm_Tricep_Extension` | `free-exercise-db:Cable_One_Arm_Tricep_Extension` Cable One Arm Tricep Extension<br>`wger:803` One Arm Triceps Extensions on Cable | same 1.0: `free-exercise-db:Cable_One_Arm_Tricep_Extension` ~ `wger:803` |
| `workout-guide:exercise-cable-rear-delt-fly` | `free-exercise-db:Cable_Rear_Delt_Fly` Cable Rear Delt Fly<br>`wger:822` Cable Rear Delt Fly<br>`workout-guide:exercise-cable-rear-delt-fly` Cable Rear Delt Fly | same 1.0: `workout-guide:exercise-cable-rear-delt-fly` ~ `free-exercise-db:Cable_Rear_Delt_Fly`<br>same 1.0: `workout-guide:exercise-cable-rear-delt-fly` ~ `wger:822` |
| `free-exercise-db:Cable_Rope_Overhead_Triceps_Extension` | `free-exercise-db:Cable_Rope_Overhead_Triceps_Extension` Cable Rope Overhead Triceps Extension<br>`free-exercise-db:Triceps_Overhead_Extension_with_Rope` Triceps Overhead Extension with Rope | same 1.0: `free-exercise-db:Cable_Rope_Overhead_Triceps_Extension` ~ `free-exercise-db:Triceps_Overhead_Extension_with_Rope` |
| `free-exercise-db:Cable_Wrist_Curl` | `free-exercise-db:Cable_Wrist_Curl` Cable Wrist Curl<br>`wger:1771` Wrist curl, cable | same 1.0: `free-exercise-db:Cable_Wrist_Curl` ~ `wger:1771` |
| `workout-guide:exercise-leg-press-calf-raise` | `free-exercise-db:Calf_Press_On_The_Leg_Press_Machine` Calf Press On The Leg Press Machine<br>`wger:146` Calf Press Using Leg Press Machine<br>`workout-guide:exercise-leg-press-calf-raise` Leg Press Calf Raise | same 1.0: `free-exercise-db:Calf_Press_On_The_Leg_Press_Machine` ~ `wger:146`<br>unsure 0.75: `workout-guide:exercise-leg-press-calf-raise` ~ `free-exercise-db:Calf_Press_On_The_Leg_Press_Machine` |
| `workout-guide:exercise-childs-pose` | `free-exercise-db:Childs_Pose` Child's Pose<br>`wger:1002` Child's pose<br>`workout-guide:exercise-childs-pose` Child's Pose | same 1.0: `workout-guide:exercise-childs-pose` ~ `free-exercise-db:Childs_Pose`<br>same 1.0: `workout-guide:exercise-childs-pose` ~ `wger:1002` |
| `free-exercise-db:Chin-Up` | `free-exercise-db:Chin-Up` Chin-Up<br>`wger:152` Chin Up<br>`wger:154` Chin-ups | same 1.0: `free-exercise-db:Chin-Up` ~ `wger:152`<br>same 1.0: `free-exercise-db:Chin-Up` ~ `wger:154` |
| `free-exercise-db:Clean` | `free-exercise-db:Clean` Clean<br>`wger:1438` Clean | same 1.0: `free-exercise-db:Clean` ~ `wger:1438` |
| `free-exercise-db:Clean_and_Press` | `free-exercise-db:Clean_and_Press` Clean and Press<br>`wger:1901` Clean and Press | same 1.0: `free-exercise-db:Clean_and_Press` ~ `wger:1901` |
| `workout-guide:exercise-close-grip-bench-press` | `free-exercise-db:Close-Grip_Barbell_Bench_Press` Close-Grip Barbell Bench Press<br>`wger:1897` Close-Grip Bench Press<br>`workout-guide:exercise-close-grip-bench-press` Close-Grip Bench Press | same 1.0: `workout-guide:exercise-close-grip-bench-press` ~ `free-exercise-db:Close-Grip_Barbell_Bench_Press`<br>same 1.0: `workout-guide:exercise-close-grip-bench-press` ~ `wger:1897` |
| `workout-guide:exercise-concentration-curl` | `free-exercise-db:Concentration_Curls` Concentration Curls<br>`wger:1649` Concentration Curl<br>`wger:202` Dumbbell Concentration Curl<br>`workout-guide:exercise-concentration-curl` Concentration Curl | same 1.0: `workout-guide:exercise-concentration-curl` ~ `free-exercise-db:Concentration_Curls`<br>same 1.0: `workout-guide:exercise-concentration-curl` ~ `wger:1649`<br>same 1.0: `workout-guide:exercise-concentration-curl` ~ `wger:202` |
| `free-exercise-db:Cross_Body_Hammer_Curl` | `free-exercise-db:Cross_Body_Hammer_Curl` Cross Body Hammer Curl<br>`wger:1502` DB Cross Body Hammer Curls | same 1.0: `free-exercise-db:Cross_Body_Hammer_Curl` ~ `wger:1502` |
| `workout-guide:exercise-crunch` | `free-exercise-db:Crunches` Crunches<br>`wger:1319` Crunches HD<br>`wger:167` Crunches<br>`workout-guide:exercise-crunch` Crunch | same 1.0: `workout-guide:exercise-crunch` ~ `free-exercise-db:Crunches`<br>unsure 0.5: `workout-guide:exercise-crunch` ~ `wger:1319`<br>same 1.0: `workout-guide:exercise-crunch` ~ `wger:167` |
| `workout-guide:exercise-dead-bug` | `free-exercise-db:Dead_Bug` Dead Bug<br>`workout-guide:exercise-dead-bug` Dead Bug | same 1.0: `workout-guide:exercise-dead-bug` ~ `free-exercise-db:Dead_Bug` |
| `workout-guide:exercise-decline-bench-press` | `free-exercise-db:Decline_Barbell_Bench_Press` Decline Barbell Bench Press<br>`wger:185` Decline Bench Press Barbell<br>`workout-guide:exercise-decline-bench-press` Decline Bench Press | same 1.0: `workout-guide:exercise-decline-bench-press` ~ `free-exercise-db:Decline_Barbell_Bench_Press`<br>same 1.0: `workout-guide:exercise-decline-bench-press` ~ `wger:185` |
| `free-exercise-db:Decline_Dumbbell_Bench_Press` | `free-exercise-db:Decline_Dumbbell_Bench_Press` Decline Dumbbell Bench Press<br>`wger:186` Decline Bench Press Dumbbell | same 1.0: `free-exercise-db:Decline_Dumbbell_Bench_Press` ~ `wger:186` |
| `workout-guide:exercise-decline-push-up` | `free-exercise-db:Decline_Push-Up` Decline Push-Up<br>`wger:1112` Push-Ups | Decline<br>`wger:188` Decline Pushups<br>`workout-guide:exercise-decline-push-up` Decline Push-up | same 1.0: `workout-guide:exercise-decline-push-up` ~ `free-exercise-db:Decline_Push-Up`<br>same 1.0: `workout-guide:exercise-decline-push-up` ~ `wger:1112`<br>same 1.0: `workout-guide:exercise-decline-push-up` ~ `wger:188` |
| `free-exercise-db:Decline_Smith_Press` | `free-exercise-db:Decline_Smith_Press` Decline Smith Press<br>`free-exercise-db:Smith_Machine_Decline_Press` Smith Machine Decline Press | same 1.0: `free-exercise-db:Decline_Smith_Press` ~ `free-exercise-db:Smith_Machine_Decline_Press` |
| `free-exercise-db:Deficit_Deadlift` | `free-exercise-db:Deficit_Deadlift` Deficit Deadlift<br>`wger:189` Deficit Deadlift | same 1.0: `free-exercise-db:Deficit_Deadlift` ~ `wger:189` |
| `workout-guide:exercise-chest-dip` | `free-exercise-db:Dips_-_Chest_Version` Dips - Chest Version<br>`workout-guide:exercise-chest-dip` Chest Dip | unsure 0.67: `workout-guide:exercise-chest-dip` ~ `free-exercise-db:Dips_-_Chest_Version` |
| `workout-guide:exercise-donkey-calf-raise` | `free-exercise-db:Donkey_Calf_Raises` Donkey Calf Raises<br>`workout-guide:exercise-donkey-calf-raise` Donkey Calf Raise | same 1.0: `workout-guide:exercise-donkey-calf-raise` ~ `free-exercise-db:Donkey_Calf_Raises` |
| `workout-guide:exercise-drag-curl` | `free-exercise-db:Drag_Curl` Drag Curl<br>`workout-guide:exercise-drag-curl` Drag Curl | same 1.0: `workout-guide:exercise-drag-curl` ~ `free-exercise-db:Drag_Curl` |
| `workout-guide:exercise-dumbbell-bench-press` | `free-exercise-db:Dumbbell_Bench_Press` Dumbbell Bench Press<br>`wger:1676` Dumbbell Bench Press<br>`workout-guide:exercise-dumbbell-bench-press` Dumbbell Bench Press | same 1.0: `workout-guide:exercise-dumbbell-bench-press` ~ `free-exercise-db:Dumbbell_Bench_Press`<br>same 1.0: `workout-guide:exercise-dumbbell-bench-press` ~ `wger:1676` |
| `workout-guide:exercise-bicep-curl` | `free-exercise-db:Dumbbell_Bicep_Curl` Dumbbell Bicep Curl<br>`wger:92` Biceps Curls With Dumbbell<br>`workout-guide:exercise-bicep-curl` Bicep Curl | same 1.0: `workout-guide:exercise-bicep-curl` ~ `free-exercise-db:Dumbbell_Bicep_Curl`<br>same 1.0: `workout-guide:exercise-bicep-curl` ~ `wger:92` |
| `workout-guide:exercise-dumbbell-fly` | `free-exercise-db:Dumbbell_Flyes` Dumbbell Flyes<br>`workout-guide:exercise-dumbbell-fly` Dumbbell Fly | same 1.0: `workout-guide:exercise-dumbbell-fly` ~ `free-exercise-db:Dumbbell_Flyes` |
| `free-exercise-db:Dumbbell_Incline_Row` | `free-exercise-db:Dumbbell_Incline_Row` Dumbbell Incline Row<br>`wger:310` Incline Dumbbell Row | same 1.0: `free-exercise-db:Dumbbell_Incline_Row` ~ `wger:310` |
| `free-exercise-db:Dumbbell_Rear_Lunge` | `free-exercise-db:Dumbbell_Rear_Lunge` Dumbbell Rear Lunge<br>`wger:1651` Dumbbell Rear Lunge | same 1.0: `free-exercise-db:Dumbbell_Rear_Lunge` ~ `wger:1651` |
| `free-exercise-db:Dumbbell_Shoulder_Press` | `free-exercise-db:Dumbbell_Shoulder_Press` Dumbbell Shoulder Press<br>`wger:1337` Shoulder Press (Dumbbell) | same 1.0: `free-exercise-db:Dumbbell_Shoulder_Press` ~ `wger:1337` |
| `workout-guide:exercise-dumbbell-shrug` | `free-exercise-db:Dumbbell_Shrug` Dumbbell Shrug<br>`workout-guide:exercise-dumbbell-shrug` Dumbbell Shrug | same 1.0: `workout-guide:exercise-dumbbell-shrug` ~ `free-exercise-db:Dumbbell_Shrug` |
| `workout-guide:exercise-dumbbell-side-bend` | `free-exercise-db:Dumbbell_Side_Bend` Dumbbell Side Bend<br>`wger:1650` Dumbbell Side Bend<br>`wger:556` Side Bends on Machine<br>`workout-guide:exercise-dumbbell-side-bend` Dumbbell Side Bend | same 1.0: `workout-guide:exercise-dumbbell-side-bend` ~ `free-exercise-db:Dumbbell_Side_Bend`<br>same 1.0: `workout-guide:exercise-dumbbell-side-bend` ~ `wger:1650`<br>same 1.0: `workout-guide:exercise-dumbbell-side-bend` ~ `wger:556` |
| `workout-guide:exercise-step-up` | `free-exercise-db:Dumbbell_Step_Ups` Dumbbell Step Ups<br>`workout-guide:exercise-step-up` Step-Up | same 1.0: `workout-guide:exercise-step-up` ~ `free-exercise-db:Dumbbell_Step_Ups` |
| `free-exercise-db:EZ-Bar_Skullcrusher` | `free-exercise-db:EZ-Bar_Skullcrusher` EZ-Bar Skullcrusher<br>`wger:1297` EZ-Bar Skullcrusher - NB<br>`wger:246` Skullcrusher SZ-bar | same 1.0: `free-exercise-db:EZ-Bar_Skullcrusher` ~ `wger:246`<br>unsure 0.5: `free-exercise-db:EZ-Bar_Skullcrusher` ~ `wger:1297` |
| `free-exercise-db:Exercise_Ball_Crunch` | `free-exercise-db:Exercise_Ball_Crunch` Exercise Ball Crunch<br>`wger:165` Ball crunches | same 1.0: `free-exercise-db:Exercise_Ball_Crunch` ~ `wger:165` |
| `free-exercise-db:External_Rotation_with_Cable` | `free-exercise-db:External_Rotation_with_Cable` External Rotation with Cable<br>`wger:142` Cable External Rotation | same 1.0: `free-exercise-db:External_Rotation_with_Cable` ~ `wger:142` |
| `workout-guide:exercise-front-squat` | `free-exercise-db:Front_Barbell_Squat` Front Barbell Squat<br>`wger:257` Front Squats<br>`workout-guide:exercise-front-squat` Front Squat | same 1.0: `workout-guide:exercise-front-squat` ~ `free-exercise-db:Front_Barbell_Squat`<br>same 1.0: `workout-guide:exercise-front-squat` ~ `wger:257` |
| `workout-guide:exercise-cable-front-raise` | `free-exercise-db:Front_Cable_Raise` Front Cable Raise<br>`wger:1731` Front Raise (Cable)<br>`workout-guide:exercise-cable-front-raise` Cable Front Raise | same 1.0: `workout-guide:exercise-cable-front-raise` ~ `free-exercise-db:Front_Cable_Raise`<br>same 1.0: `workout-guide:exercise-cable-front-raise` ~ `wger:1731` |
| `workout-guide:exercise-front-raise` | `free-exercise-db:Front_Dumbbell_Raise` Front Dumbbell Raise<br>`workout-guide:exercise-front-raise` Front Raise | same 1.0: `workout-guide:exercise-front-raise` ~ `free-exercise-db:Front_Dumbbell_Raise` |
| `workout-guide:exercise-plate-front-raise` | `free-exercise-db:Front_Plate_Raise` Front Plate Raise<br>`wger:254` Front Raises with Plates<br>`wger:827` Front Plate Raise<br>`workout-guide:exercise-plate-front-raise` Plate Front Raise | same 1.0: `workout-guide:exercise-plate-front-raise` ~ `free-exercise-db:Front_Plate_Raise`<br>same 1.0: `workout-guide:exercise-plate-front-raise` ~ `wger:254`<br>same 1.0: `workout-guide:exercise-plate-front-raise` ~ `wger:827` |
| `workout-guide:exercise-good-morning` | `free-exercise-db:Good_Morning` Good Morning<br>`wger:268` Good Mornings<br>`workout-guide:exercise-good-morning` Good Morning | same 1.0: `workout-guide:exercise-good-morning` ~ `free-exercise-db:Good_Morning`<br>same 1.0: `workout-guide:exercise-good-morning` ~ `wger:268` |
| `workout-guide:exercise-hack-squat` | `free-exercise-db:Hack_Squat` Hack Squat<br>`wger:1414` Hack Squats<br>`workout-guide:exercise-hack-squat` Hack Squat | same 1.0: `workout-guide:exercise-hack-squat` ~ `free-exercise-db:Hack_Squat`<br>same 1.0: `workout-guide:exercise-hack-squat` ~ `wger:1414` |
| `workout-guide:exercise-hammer-curl` | `free-exercise-db:Hammer_Curls` Hammer Curls<br>`wger:1932` Hammer Curl<br>`wger:272` Hammer Curls<br>`workout-guide:exercise-hammer-curl` Hammer Curl | same 1.0: `workout-guide:exercise-hammer-curl` ~ `free-exercise-db:Hammer_Curls`<br>same 1.0: `workout-guide:exercise-hammer-curl` ~ `wger:1932`<br>same 1.0: `workout-guide:exercise-hammer-curl` ~ `wger:272` |
| `workout-guide:exercise-hamstring-stretch` | `free-exercise-db:Hamstring_Stretch` Hamstring Stretch<br>`workout-guide:exercise-hamstring-stretch` Hamstring Stretch | same 1.0: `workout-guide:exercise-hamstring-stretch` ~ `free-exercise-db:Hamstring_Stretch` |
| `workout-guide:exercise-handstand-push-up` | `free-exercise-db:Handstand_Push-Ups` Handstand Push-Ups<br>`wger:907` Handstand Push Up<br>`workout-guide:exercise-handstand-push-up` Handstand Push-up | same 1.0: `workout-guide:exercise-handstand-push-up` ~ `free-exercise-db:Handstand_Push-Ups`<br>same 1.0: `workout-guide:exercise-handstand-push-up` ~ `wger:907` |
| `workout-guide:exercise-hanging-leg-raise` | `free-exercise-db:Hanging_Leg_Raise` Hanging Leg Raise<br>`wger:283` Hanging Leg Raises<br>`workout-guide:exercise-hanging-leg-raise` Hanging Leg Raise | same 1.0: `workout-guide:exercise-hanging-leg-raise` ~ `free-exercise-db:Hanging_Leg_Raise`<br>same 1.0: `workout-guide:exercise-hanging-leg-raise` ~ `wger:283` |
| `free-exercise-db:Incline_Cable_Chest_Press` | `free-exercise-db:Incline_Cable_Chest_Press` Incline Cable Chest Press<br>`wger:1660` Cable Chest Press - Incline | same 1.0: `free-exercise-db:Incline_Cable_Chest_Press` ~ `wger:1660` |
| `workout-guide:exercise-incline-cable-fly` | `free-exercise-db:Incline_Cable_Flye` Incline Cable Flye<br>`workout-guide:exercise-incline-cable-fly` Incline Cable Fly | same 1.0: `workout-guide:exercise-incline-cable-fly` ~ `free-exercise-db:Incline_Cable_Flye` |
| `workout-guide:exercise-incline-dumbbell-curl` | `free-exercise-db:Incline_Dumbbell_Curl` Incline Dumbbell Curl<br>`wger:204` Dumbbell Incline Curl<br>`workout-guide:exercise-incline-dumbbell-curl` Incline Dumbbell Curl | same 1.0: `workout-guide:exercise-incline-dumbbell-curl` ~ `free-exercise-db:Incline_Dumbbell_Curl`<br>same 1.0: `workout-guide:exercise-incline-dumbbell-curl` ~ `wger:204` |
| `free-exercise-db:Incline_Dumbbell_Flyes` | `free-exercise-db:Incline_Dumbbell_Flyes` Incline Dumbbell Flyes<br>`wger:1643` Dumbbell Incline Fly<br>`wger:308` Incline Dumbbell Fly | same 1.0: `free-exercise-db:Incline_Dumbbell_Flyes` ~ `wger:308`<br>same 1.0: `free-exercise-db:Incline_Dumbbell_Flyes` ~ `wger:1643` |
| `workout-guide:exercise-incline-dumbbell-press` | `free-exercise-db:Incline_Dumbbell_Press` Incline Dumbbell Press<br>`wger:1277` Incline Dumbbell Press<br>`workout-guide:exercise-incline-dumbbell-press` Incline Dumbbell Press | same 1.0: `workout-guide:exercise-incline-dumbbell-press` ~ `free-exercise-db:Incline_Dumbbell_Press`<br>same 1.0: `workout-guide:exercise-incline-dumbbell-press` ~ `wger:1277` |
| `workout-guide:exercise-incline-push-up` | `free-exercise-db:Incline_Push-Up` Incline Push-Up<br>`free-exercise-db:Incline_Push-Up_Medium` Incline Push-Up Medium<br>`wger:1111` Push-Ups | Incline<br>`wger:313` Incline Push up<br>`workout-guide:exercise-incline-push-up` Incline Push-up | same 1.0: `workout-guide:exercise-incline-push-up` ~ `free-exercise-db:Incline_Push-Up`<br>unsure 0.67: `workout-guide:exercise-incline-push-up` ~ `free-exercise-db:Incline_Push-Up_Medium`<br>same 1.0: `workout-guide:exercise-incline-push-up` ~ `wger:1111`<br>same 1.0: `workout-guide:exercise-incline-push-up` ~ `wger:313` |
| `workout-guide:exercise-inverted-row` | `free-exercise-db:Inverted_Row` Inverted Row<br>`workout-guide:exercise-inverted-row` Inverted Row | same 1.0: `workout-guide:exercise-inverted-row` ~ `free-exercise-db:Inverted_Row` |
| `free-exercise-db:Isometric_Wipers` | `free-exercise-db:Isometric_Wipers` Isometric Wipers<br>`wger:314` Isometric Wipers | same 1.0: `free-exercise-db:Isometric_Wipers` ~ `wger:314` |
| `free-exercise-db:JM_Press` | `free-exercise-db:JM_Press` JM Press<br>`wger:1302` JM Press | same 1.0: `free-exercise-db:JM_Press` ~ `wger:1302` |
| `workout-guide:exercise-leg-extension` | `free-exercise-db:Leg_Extensions` Leg Extensions<br>`wger:369` Leg Extension<br>`wger:851` Leg Extension<br>`workout-guide:exercise-leg-extension` Leg Extension | same 1.0: `workout-guide:exercise-leg-extension` ~ `free-exercise-db:Leg_Extensions`<br>same 1.0: `workout-guide:exercise-leg-extension` ~ `wger:369`<br>same 1.0: `workout-guide:exercise-leg-extension` ~ `wger:851` |
| `workout-guide:exercise-leg-press` | `free-exercise-db:Leg_Press` Leg Press<br>`wger:371` Leg Press<br>`workout-guide:exercise-leg-press` Leg Press | same 1.0: `workout-guide:exercise-leg-press` ~ `free-exercise-db:Leg_Press`<br>same 1.0: `workout-guide:exercise-leg-press` ~ `wger:371` |
| `free-exercise-db:Leverage_Chest_Press` | `free-exercise-db:Leverage_Chest_Press` Leverage Chest Press<br>`wger:379` Leverage Machine Chest Press | same 1.0: `free-exercise-db:Leverage_Chest_Press` ~ `wger:379` |
| `free-exercise-db:Leverage_Iso_Row` | `free-exercise-db:Leverage_Iso_Row` Leverage Iso Row<br>`wger:380` Leverage Machine Iso Row | same 1.0: `free-exercise-db:Leverage_Iso_Row` ~ `wger:380` |
| `workout-guide:exercise-lying-leg-curl` | `free-exercise-db:Lying_Leg_Curls` Lying Leg Curls<br>`workout-guide:exercise-lying-leg-curl` Lying Leg Curl | same 1.0: `workout-guide:exercise-lying-leg-curl` ~ `free-exercise-db:Lying_Leg_Curls` |
| `free-exercise-db:Machine_Bicep_Curl` | `free-exercise-db:Machine_Bicep_Curl` Machine Bicep Curl<br>`wger:1424` Biceps Curl Machine | same 1.0: `free-exercise-db:Machine_Bicep_Curl` ~ `wger:1424` |
| `workout-guide:exercise-preacher-curl` | `free-exercise-db:Machine_Preacher_Curls` Machine Preacher Curls<br>`workout-guide:exercise-preacher-curl` Preacher Curl | same 1.0: `workout-guide:exercise-preacher-curl` ~ `free-exercise-db:Machine_Preacher_Curls` |
| `free-exercise-db:Narrow_Stance_Leg_Press` | `free-exercise-db:Narrow_Stance_Leg_Press` Narrow Stance Leg Press<br>`wger:373` Leg Presses (narrow) | unsure 0.75: `free-exercise-db:Narrow_Stance_Leg_Press` ~ `wger:373` |
| `workout-guide:exercise-one-arm-dumbbell-row` | `free-exercise-db:One-Arm_Dumbbell_Row` One-Arm Dumbbell Row<br>`wger:1701` One-Arm Heavy Row<br>`workout-guide:exercise-one-arm-dumbbell-row` One-Arm Dumbbell Row | same 1.0: `workout-guide:exercise-one-arm-dumbbell-row` ~ `free-exercise-db:One-Arm_Dumbbell_Row`<br>unsure 0.75: `workout-guide:exercise-one-arm-dumbbell-row` ~ `wger:1701` |
| `free-exercise-db:Overhead_Squat` | `free-exercise-db:Overhead_Squat` Overhead Squat<br>`wger:441` Overhead Squat | same 1.0: `free-exercise-db:Overhead_Squat` ~ `wger:441` |
| `workout-guide:exercise-pallof-press` | `free-exercise-db:Pallof_Press` Pallof Press<br>`workout-guide:exercise-pallof-press` Pallof Press | same 1.0: `workout-guide:exercise-pallof-press` ~ `free-exercise-db:Pallof_Press` |
| `workout-guide:exercise-plank` | `free-exercise-db:Plank` Plank<br>`wger:1317` Plank<br>`wger:458` Plank<br>`workout-guide:exercise-plank` Plank | same 1.0: `workout-guide:exercise-plank` ~ `free-exercise-db:Plank`<br>same 1.0: `workout-guide:exercise-plank` ~ `wger:1317`<br>same 1.0: `workout-guide:exercise-plank` ~ `wger:458` |
| `free-exercise-db:Plate_Twist` | `free-exercise-db:Plate_Twist` Plate Twist<br>`wger:1079` Plate twist | same 1.0: `free-exercise-db:Plate_Twist` ~ `wger:1079` |
| `workout-guide:exercise-cable-pull-through` | `free-exercise-db:Pull_Through` Pull Through<br>`wger:1751` Cable pull through<br>`workout-guide:exercise-cable-pull-through` Cable Pull-Through | same 1.0: `workout-guide:exercise-cable-pull-through` ~ `free-exercise-db:Pull_Through`<br>same 1.0: `workout-guide:exercise-cable-pull-through` ~ `wger:1751` |
| `workout-guide:exercise-pull-up` | `free-exercise-db:Pullups` Pullups<br>`wger:475` Pull-ups<br>`workout-guide:exercise-pull-up` Pull-up | same 1.0: `workout-guide:exercise-pull-up` ~ `free-exercise-db:Pullups`<br>same 1.0: `workout-guide:exercise-pull-up` ~ `wger:475` |
| `workout-guide:exercise-wide-push-up` | `free-exercise-db:Push-Up_Wide` Push-Up Wide<br>`workout-guide:exercise-wide-push-up` Wide Push-up | same 1.0: `workout-guide:exercise-wide-push-up` ~ `free-exercise-db:Push-Up_Wide` |
| `workout-guide:exercise-push-press` | `free-exercise-db:Push_Press` Push Press<br>`workout-guide:exercise-push-press` Push Press | same 1.0: `workout-guide:exercise-push-press` ~ `free-exercise-db:Push_Press` |
| `workout-guide:exercise-push-up` | `free-exercise-db:Pushups` Pushups<br>`wger:1551` Push-Up<br>`wger:1675` Push-Ups<br>`workout-guide:exercise-push-up` Push-up | same 1.0: `workout-guide:exercise-push-up` ~ `free-exercise-db:Pushups`<br>same 1.0: `workout-guide:exercise-push-up` ~ `wger:1551`<br>same 1.0: `workout-guide:exercise-push-up` ~ `wger:1675` |
| `free-exercise-db:Quad_Stretch` | `free-exercise-db:Quad_Stretch` Quad Stretch<br>`wger:1873` Quad Stretch | same 1.0: `free-exercise-db:Quad_Stretch` ~ `wger:1873` |
| `workout-guide:exercise-rack-pull` | `free-exercise-db:Rack_Pulls` Rack Pulls<br>`workout-guide:exercise-rack-pull` Rack Pull | same 1.0: `workout-guide:exercise-rack-pull` ~ `free-exercise-db:Rack_Pulls` |
| `free-exercise-db:Recumbent_Bike` | `free-exercise-db:Recumbent_Bike` Recumbent Bike<br>`wger:1376` Recumbent Bike | same 1.0: `free-exercise-db:Recumbent_Bike` ~ `wger:1376` |
| `workout-guide:exercise-reverse-curl` | `free-exercise-db:Reverse_Barbell_Curl` Reverse Barbell Curl<br>`wger:495` Reverse Curl<br>`workout-guide:exercise-reverse-curl` Reverse Curl | same 1.0: `workout-guide:exercise-reverse-curl` ~ `free-exercise-db:Reverse_Barbell_Curl`<br>same 1.0: `workout-guide:exercise-reverse-curl` ~ `wger:495` |
| `workout-guide:exercise-reverse-crunch` | `free-exercise-db:Reverse_Crunch` Reverse Crunch<br>`wger:1772` Reverse crunch<br>`workout-guide:exercise-reverse-crunch` Reverse Crunch | same 1.0: `workout-guide:exercise-reverse-crunch` ~ `free-exercise-db:Reverse_Crunch`<br>same 1.0: `workout-guide:exercise-reverse-crunch` ~ `wger:1772` |
| `workout-guide:exercise-reverse-hyperextension` | `free-exercise-db:Reverse_Hyperextension` Reverse Hyperextension<br>`workout-guide:exercise-reverse-hyperextension` Reverse Hyperextension | same 1.0: `workout-guide:exercise-reverse-hyperextension` ~ `free-exercise-db:Reverse_Hyperextension` |
| `free-exercise-db:Ring_Dips` | `free-exercise-db:Ring_Dips` Ring Dips<br>`wger:501` Ring Dips | same 1.0: `free-exercise-db:Ring_Dips` ~ `wger:501` |
| `workout-guide:exercise-romanian-deadlift` | `free-exercise-db:Romanian_Deadlift` Romanian Deadlift<br>`wger:507` Romanian Deadlift<br>`workout-guide:exercise-romanian-deadlift` Romanian Deadlift | same 1.0: `workout-guide:exercise-romanian-deadlift` ~ `free-exercise-db:Romanian_Deadlift`<br>same 1.0: `workout-guide:exercise-romanian-deadlift` ~ `wger:507` |
| `workout-guide:exercise-russian-twist` | `free-exercise-db:Russian_Twist` Russian Twist<br>`workout-guide:exercise-russian-twist` Russian Twist | same 1.0: `workout-guide:exercise-russian-twist` ~ `free-exercise-db:Russian_Twist` |
| `workout-guide:exercise-scapular-pull-up` | `free-exercise-db:Scapular_Pull-Up` Scapular Pull-Up<br>`workout-guide:exercise-scapular-pull-up` Scapular Pull-up | same 1.0: `workout-guide:exercise-scapular-pull-up` ~ `free-exercise-db:Scapular_Pull-Up` |
| `workout-guide:exercise-seated-row` | `free-exercise-db:Seated_Cable_Rows` Seated Cable Rows<br>`wger:1117` Seated Cable Row<br>`wger:921` Seated Cable Rows<br>`workout-guide:exercise-seated-row` Seated Cable Row | same 1.0: `workout-guide:exercise-seated-row` ~ `free-exercise-db:Seated_Cable_Rows`<br>same 1.0: `workout-guide:exercise-seated-row` ~ `wger:1117`<br>same 1.0: `workout-guide:exercise-seated-row` ~ `wger:921` |
| `workout-guide:exercise-seated-calf-raise` | `free-exercise-db:Seated_Calf_Raise` Seated Calf Raise<br>`wger:1365` Calf Raise with machine (seated)<br>`workout-guide:exercise-seated-calf-raise` Seated Calf Raise | same 1.0: `workout-guide:exercise-seated-calf-raise` ~ `free-exercise-db:Seated_Calf_Raise`<br>same 1.0: `workout-guide:exercise-seated-calf-raise` ~ `wger:1365` |
| `free-exercise-db:Seated_Dumbbell_Curl` | `free-exercise-db:Seated_Dumbbell_Curl` Seated Dumbbell Curl<br>`wger:1289` Seated Dumbbell Curls | same 1.0: `free-exercise-db:Seated_Dumbbell_Curl` ~ `wger:1289` |
| `workout-guide:exercise-seated-leg-curl` | `free-exercise-db:Seated_Leg_Curl` Seated Leg Curl<br>`workout-guide:exercise-seated-leg-curl` Seated Leg Curl | same 1.0: `workout-guide:exercise-seated-leg-curl` ~ `free-exercise-db:Seated_Leg_Curl` |
| `free-exercise-db:Seated_Side_Lateral_Raise` | `free-exercise-db:Seated_Side_Lateral_Raise` Seated Side Lateral Raise<br>`wger:918` Seated Dumbbell Side Lateral | unsure 0.75: `free-exercise-db:Seated_Side_Lateral_Raise` ~ `wger:918` |
| `free-exercise-db:Seated_Triceps_Press` | `free-exercise-db:Seated_Triceps_Press` Seated Triceps Press<br>`wger:1749` Seated Triceps Press<br>`wger:549` Seated Triceps Press | same 1.0: `free-exercise-db:Seated_Triceps_Press` ~ `wger:549`<br>same 1.0: `free-exercise-db:Seated_Triceps_Press` ~ `wger:1749` |
| `free-exercise-db:Shotgun_Row` | `free-exercise-db:Shotgun_Row` Shotgun Row<br>`wger:562` Shotgun Row | same 1.0: `free-exercise-db:Shotgun_Row` ~ `wger:562` |
| `free-exercise-db:Single-Leg_Leg_Extension` | `free-exercise-db:Single-Leg_Leg_Extension` Single-Leg Leg Extension<br>`wger:71` Single Leg Extension | same 1.0: `free-exercise-db:Single-Leg_Leg_Extension` ~ `wger:71` |
| `workout-guide:exercise-single-leg-glute-bridge` | `free-exercise-db:Single_Leg_Glute_Bridge` Single Leg Glute Bridge<br>`wger:1740` Single Leg Glute Bridge<br>`workout-guide:exercise-single-leg-glute-bridge` Single-Leg Glute Bridge | same 1.0: `workout-guide:exercise-single-leg-glute-bridge` ~ `free-exercise-db:Single_Leg_Glute_Bridge`<br>same 1.0: `workout-guide:exercise-single-leg-glute-bridge` ~ `wger:1740` |
| `free-exercise-db:Sit-Up` | `free-exercise-db:Sit-Up` Sit-Up<br>`wger:591` Sit-ups | same 1.0: `free-exercise-db:Sit-Up` ~ `wger:591` |
| `free-exercise-db:Sled_Push` | `free-exercise-db:Sled_Push` Sled Push<br>`wger:1523` Sled Push | same 1.0: `free-exercise-db:Sled_Push` ~ `wger:1523` |
| `workout-guide:exercise-smith-machine-bench-press` | `free-exercise-db:Smith_Machine_Bench_Press` Smith Machine Bench Press<br>`workout-guide:exercise-smith-machine-bench-press` Smith Machine Bench Press | same 1.0: `workout-guide:exercise-smith-machine-bench-press` ~ `free-exercise-db:Smith_Machine_Bench_Press` |
| `free-exercise-db:Smith_Machine_Close-Grip_Bench_Press` | `free-exercise-db:Smith_Machine_Close-Grip_Bench_Press` Smith Machine Close-Grip Bench Press<br>`wger:598` Smith Machine Close-grip Bench Press | same 1.0: `free-exercise-db:Smith_Machine_Close-Grip_Bench_Press` ~ `wger:598` |
| `workout-guide:exercise-smith-machine-squat` | `free-exercise-db:Smith_Machine_Squat` Smith Machine Squat<br>`wger:1747` Smith machine squat<br>`workout-guide:exercise-smith-machine-squat` Smith Machine Squat | same 1.0: `workout-guide:exercise-smith-machine-squat` ~ `free-exercise-db:Smith_Machine_Squat`<br>same 1.0: `workout-guide:exercise-smith-machine-squat` ~ `wger:1747` |
| `workout-guide:exercise-split-squat` | `free-exercise-db:Split_Squats` Split Squats<br>`wger:1366` Dumbbell Split Squat<br>`workout-guide:exercise-split-squat` Split Squat | same 1.0: `workout-guide:exercise-split-squat` ~ `free-exercise-db:Split_Squats`<br>same 1.0: `workout-guide:exercise-split-squat` ~ `wger:1366` |
| `workout-guide:exercise-standing-calf-raise` | `free-exercise-db:Standing_Calf_Raises` Standing Calf Raises<br>`wger:622` Standing Calf Raises<br>`workout-guide:exercise-standing-calf-raise` Standing Calf Raise | same 1.0: `workout-guide:exercise-standing-calf-raise` ~ `free-exercise-db:Standing_Calf_Raises`<br>same 1.0: `workout-guide:exercise-standing-calf-raise` ~ `wger:622` |
| `workout-guide:exercise-standing-dumbbell-press` | `free-exercise-db:Standing_Dumbbell_Press` Standing Dumbbell Press<br>`workout-guide:exercise-standing-dumbbell-press` Standing Dumbbell Press | same 1.0: `workout-guide:exercise-standing-dumbbell-press` ~ `free-exercise-db:Standing_Dumbbell_Press` |
| `free-exercise-db:Standing_Gastrocnemius_Calf_Stretch` | `free-exercise-db:Standing_Gastrocnemius_Calf_Stretch` Standing Gastrocnemius Calf Stretch<br>`wger:1239` Standing Calf Stretch | unsure 0.75: `free-exercise-db:Standing_Gastrocnemius_Calf_Stretch` ~ `wger:1239` |
| `free-exercise-db:Standing_Leg_Curl` | `free-exercise-db:Standing_Leg_Curl` Standing Leg Curl<br>`wger:367` Leg Curls (standing) | same 1.0: `free-exercise-db:Standing_Leg_Curl` ~ `wger:367` |
| `free-exercise-db:Stiff-Legged_Barbell_Deadlift` | `free-exercise-db:Stiff-Legged_Barbell_Deadlift` Stiff-Legged Barbell Deadlift<br>`wger:627` Stiff-legged Deadlifts | same 1.0: `free-exercise-db:Stiff-Legged_Barbell_Deadlift` ~ `wger:627` |
| `workout-guide:exercise-straight-arm-pulldown` | `free-exercise-db:Straight-Arm_Pulldown` Straight-Arm Pulldown<br>`wger:1726` Straight-Arm Pulldown (Cable)<br>`workout-guide:exercise-straight-arm-pulldown` Straight-Arm Pulldown | same 1.0: `workout-guide:exercise-straight-arm-pulldown` ~ `free-exercise-db:Straight-Arm_Pulldown`<br>same 1.0: `workout-guide:exercise-straight-arm-pulldown` ~ `wger:1726` |
| `workout-guide:exercise-sumo-deadlift` | `free-exercise-db:Sumo_Deadlift` Sumo Deadlift<br>`wger:630` Sumo Deadlift<br>`workout-guide:exercise-sumo-deadlift` Sumo Deadlift | same 1.0: `workout-guide:exercise-sumo-deadlift` ~ `free-exercise-db:Sumo_Deadlift`<br>same 1.0: `workout-guide:exercise-sumo-deadlift` ~ `wger:630` |
| `workout-guide:exercise-superman` | `free-exercise-db:Superman` Superman<br>`wger:636` Superman<br>`workout-guide:exercise-superman` Superman | same 1.0: `workout-guide:exercise-superman` ~ `free-exercise-db:Superman`<br>same 1.0: `workout-guide:exercise-superman` ~ `wger:636` |
| `free-exercise-db:T-Bar_Row_with_Handle` | `free-exercise-db:T-Bar_Row_with_Handle` T-Bar Row with Handle<br>`wger:919` T-Bar row | unsure 0.75: `free-exercise-db:T-Bar_Row_with_Handle` ~ `wger:919` |
| `workout-guide:exercise-trap-bar-deadlift` | `free-exercise-db:Trap_Bar_Deadlift` Trap Bar Deadlift<br>`workout-guide:exercise-trap-bar-deadlift` Trap Bar Deadlift | same 1.0: `workout-guide:exercise-trap-bar-deadlift` ~ `free-exercise-db:Trap_Bar_Deadlift` |
| `workout-guide:exercise-tricep-kickback` | `free-exercise-db:Tricep_Dumbbell_Kickback` Tricep Dumbbell Kickback<br>`wger:655` Tricep Dumbbell Kickback<br>`workout-guide:exercise-tricep-kickback` Tricep Kickback | same 1.0: `workout-guide:exercise-tricep-kickback` ~ `free-exercise-db:Tricep_Dumbbell_Kickback`<br>same 1.0: `workout-guide:exercise-tricep-kickback` ~ `wger:655` |
| `workout-guide:exercise-tricep-pushdown` | `free-exercise-db:Triceps_Pushdown` Triceps Pushdown<br>`wger:1185` Triceps Pushdown<br>`wger:805` Tricep Pushdown on Cable<br>`workout-guide:exercise-tricep-pushdown` Tricep Pushdown | same 1.0: `workout-guide:exercise-tricep-pushdown` ~ `free-exercise-db:Triceps_Pushdown`<br>same 1.0: `workout-guide:exercise-tricep-pushdown` ~ `wger:1185`<br>same 1.0: `workout-guide:exercise-tricep-pushdown` ~ `wger:805` |
| `workout-guide:exercise-rope-tricep-pushdown` | `free-exercise-db:Triceps_Pushdown_-_Rope_Attachment` Triceps Pushdown - Rope Attachment<br>`wger:1900` Tricep Rope Pushdowns<br>`workout-guide:exercise-rope-tricep-pushdown` Rope Tricep Pushdown | unsure 0.75: `workout-guide:exercise-rope-tricep-pushdown` ~ `free-exercise-db:Triceps_Pushdown_-_Rope_Attachment`<br>same 1.0: `workout-guide:exercise-rope-tricep-pushdown` ~ `wger:1900` |
| `workout-guide:exercise-upright-row` | `free-exercise-db:Upright_Barbell_Row` Upright Barbell Row<br>`workout-guide:exercise-upright-row` Upright Row | same 1.0: `workout-guide:exercise-upright-row` ~ `free-exercise-db:Upright_Barbell_Row` |
| `free-exercise-db:V-Bar_Pulldown` | `free-exercise-db:V-Bar_Pulldown` V-Bar Pulldown<br>`wger:695` V-Bar Pulldown | same 1.0: `free-exercise-db:V-Bar_Pulldown` ~ `wger:695` |
| `workout-guide:exercise-weighted-pull-up` | `free-exercise-db:Weighted_Pull_Ups` Weighted Pull Ups<br>`workout-guide:exercise-weighted-pull-up` Weighted Pull-up | same 1.0: `workout-guide:exercise-weighted-pull-up` ~ `free-exercise-db:Weighted_Pull_Ups` |
| `workout-guide:exercise-wide-grip-lat-pulldown` | `free-exercise-db:Wide-Grip_Lat_Pulldown` Wide-Grip Lat Pulldown<br>`wger:1697` Lat Pulldown (Wide Grip)<br>`workout-guide:exercise-wide-grip-lat-pulldown` Wide-Grip Lat Pulldown | same 1.0: `workout-guide:exercise-wide-grip-lat-pulldown` ~ `free-exercise-db:Wide-Grip_Lat_Pulldown`<br>same 1.0: `workout-guide:exercise-wide-grip-lat-pulldown` ~ `wger:1697` |
| `workout-guide:exercise-worlds-greatest-stretch` | `free-exercise-db:Worlds_Greatest_Stretch` World's Greatest Stretch<br>`workout-guide:exercise-worlds-greatest-stretch` World's Greatest Stretch | same 1.0: `workout-guide:exercise-worlds-greatest-stretch` ~ `free-exercise-db:Worlds_Greatest_Stretch` |
| `free-exercise-db:Zottman_Curl` | `free-exercise-db:Zottman_Curl` Zottman Curl<br>`wger:1683` Zottman curl | same 1.0: `free-exercise-db:Zottman_Curl` ~ `wger:1683` |
| `workout-guide:exercise-dumbbell-sumo-deadlift` | `wger:1088` Dumbbell sumo deadlift<br>`workout-guide:exercise-dumbbell-sumo-deadlift` Dumbbell Sumo Deadlift | same 1.0: `workout-guide:exercise-dumbbell-sumo-deadlift` ~ `wger:1088` |
| `workout-guide:exercise-seated-knee-tuck` | `wger:1105` Seated Knee Tuck<br>`wger:1106` Seated Knee Tuck<br>`workout-guide:exercise-seated-knee-tuck` Seated Knee Tuck | same 1.0: `workout-guide:exercise-seated-knee-tuck` ~ `wger:1105`<br>same 1.0: `workout-guide:exercise-seated-knee-tuck` ~ `wger:1106` |
| `workout-guide:exercise-side-lying-hip-abduction` | `wger:1202` Side Lying Hip Abduction<br>`workout-guide:exercise-side-lying-hip-abduction` Side-Lying Hip Abduction | same 1.0: `workout-guide:exercise-side-lying-hip-abduction` ~ `wger:1202` |
| `workout-guide:exercise-single-leg-romanian-deadlift` | `wger:1211` Romanian deadlift, single leg<br>`workout-guide:exercise-single-leg-romanian-deadlift` Single-Leg Romanian Deadlift | same 1.0: `workout-guide:exercise-single-leg-romanian-deadlift` ~ `wger:1211` |
| `workout-guide:exercise-reverse-snow-angel` | `wger:1215` Reverse Snow Angel<br>`workout-guide:exercise-reverse-snow-angel` Reverse Snow Angel | same 1.0: `workout-guide:exercise-reverse-snow-angel` ~ `wger:1215` |
| `workout-guide:exercise-machine-chest-press` | `wger:129` Chest Press<br>`wger:1918` Legend Chest Press<br>`workout-guide:exercise-machine-chest-press` Machine Chest Press | same 1.0: `workout-guide:exercise-machine-chest-press` ~ `wger:129`<br>unsure 0.67: `workout-guide:exercise-machine-chest-press` ~ `wger:1918` |
| `workout-guide:exercise-meadows-row` | `wger:1304` Meadows Row<br>`workout-guide:exercise-meadows-row` Meadows Row | same 1.0: `workout-guide:exercise-meadows-row` ~ `wger:1304` |
| `workout-guide:exercise-lying-leg-raise` | `wger:1313` Lying Leg Raise<br>`wger:377` Leg Raises, Lying<br>`workout-guide:exercise-lying-leg-raise` Lying Leg Raise | same 1.0: `workout-guide:exercise-lying-leg-raise` ~ `wger:1313`<br>same 1.0: `workout-guide:exercise-lying-leg-raise` ~ `wger:377` |
| `workout-guide:exercise-jumping-jack` | `wger:1314` Jumping Jack HD<br>`wger:1316` Jumping Jack HD<br>`wger:1669` Jumping Jacks<br>`wger:320` Jumping Jacks<br>`workout-guide:exercise-jumping-jack` Jumping Jack | same 1.0: `wger:1314` ~ `wger:1316`<br>unsure 0.67: `workout-guide:exercise-jumping-jack` ~ `wger:1314`<br>same 1.0: `workout-guide:exercise-jumping-jack` ~ `wger:1669`<br>same 1.0: `workout-guide:exercise-jumping-jack` ~ `wger:320` |
| `workout-guide:exercise-side-plank` | `wger:1321` Side Plank<br>`wger:580` Side Plank<br>`workout-guide:exercise-side-plank` Side Plank | same 1.0: `workout-guide:exercise-side-plank` ~ `wger:1321`<br>same 1.0: `workout-guide:exercise-side-plank` ~ `wger:580` |
| `workout-guide:exercise-torso-twist-stretch` | `wger:1377` TORSO TWIST<br>`workout-guide:exercise-torso-twist-stretch` Torso Twists | same 1.0: `workout-guide:exercise-torso-twist-stretch` ~ `wger:1377` |
| `workout-guide:exercise-band-pull-apart` | `wger:1380` Band pull-aparts<br>`workout-guide:exercise-band-pull-apart` Band Pull-Apart | same 1.0: `workout-guide:exercise-band-pull-apart` ~ `wger:1380` |
| `workout-guide:exercise-cossack-squat` | `wger:1407` Cossack squat<br>`workout-guide:exercise-cossack-squat` Cossack Squat | same 1.0: `workout-guide:exercise-cossack-squat` ~ `wger:1407` |
| `workout-guide:exercise-wall-sit` | `wger:1408` Wall-sit<br>`workout-guide:exercise-wall-sit` Wall Sit | same 1.0: `workout-guide:exercise-wall-sit` ~ `wger:1408` |
| `workout-guide:exercise-dragon-flag` | `wger:1409` Dragon-flag<br>`workout-guide:exercise-dragon-flag` Dragon Flag | same 1.0: `workout-guide:exercise-dragon-flag` ~ `wger:1409` |
| `workout-guide:exercise-bicycle-crunch` | `wger:1412` bicycle crunches<br>`workout-guide:exercise-bicycle-crunch` Bicycle Crunch | same 1.0: `workout-guide:exercise-bicycle-crunch` ~ `wger:1412` |
| `workout-guide:exercise-overhead-tricep-extension` | `wger:1513` Overhead Cable Tricep Extension<br>`workout-guide:exercise-overhead-tricep-extension` Overhead Tricep Extension | same 1.0: `workout-guide:exercise-overhead-tricep-extension` ~ `wger:1513` |
| `workout-guide:exercise-bird-dog` | `wger:1572` Bird Dog<br>`workout-guide:exercise-bird-dog` Bird Dog | same 1.0: `workout-guide:exercise-bird-dog` ~ `wger:1572` |
| `workout-guide:exercise-dumbbell-hip-thrust` | `wger:1642` Dumbbell Hip Thrust<br>`workout-guide:exercise-dumbbell-hip-thrust` Dumbbell Hip Thrust | same 1.0: `workout-guide:exercise-dumbbell-hip-thrust` ~ `wger:1642` |
| `workout-guide:exercise-dumbbell-romanian-deadlift` | `wger:1652` Dumbbell Romanian Deadlift<br>`wger:1750` Romanian Deadlift<br>`workout-guide:exercise-dumbbell-romanian-deadlift` Dumbbell Romanian Deadlift | same 1.0: `workout-guide:exercise-dumbbell-romanian-deadlift` ~ `wger:1652`<br>same 1.0: `workout-guide:exercise-dumbbell-romanian-deadlift` ~ `wger:1750` |
| `workout-guide:exercise-neutral-grip-pull-up` | `wger:1696` Pull-Ups (Neutral Grip)<br>`workout-guide:exercise-neutral-grip-pull-up` Neutral-Grip Pull-up | same 1.0: `workout-guide:exercise-neutral-grip-pull-up` ~ `wger:1696` |
| `workout-guide:exercise-machine-glute-kickback` | `wger:1723` Glute Kickback (Machine)<br>`workout-guide:exercise-machine-glute-kickback` Machine Glute Kickback | same 1.0: `workout-guide:exercise-machine-glute-kickback` ~ `wger:1723` |
| `workout-guide:exercise-hip-abduction-machine` | `wger:1748` Machine Hip Abduction<br>`workout-guide:exercise-hip-abduction-machine` Hip Abduction Machine | same 1.0: `workout-guide:exercise-hip-abduction-machine` ~ `wger:1748` |
| `workout-guide:exercise-clamshell` | `wger:1823` Clamshell<br>`workout-guide:exercise-clamshell` Clamshell | same 1.0: `workout-guide:exercise-clamshell` ~ `wger:1823` |
| `workout-guide:exercise-banded-clamshell` | `wger:1842` Banded Clamshell<br>`workout-guide:exercise-banded-clamshell` Banded Clamshell | same 1.0: `workout-guide:exercise-banded-clamshell` ~ `wger:1842` |
| `workout-guide:exercise-butterfly-stretch` | `wger:1843` Butterfly Stretch<br>`workout-guide:exercise-butterfly-stretch` Butterfly Stretch | same 1.0: `workout-guide:exercise-butterfly-stretch` ~ `wger:1843` |
| `workout-guide:exercise-wrist-extension` | `wger:1881` DB Wrist Extension<br>`workout-guide:exercise-wrist-extension` Wrist Extension | same 1.0: `workout-guide:exercise-wrist-extension` ~ `wger:1881` |
| `workout-guide:exercise-overhead-press` | `wger:1893` Overhead Barbell Press<br>`wger:687` Overhead Press<br>`workout-guide:exercise-overhead-press` Overhead Press | same 1.0: `workout-guide:exercise-overhead-press` ~ `wger:1893`<br>same 1.0: `workout-guide:exercise-overhead-press` ~ `wger:687` |
| `workout-guide:exercise-weighted-push-up` | `wger:1902` Weighted push-ups<br>`workout-guide:exercise-weighted-push-up` Weighted Push-up | same 1.0: `workout-guide:exercise-weighted-push-up` ~ `wger:1902` |
| `workout-guide:exercise-pec-deck` | `wger:1904` Pec Deck<br>`workout-guide:exercise-pec-deck` Pec Deck | same 1.0: `workout-guide:exercise-pec-deck` ~ `wger:1904` |
| `workout-guide:exercise-belt-squat` | `wger:1935` Belt Squat<br>`workout-guide:exercise-belt-squat` Belt Squat | same 1.0: `workout-guide:exercise-belt-squat` ~ `wger:1935` |
| `workout-guide:exercise-goblet-squat` | `wger:203` Dumbbell Goblet Squat<br>`workout-guide:exercise-goblet-squat` Goblet Squat | same 1.0: `workout-guide:exercise-goblet-squat` ~ `wger:203` |
| `workout-guide:exercise-walking-lunge` | `wger:206` Dumbbell Lunges Walking<br>`workout-guide:exercise-walking-lunge` Walking Lunge | same 1.0: `workout-guide:exercise-walking-lunge` ~ `wger:206` |
| `workout-guide:exercise-flutter-kick` | `wger:235` Flutter Kicks<br>`workout-guide:exercise-flutter-kick` Flutter Kick | same 1.0: `workout-guide:exercise-flutter-kick` ~ `wger:235` |
| `workout-guide:exercise-cable-fly` | `wger:237` Fly With Cable<br>`wger:924` Cable Fly<br>`workout-guide:exercise-cable-fly` Cable Fly | same 1.0: `workout-guide:exercise-cable-fly` ~ `wger:237`<br>same 1.0: `workout-guide:exercise-cable-fly` ~ `wger:924` |
| `workout-guide:exercise-glute-bridge` | `wger:265` Glute Bridge<br>`workout-guide:exercise-glute-bridge` Glute Bridge | same 1.0: `workout-guide:exercise-glute-bridge` ~ `wger:265` |
| `workout-guide:exercise-kettlebell-swing` | `wger:331` Kettlebell Swings<br>`workout-guide:exercise-kettlebell-swing` Kettlebell Swing | same 1.0: `workout-guide:exercise-kettlebell-swing` ~ `wger:331` |
| `workout-guide:exercise-landmine-press` | `wger:346` Landmine press<br>`workout-guide:exercise-landmine-press` Landmine Press | same 1.0: `workout-guide:exercise-landmine-press` ~ `wger:346` |
| `workout-guide:exercise-lateral-raise` | `wger:348` Lateral Raises<br>`workout-guide:exercise-lateral-raise` Lateral Raise | same 1.0: `workout-guide:exercise-lateral-raise` ~ `wger:348` |
| `workout-guide:exercise-leg-curl` | `wger:364` Leg Curl<br>`workout-guide:exercise-leg-curl` Leg Curl | same 1.0: `workout-guide:exercise-leg-curl` ~ `wger:364` |
| `workout-guide:exercise-pistol-squat` | `wger:456` Pistol Squat<br>`workout-guide:exercise-pistol-squat` Pistol Squat | same 1.0: `workout-guide:exercise-pistol-squat` ~ `wger:456` |
| `workout-guide:exercise-barbell-row` | `wger:508` Row<br>`workout-guide:exercise-barbell-row` Barbell Row | same 1.0: `workout-guide:exercise-barbell-row` ~ `wger:508` |
| `workout-guide:exercise-machine-shoulder-press` | `wger:543` Shoulder Press, on Machine<br>`workout-guide:exercise-machine-shoulder-press` Machine Shoulder Press | same 1.0: `workout-guide:exercise-machine-shoulder-press` ~ `wger:543` |
| `workout-guide:exercise-jump-squat` | `wger:614` Squat Jumps<br>`workout-guide:exercise-jump-squat` Jump Squat | same 1.0: `workout-guide:exercise-jump-squat` ~ `wger:614` |
| `workout-guide:exercise-high-knees` | `wger:983` High knees<br>`workout-guide:exercise-high-knees` High Knees | same 1.0: `workout-guide:exercise-high-knees` ~ `wger:983` |

## Kept apart: two workout-guide rows

These matched, but merging would fold one shipped workout-guide row into another that people's logged sets already point at. Left as two records for the owner.

| Row | Row | Score |
|---|---|---:|

## Held: no demonstration graphic

No member has an image this build can ship, so the record is not shipped (every exercise must have one). wger's own images are on wger.de, which this build does not read.

| Members |
|---|
| `free-exercise-db:Kettlebell_Halo` Kettlebell Halo |
| `free-exercise-db:Kettlebell_Halo_With_Overhead_Extension` Kettlebell Halo with Overhead Extension |
| `free-exercise-db:Kettlebell_Overhead_Triceps_Extension` Kettlebell Overhead Triceps Extension |
| `wger:1000` Floor dips |
| `wger:1001` High plank |
| `wger:1003` Kettlebell deadlifts |
| `wger:1004` Forward shoulder rotation |
| `wger:1005` Backward shoulder rotation |
| `wger:1006` Chin tuck |
| `wger:1007` Head turns |
| `wger:1008` Left neck stretch |
| `wger:1009` Right neck stretch |
| `wger:1010` Back neck stretch |
| `wger:1011` Front neck stretch |
| `wger:1012` Alternating bicep curls<br>`wger:1192` Alternating Biceps Curls With Dumbbell |
| `wger:1013` Left levator scapulae stretch |
| `wger:1014` Right levator scapulae stretch |
| `wger:1015` Clockwise neck circles |
| `wger:1016` Counterclockwise neck circles |
| `wger:1017` Neck half circles |
| `wger:1018` Head tilts |
| `wger:1019` Side plank right |
| `wger:1020` Pistol squats right |
| `wger:1021` Calf raises, right leg |
| `wger:1022` Single Arm Plank to Row |
| `wger:1027` Elevated prayer stretch |
| `wger:1028` Quadruped thoracic rotation left |
| `wger:1029` Quadruped thoracic rotation right |
| `wger:1080` Hindu Pushups |
| `wger:1081` Shoulder dislocates |
| `wger:1082` Bent over row to external rotation |
| `wger:1083` YWTs |
| `wger:1084` Dumbbell Floor Press<br>`wger:1674` Dumbbell Floor Press |
| `wger:1085` Dumbbell Bent Over Row |
| `wger:1086` Close-grip Press-ups |
| `wger:1087` Dumbbell Hang Power Cleans |
| `wger:1089` Medicine ball twist |
| `wger:1090` Vpushup |
| `wger:1091` Plank Shoulder Taps |
| `wger:1092` Bag training |
| `wger:1093` Rowing Machine |
| `wger:1094` Seated Bench Press |
| `wger:1096` Abduction while standing |
| `wger:1098` Seated rear delt rise |
| `wger:1099` Dynamic side hold |
| `wger:1100` Wall balls |
| `wger:1101` Horizontal traction isometry |
| `wger:1102` Alternate back lunges |
| `wger:1103` walking bridge |
| `wger:1104` Walking |
| `wger:1109` Cable Concentration Curl |
| `wger:1113` Push-Ups | Parallettes |
| `wger:1114` Rest (for timed workouts) |
| `wger:1115` 3D lunge warmup |
| `wger:1116` Dumbbell farmer's carry |
| `wger:1119` Remo maquina agarre estrecho |
| `wger:112` Body-Ups |
| `wger:1120` Remo maquina agarre estrecho supino |
| `wger:1124` Jalón abierto |
| `wger:1125` Jalón abierto supino |
| `wger:1126` Jalón cerrado |
| `wger:1127` Jalón cerrado supino |
| `wger:1131` Extensión de gluteos en polea |
| `wger:1132` Extensión de gluteo en  máquina |
| `wger:1136` JALONES PECHO NEUTRO |
| `wger:1137` PULL OVER POLEA ALTA |
| `wger:1138` JALON EN BANCO INCLINADO |
| `wger:1141` Arabesque |
| `wger:1143` Back extensión |
| `wger:1186` One Arm Bent Row |
| `wger:1187` High Pull |
| `wger:1188` Flexión lateral |
| `wger:1190` Curl de biceps con agarre prono |
| `wger:1193` Russian Twist |
| `wger:1194` PALLOF PRESS |
| `wger:1195` Side Slides + Squats |
| `wger:1196` Wall Drills |
| `wger:1198` Inverted Rows |
| `wger:12` Seated Hip Adduction |
| `wger:1200` Tibialis raises |
| `wger:1201` Dragon squat |
| `wger:1203` Calf raises, left leg |
| `wger:1204` Cycling cardio session |
| `wger:1205` Wrist curl, dumbbells |
| `wger:1207` Scorpion Kick |
| `wger:1208` Prisoner Squat |
| `wger:1209` Shoulder width three-point push-up |
| `wger:1210` Skydiver with arms in T-position |
| `wger:1214` Front lever tuck |
| `wger:1216` Recruitment Pulls |
| `wger:1217` Finger Pushup |
| `wger:1218` knee push-ups |
| `wger:1219` Australian pull-ups |
| `wger:1223` Claps over the head |
| `wger:1224` Dumbbell drag curls |
| `wger:1225` Dumbbell wide bicep curls |
| `wger:1226` Dumbbell bicep curl to press |
| `wger:1227` Dumbbell rear delt row |
| `wger:1228` Dumbbell close grip bench press |
| `wger:1229` Dumbbell upright-row |
| `wger:1230` Triceps stretch left |
| `wger:1231` Triceps stretch right |
| `wger:1232` Standing biceps stretch left |
| `wger:1233` Standing biceps stretch right |
| `wger:1234` Dumbbell Single-leg Hip Thrust |
| `wger:1238` Frog stand |
| `wger:124` Braced Squat |
| `wger:1240` Standing Soleus Stretch |
| `wger:1241` Exercise Band Dorsiflexion |
| `wger:1242` Exercise Band Plantarflexion |
| `wger:1243` Double Leg Calf Raise |
| `wger:1244` Yoga exercise: Cow-cat |
| `wger:1245` Front Lever |
| `wger:1246` TRX roll out |
| `wger:1248` Ice Scream maker |
| `wger:1252` Front lever pull-up |
| `wger:1259` TRX Obliques |
| `wger:1260` TRX hammer curl |
| `wger:1261` TRX gorilla biceps curl |
| `wger:1262` Trx Single Arm Bicep Curl |
| `wger:1263` Back bridge |
| `wger:1266` TRX Tricep Extension |
| `wger:1269` TRX dips |
| `wger:1270` Low Pulley Cable Fly |
| `wger:1271` Low Pulley Cable fFly<br>`wger:1272` Low Pulley Cable fFly |
| `wger:1273` Pullover |
| `wger:1274` Sitting Calf Stretch (Dorsiflexion) |
| `wger:1275` Plantarflexion Stretch with Band |
| `wger:537` Incline Bench Press - Dumbbell<br>`wger:1276` Incline Dumbbell Bench Press |
| `wger:1278` Dumbbell Chest Press |
| `wger:1280` Biceps Close Grip Pull Down |
| `wger:1282` Isometria trazioni impugnatura inversa |
| `wger:1283` Incline Chest-Supported Dumbbell Row |
| `wger:1284` Pseudo Planche Push-up |
| `wger:1285` Talons fesses |
| `wger:1286` Dynamic Planche |
| `wger:1287` Reach ups |
| `wger:1288` Planche de cote dynamique |
| `wger:1290` Reverse Grip Barbell Curls |
| `wger:1292` Trazioni impugnatura inversa |
| `wger:1293` One armed push-ups |
| `wger:1294` Arco femorale una gamba |
| `wger:1296` Low-Cable Cross-Over - NB |
| `wger:1298` High-Cable Cross Tricep Extention - NB |
| `wger:1303` Helms Row |
| `wger:1307` Front Plank |
| `wger:1318` High Knee Skips HD |
| `wger:132` Burpees |
| `wger:1320` Bench Dips On Floor HD |
| `wger:1322` Kopfüber Gewichtaufheben |
| `wger:1324` Bodyweight lunge HD |
| `wger:1325` Lateral Push Off |
| `wger:1333` Forearm Curls (underhand grip) |
| `wger:1336` Triceps Overhead (Dumbbell) |
| `wger:1338` Schoulder Raise (Dumbbell) |
| `wger:1348` Lower Back Extensions |
| `wger:1353` Dumbbell Hex Press |
| `wger:1360` Double Kettlebell Clean and Press |
| `wger:1361` Double Kettlebell Front Squat |
| `wger:1363` Blackroll |
| `wger:137` Butterfly Narrow Grip |
| `wger:1370` Dumbbell Deadlift |
| `wger:1372` Triceps Dips (Assisted) |
| `wger:1373` box jumps |
| `wger:1374` Rotary Torso Machine |
| `wger:1378` Cable Lateral Raises (Single Arm) |
| `wger:1381` Upper Back |
| `wger:1384` Pullover Machine |
| `wger:1387` Hamstring Kicks |
| `wger:1388` Single Leg RDL<br>`wger:1389` Single Leg RDL |
| `wger:139` Butterfly Reverse |
| `wger:1390` Toe Touch |
| `wger:1391` Elephant Walks |
| `wger:1392` Good Morning |
| `wger:1393` Single Leg Hamstring Stretch |
| `wger:1394` Sit & Reach |
| `wger:1395` Crossbody Leg Swings |
| `wger:1396` Standing Pancake |
| `wger:1397` Standing Pancake Good Morning |
| `wger:1398` Hamstring Chokes |
| `wger:1399` Roll Down |
| `wger:1400` Crossbody Hamstring Stretch |
| `wger:1406` Plank-to-Elbow Extension |
| `wger:1410` Plank with Alternating Leg Lift |
| `wger:1411` Heel Touches |
| `wger:1415` Dumbbell Crunches |
| `wger:1425` Toe Taps |
| `wger:1426` Standing Side Crunches |
| `wger:1429` Dumbbell Shoulder Rotations |
| `wger:1430` Plate Pinch Hold |
| `wger:1433` Reverse Wood Chops |
| `wger:1434` Lat Pull DB |
| `wger:1435` Scapula Pulls |
| `wger:1436` Pin Bench Press BB |
| `wger:1437` Pin Squat |
| `wger:1439` Pin OHP |
| `wger:1440` Push OHP |
| `wger:1441` Incline OHP DB |
| `wger:1442` Kreis Press DB |
| `wger:1443` Shoulder Raise Side and Front DB |
| `wger:1444` Incline Chest Press DB |
| `wger:1445` Jerk OL |
| `wger:1446` Clean and Jerk OL |
| `wger:1447` Snatch OL |
| `wger:1448` Seated W Curl |
| `wger:1449` ClimbMill |
| `wger:145` Cable Woodchoppers |
| `wger:1450` Cobra Stretch |
| `wger:1451` Torso rotation stretch |
| `wger:1452` Knee to Chest Stretch |
| `wger:1455` Towel Superman |
| `wger:1457` Cable Press Around |
| `wger:1458` Cross-Body Cable Y-Raise |
| `wger:1461` No Leg Drive Dumbbell Chest Press |
| `wger:1462` punches |
| `wger:1463` Dumbbell Underhand Dead Row |
| `wger:1464` Pause Hack Squats |
| `wger:1465` Spider Curl |
| `wger:1466` Calf Raise using Hack Squat Machine |
| `wger:1467` Incline Close Grip Barbell Bench Press |
| `wger:1468` Floor Skull Crusher |
| `wger:1469` Bent over Cable Flye |
| `wger:1470` 1-Arm Half-Kneeling Lat Pulldown |
| `wger:1471` Kroc Row |
| `wger:1472` Cable Shrug-In |
| `wger:1473` Reverse Cable Flye |
| `wger:1474` W-Raise |
| `wger:1475` Black Widow Knee Slides |
| `wger:1476` Butterfly Sit Up |
| `wger:1477` Seated Corkscrew |
| `wger:1478` Levitation Crunch |
| `wger:1479` Sit Up Elbow Thrust |
| `wger:148` Calf Raises on Hackenschmitt Machine |
| `wger:1480` Lying Triceps Extensions |
| `wger:1481` Drag Pushdown |
| `wger:1482` Dumbbell Cheat Curl |
| `wger:1483` Bizeps Curls Trifecta |
| `wger:1484` Omni Cable Cross-over |
| `wger:1485` Rocking Triceps Pushdown |
| `wger:1486` Alternating High Cable Row |
| `wger:1487` Hyper Y W Combo |
| `wger:1488` Dumbbell Pullover |
| `wger:1489` Plank Jacks |
| `wger:1490` Lying Triceps Kickback |
| `wger:1491` Remada unilateral no cabo |
| `wger:1492` High Row |
| `wger:1493` Bayesian Curl |
| `wger:590` Sitting Calf Raises<br>`wger:1494` Sitting Calf Raises |
| `wger:1496` DB Upper Chest Variation |
| `wger:1497` DB Underhand bench press |
| `wger:1498` Elbows Tucked DB Bench Press |
| `wger:1499` DB Skull Crushers |
| `wger:1500` DB UCV |
| `wger:1501` Alternative DB Gorilla rows |
| `wger:1503` Dumbbell Frog Press |
| `wger:1504` Dumbbell Bradford press |
| `wger:1508` High-Incline Smith Machine Press |
| `wger:1509` Cable Tricep Kickback |
| `wger:1510` Neutral Grip Lat Pulldown |
| `wger:1511` Kong Curl |
| `wger:1512` Drop Curl |
| `wger:1514` Lateral Walk |
| `wger:1515` Leg Press Toe Press |
| `wger:1516` Handstand |
| `wger:1519` Overhead Triceps Extension |
| `wger:1521` Pendular hack |
| `wger:1524` Battle Ropes |
| `wger:1525` Ball Slams |
| `wger:1526` Ski Machine |
| `wger:1527` Pendulum Squat |
| `wger:1528` Glute Drive |
| `wger:1529` Toes to bar |
| `wger:1530` Lying Dumbbell Curls |
| `wger:1531` Cable Curls |
| `wger:1535` lying bicep curl |
| `wger:1536` Delt Stretch |
| `wger:1537` Pull-up Isometric Hold |
| `wger:1542` Wide Pull Up |
| `wger:1545` Archer Pull Up |
| `wger:1546` Larsen Press |
| `wger:1548` Stair Master<br>`wger:1549` Stair Master |
| `wger:1554` Clap Push-UP |
| `wger:1556` Devil’s Press |
| `wger:1567` Alternating dumbbell hammer curl |
| `wger:1573` Ab wheel |
| `wger:1574` Schwimmen |
| `wger:1575` Standing Dowel Shoulder press |
| `wger:1576` Snap Down |
| `wger:1577` Bretzel stretch |
| `wger:1578` Hip hinge |
| `wger:1579` Bronco |
| `wger:158` Close-grip Lat Pull Down |
| `wger:1580` Perpendicular Unilateral Landmine Row |
| `wger:1581` Trap press |
| `wger:1582` Side-laying interior rotation |
| `wger:1583` Supine press |
| `wger:1584` March or jog in place |
| `wger:1589` Estiramiento de piernas y cadera |
| `wger:1590` Estiramiento de brazos y cuello |
| `wger:1591` Respiración profunda (de pie o sentado) |
| `wger:1592` Meditación guiada o libre |
| `wger:1593` Smith Machine Split Squat<br>`wger:1594` Smith Machine Split Squat |
| `wger:1602` Dumbbell Scaption |
| `wger:1603` Leg curl with elastic |
| `wger:1604` Sliding Lateral Lunge |
| `wger:1605` Copenhagen Adduction Exercise |
| `wger:1606` Arm Raises (T/Y/I) |
| `wger:1607` Typewriter Pull-ups |
| `wger:1608` Bodyweight Biceps Curl |
| `wger:161` Cross-Bench Dumbbell Pullovers |
| `wger:1612` kettlebell sumo deadlift |
| `wger:1613` rubber band glute kickback |
| `wger:1614` Dumbbell Hip Thrust |
| `wger:1615` Treadmill Cardio |
| `wger:1616` Patada de burro con mancuerna |
| `wger:1618` Cardio en bicicleta estática |
| `wger:1620` Seated Dumbbell Calf Raise |
| `wger:1621` Unilateral Cable row<br>`wger:1636` Unilateral Cable row |
| `wger:1630` Blaze |
| `wger:1634` Rope Pullover/row |
| `wger:1635` Modified pulldown |
| `wger:1637` Single arm row |
| `wger:1638` Barbell Clean and press |
| `wger:1639` Dumbbell Bent Over Face Pull |
| `wger:1640` Dumbbell Front Squat |
| `wger:1641` Kettlebell One Legged Deadlift |
| `wger:1645` Dumbbell Shrug |
| `wger:1648` Weighted Crunch |
| `wger:1653` Dumbbell Side Squat |
| `wger:1654` Machine lateral wise |
| `wger:1655` Machine Chest Press Exercise<br>`wger:1883` Machine Chest Press |
| `wger:1656` Cable Chest Press - Decline |
| `wger:1657` Preacher Curl - Internally Rotated |
| `wger:1658` Preacher Curl - Externally Rotated |
| `wger:1659` Lat Pulldown - Cross Body Single Arm |
| `wger:1661` Cable Triceps Press |
| `wger:1662` Cable Tri Extension - Internal Rotation |
| `wger:1665` Cable Tri Extension - External Rotation |
| `wger:1666` Curl  - With Shoulder Elevated |
| `wger:1668` One Arm Overhead Cable Tricep Extension |
| `wger:1670` Leg Swings (Front–Back) |
| `wger:1672` Seated Hip Abduction |
| `wger:1679` Wall Angels |
| `wger:1680` seated figure four |
| `wger:1684` Dumbbell Thruster |
| `wger:1686` Glute Bridge Single-Arm Press |
| `wger:1687` Bear crawl pull through |
| `wger:1688` Kickstand RDL |
| `wger:1689` Cable Fly Middle Chest |
| `wger:1690` Cable Fly Upper Chest |
| `wger:1691` Cable Fly Lower Chest |
| `wger:1692` Incline Smith Press |
| `wger:1693` Incline Static Hold |
| `wger:1694` Flat Machine Press |
| `wger:1695` Pull-Ups (Wide Grip)<br>`wger:1765` Pull-Ups (Wide Grip)<br>`wger:1880` Wide Grip Pull Up |
| `wger:1698` Barbell Row (Overhand) |
| `wger:1699` Barbell Row (Underhand) |
| `wger:1700` Barbell Romanian Deadlift (RDL) |
| `wger:1702` Jalón al pecho con agarre ancho |
| `wger:1703` Patadas traseras |
| `wger:1704` Tuck L-sit |
| `wger:1706` Bulgarian Squat with Dumbbells |
| `wger:1707` Elevación lateral polea |
| `wger:1709` Reverse Fly Standing |
| `wger:171` Incline Crunches |
| `wger:1710` Butchers Block Stretch |
| `wger:1711` Sleeper Stretch |
| `wger:1712` Horizontal Shoulder Flexion Stretch |
| `wger:1713` Doorway Pectoral Stretch |
| `wger:1714` Shoulder Dumbbell Pendular Exercise |
| `wger:1715` Shoulder External Rotation with Dumbbell |
| `wger:1716` Incline Shoulder Press Up |
| `wger:1717` Neck extension |
| `wger:1718` Remo alto polea alta |
| `wger:1719` Jalon caballero unialteral |
| `wger:172` Crunches on Machine |
| `wger:1724` Standing Adduction (Cable) |
| `wger:1725` Seated Row (Machine)<br>`wger:1770` Seated machine row |
| `wger:1727` Side Straight-Arm Pulldown (Cable) |
| `wger:1728` Shoulder Internal Rotation (Cable) |
| `wger:1729` Shoulder External Rotation (Cable) |
| `wger:1730` Side Lateral Raise (Cable) |
| `wger:1732` Face pulls with yellow/green band |
| `wger:1733` Isometric Squat to Failure |
| `wger:1734` Single-Leg Lunge with Kettlebell: |
| `wger:1735` Single-leg side glute press |
| `wger:1736` Single-Leg Deadlift with Dumbbell |
| `wger:1737` Assisted chin-ups |
| `wger:1738` Neutral-grip pull-ups or TRX rows |
| `wger:1739` Shrimp Squad |
| `wger:174` Crunches With Legs Up |
| `wger:1741` L-Sit Pull-ups |
| `wger:1742` Back Lever |
| `wger:1743` Windshield Wipers |
| `wger:1744` Machine Side Lateral Raises |
| `wger:1745` Cable Front Raise with a small bar |
| `wger:1746` Floor dumbbell bench press |
| `wger:1752` Side lateral raise - Front (Cable) |
| `wger:1753` Side lateral raise - Back (Cable) |
| `wger:1754` 45° lateral raises |
| `wger:1755` Shoulder Y-pull cable |
| `wger:1757` supino<br>`wger:1763` supino |
| `wger:1766` Plank Reach |
| `wger:1768` bicep |
| `wger:1769` cabel |
| `wger:177` Cycling |
| `wger:1773` Legend Incline Bench Press |
| `wger:1774` Chair dips |
| `wger:1775` Pec deck rear delt fly |
| `wger:1776` Suitcase Carry |
| `wger:1777` Deficit Push ups |
| `wger:1778` Supino inclinado<br>`wger:1793` Supino Inclinado |
| `wger:1779` Landmine Rotation |
| `wger:178` Deadbug |
| `wger:1795` unilateral cross body cable pull down |
| `wger:1798` Supino |
| `wger:1800` Supino Inclinado |
| `wger:1803` Trap Bar Squat |
| `wger:1804` ankle dorsiflexion rocks |
| `wger:1806` Lat Pull Down |
| `wger:1807` Behind the Back Cable Lateral Raise |
| `wger:1808` Parallel Bar Hold |
| `wger:1809` Reverse Hyperextension |
| `wger:1810` Sphinx |
| `wger:182` Deadhang |
| `wger:1822` Open Book |
| `wger:1824` Dumbell Tate Press |
| `wger:1825` Chest-Supported Rear Delt Raise |
| `wger:1826` Band pull-apart with external rotation |
| `wger:1827` Double-Leg Abdominal Press |
| `wger:1828` Abdominal Draw-In |
| `wger:1829` Landmine Squat to Press |
| `wger:1830` Barbell Step Back Lunge |
| `wger:1831` Hammerstrength Decline Chest Press |
| `wger:1832` Ring Support Hold |
| `wger:1833` Floor Glider Hamstring Curls |
| `wger:1834` Trap-3 Raise |
| `wger:1835` External Rotation Stretch |
| `wger:1838` Banded Shoulder Drills |
| `wger:1839` Solo Hip Flexor Stretch<br>`wger:1867` Hip Flexor Stretch |
| `wger:1840` Bent-Leg Hamstring Stretch |
| `wger:1841` Seated Shoulder Extension Stretch |
| `wger:1844` Frog Stretch |
| `wger:1845` Seated Pancake Good Morning |
| `wger:1846` Horse Stance (Side Splits) |
| `wger:1847` Straddle L-Sit |
| `wger:1852` L-sit |
| `wger:1853` L-Sit (Foot Supported) |
| `wger:1854` Calves foam roller |
| `wger:1855` Hamstring Foam roller |
| `wger:1856` Foam Roller Anterior tibialis |
| `wger:1857` Foam Roller Iliotibial band |
| `wger:1858` Foam Roller quadriceps |
| `wger:1859` Foam Roller Gluteus |
| `wger:1860` Foam Roller Adductors |
| `wger:1861` Side stretch |
| `wger:1862` Hip Circles |
| `wger:1863` Hip Crossover |
| `wger:1864` Ankle Roll |
| `wger:1865` Banded Ankle Mobility |
| `wger:1868` Lunge with Twist Stretch |
| `wger:1869` Lying Figure Four Stretch |
| `wger:1870` Lying Hamstring Stretch with Band |
| `wger:1871` Lying Knee to Chest Stretch |
| `wger:1872` Pigeon Stretch |
| `wger:1874` Runners Lunge Stretch |
| `wger:1875` Standing IT Band Stretch |
| `wger:1876` Supported Calf Stretch |
| `wger:1877` Banded Scapular Retraction |
| `wger:1879` Incline DB Y-Raise |
| `wger:1882` High-Cable Lateral Raise |
| `wger:1884` Shinbox IR Stretch |
| `wger:1885` YTWL Exercise |
| `wger:1886` Supine Hip Abduction |
| `wger:1889` Decline Bench Leg Raise |
| `wger:1903` Walking Lunges |
| `wger:1905` Pullback |
| `wger:1906` Hip Bridge |
| `wger:1907` Unilateral Lunges |
| `wger:1908` Butterfly Superman |
| `wger:1909` Leg Wheel |
| `wger:1910` Kneeling Superman |
| `wger:1911` Cat Plank |
| `wger:1912` Core Rotation |
| `wger:1913` Unilateral Hip Thrust |
| `wger:1914` Isometria alle parallele |
| `wger:1915` Quadruped Hip Abduction |
| `wger:1916` Tuck planche |
| `wger:1919` Extreme Pec Stretch |
| `wger:1920` Extreme Shoulder Stretch |
| `wger:1921` Extreme Lat Stretch |
| `wger:1922` Seated Cable chest fly |
| `wger:1924` 3008 Abdominal Crunch |
| `wger:1925` Barbell Silverback Shrug |
| `wger:1927` Inverted Lat Pull Down |
| `wger:1928` Seated V-Grip Row |
| `wger:193` Diagonal Shoulder Press |
| `wger:1931` Dumbbell Curl |
| `wger:1933` Abdominal Crunch |
| `wger:1936` Cable Rear-Delt Fly (single arm) |
| `wger:194` Dips |
| `wger:197` Dips Between Two Benches |
| `wger:20` Arnold Shoulder Press |
| `wger:205` Dumbbell Lunges Standing |
| `wger:208` Dumbbells on Scott Machine |
| `wger:211` Dumbbell Triceps Extension |
| `wger:222` Facepull |
| `wger:238` Fly With Dumbbells |
| `wger:239` Fly With Dumbbells, Decline Bench |
| `wger:245` Skullcrusher Dumbbells |
| `wger:256` Front Raises |
| `wger:258` Front pull wide |
| `wger:259` Front Pull narrow |
| `wger:260` Full Sit Outs |
| `wger:275` Hammercurls on Cable |
| `wger:279` Hand Grip |
| `wger:282` Handstand Pushup |
| `wger:284` Hercules Pillars |
| `wger:285` High Knee Jumps |
| `wger:289` High Pull |
| `wger:291` Hindu Squats |
| `wger:292` Hip Raise, Lying |
| `wger:297` Hollow Hold |
| `wger:301` Hyperextensions |
| `wger:31` Axe Hold |
| `wger:312` Incline Plank With Alternate Floor Touch |
| `wger:319` Jogging |
| `wger:323` Cable Cross-over |
| `wger:341` Squats on Multipress |
| `wger:349` Lateral Rows on Cable, One Armed |
| `wger:351` Lateral-to-Front Raises |
| `wger:354` Lat Pull Down (Leaning Back) |
| `wger:355` Lat Pull Down (Straight Back) |
| `wger:365` Leg Curls (laying) |
| `wger:366` Leg Curls (sitting) |
| `wger:374` Leg Presses (wide) |
| `wger:375` Leg Press on Hackenschmidt Machine |
| `wger:376` Leg Raise |
| `wger:378` Leg Raises, Standing |
| `wger:382` L Hold |
| `wger:386` Diamond push ups |
| `wger:394` Long-Pulley (low Row) |
| `wger:395` Long-Pulley, Narrow |
| `wger:397` Low Box Squat - Wide Stance |
| `wger:406` Lying Rotator Cuff Exercise |
| `wger:418` Military Press mit SZ-Bar |
| `wger:423` Muscle up |
| `wger:427` Negative Crunches |
| `wger:439` Overhand Cable Curl |
| `wger:445` Pause Bench |
| `wger:448` Pendelay Rows |
| `wger:454` Pike Push Ups |
| `wger:46` Barbell Lunges Standing |
| `wger:465` Preacher Curls |
| `wger:468` Prone Scapular Retraction - Arms at Side |
| `wger:477` Pull Ups on Machine |
| `wger:478` Push Press |
| `wger:48` Barbell Reverse Wrist Curl |
| `wger:484` Rack Deadlift |
| `wger:487` Rear Delt Raises<br>`wger:829` Rear Delt Raise |
| `wger:490` Renegade Row |
| `wger:493` Reverse Bar Curl |
| `wger:498` Reverse Grip Bench Press |
| `wger:50` Barbell Triceps Extension |
| `wger:500` Reverse Plank |
| `wger:505` Roman Chair |
| `wger:51` Barbell Wrist Curl |
| `wger:510` Rowing, Lying on Bench |
| `wger:512` Rowing seated, narrow grip |
| `wger:513` Rowing, T-bar |
| `wger:516` Front Wood Chop |
| `wger:84` Bent Over Rowing Reverse<br>`wger:525` Bent Over Rowing Reverse |
| `wger:527` Run |
| `wger:529` Run - Interval Training |
| `wger:530` Run - Treadmill |
| `wger:545` Scissors |
| `wger:56` Abdominal Stabilization |
| `wger:567` Shoulder Press, Dumbbells |
| `wger:569` Shoulder Press, on Multi Press |
| `wger:57` Bear Walk 2 |
| `wger:570` Shoulder Shrug |
| `wger:571` Shrugs, Barbells |
| `wger:572` Shrugs, Dumbbells |
| `wger:575` Shrugs on Multipress |
| `wger:576` Side Crunch |
| `wger:577` Side Dumbbell Trunk Flexion |
| `wger:578` Side-lying External Rotation |
| `wger:583` Side to Side Push Ups |
| `wger:584` Single-arm Preacher Curl |
| `wger:595` Skipping - Standard |
| `wger:599` Snach |
| `wger:604` Speed Deadlift |
| `wger:607` Splinter Sit-ups |
| `wger:616` Squat Thrust |
| `wger:621` Standing Bicep Curl |
| `wger:623` Standing Rope Forearm |
| `wger:624` Stationary Bike |
| `wger:628` Straight-arm Pull Down (bar Attachment) |
| `wger:629` Straight-arm Pull Down (rope Attachment) |
| `wger:632` Sumo Squats |
| `wger:650` Thruster |
| `wger:659` Triceps Extensions on Cable |
| `wger:660` Triceps Extensions on Cable With Bar |
| `wger:661` Triceps on Machine |
| `wger:672` Trunk Rotation With Cable |
| `wger:674` Rowing with TRX band |
| `wger:675` Turkish Get-Up |
| `wger:683` Power Clean |
| `wger:684` Underhand Lat Pull Down |
| `wger:688` Upper External Oblique |
| `wger:691` Upright Row, on Multi Press |
| `wger:693` Upright Row, SZ-bar |
| `wger:694` Upright Row w/ Dumbbells |
| `wger:702` Calf raises, one legged |
| `wger:711` Wall Handstand |
| `wger:713` Wall Pushup |
| `wger:716` Wall Slides |
| `wger:718` Wall Squat |
| `wger:722` Weighted Step-ups |
| `wger:723` Wide-grip Pulldown |
| `wger:75` Benchpress Dumbbells |
| `wger:76` Bench Press Narrow Grip |
| `wger:79` Bent High Pulls |
| `wger:801` Dumbbell Push-Up |
| `wger:804` Sloper hanging |
| `wger:82` Bent-over Lateral Raises |
| `wger:820` Fingerboard 20 mm edge |
| `wger:821` Pullup on fingerboard |
| `wger:828` Incline Bench Reverse Fly |
| `wger:83` Bent Over Rowing |
| `wger:9` 2 Handed Kettlebell Swing |
| `wger:908` Zone 2 Running |
| `wger:909` Reverse Nordic Curl |
| `wger:91` Biceps Curls With Barbell |
| `wger:910` Nordic Curl |
| `wger:911` Incline Skull Crush |
| `wger:912` Straight Bar Cable Curls |
| `wger:913` Reverse Preacher Curl (Close Grip) |
| `wger:914` Reverse EZ Bar Cable Curls |
| `wger:915` BUS DRIVERS |
| `wger:916` Smith Press |
| `wger:917` Straight Bar Cable Front Raise |
| `wger:922` SEATED CABLE MID TRAP SHRUG |
| `wger:923` LYING DUMBBELL ROW SS SEATED SHRUG |
| `wger:925` SMITH MACHINE SLIGHT INCLINE PRESS |
| `wger:926` Machine chest fly |
| `wger:927` Suspended crossess |
| `wger:94` Biceps Curls With SZ-bar |
| `wger:95` Biceps Curl With Cable |
| `wger:957` Quadriped Arm and Leg Raise |
| `wger:958` Biceps with TRX |
| `wger:959` TRX Rows |
| `wger:960` Kettlebell Swing |
| `wger:961` Swimming 50m sprints |
| `wger:962` Elliptical |
| `wger:974` Curl with kettlebell two hands |
| `wger:975` one-handed kettlebell curls |
| `wger:976` Medicine ball booklet crunch |
| `wger:977` Box squat |
| `wger:978` Knee Raises |
| `wger:979` Leg raises pull up bar |
| `wger:980` commando pull-ups |
| `wger:981` Step-ups |
| `wger:984` Lunges |
| `wger:985` Push-up rotations |
| `wger:986` Side split squats left |
| `wger:987` Side split squats right |
| `wger:988` Bulgarian split squats left |
| `wger:989` Bulgarian split squats right |
| `wger:990` Kneeling kickbacks |
| `wger:991` Split squats left |
| `wger:992` Split squats right |
| `wger:993` Jump rope: basic jumps |
| `wger:994` Forward arm circles |
| `wger:995` Backward arm circles |
| `wger:996` Mountain climbers |
| `wger:997` 4-count burpees |
| `wger:998` No push-up burpees |
| `wger:999` Reverse lunges |
