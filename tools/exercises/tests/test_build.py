import unittest

from almanac_exercises.build import Row, build_library, cluster, tokens


def row(source, id, name, muscle="Biceps", equipment="Dumbbell", graphic="g.png"):
    return Row(source, id, name, muscle, equipment, graphic=graphic, licence_group="cc0")


class MatchTests(unittest.TestCase):
    def test_names_normalise(self):
        self.assertEqual(tokens("Push-Ups"), tokens("pushup"))
        self.assertEqual(tokens("Dumbbell Bicep Curls"), tokens("Bicep Curl"))
        self.assertNotEqual(tokens("Weighted Push-up"), tokens("Push-up"))

    def test_same_unsure_and_apart(self):
        rows = [row("workout-guide", "wg", "Bicep Curl"),
                row("free-exercise-db", "f1", "Dumbbell Bicep Curl"),
                row("wger", "w1", "Incline Dumbbell Curl"),            # variation word
                row("wger", "w2", "Bicep Curl", equipment="Cable"),   # other equipment
                row("wger", "w3", "Bicep Curl HD", equipment=None)]   # neutral word, unsure
        groups, matches, _ = cluster(rows)
        merged = next(g for g in groups if any(r.id == "wg" for r in g))
        self.assertEqual({r.id for r in merged}, {"wg", "f1", "w3"})
        self.assertEqual({m["kind"] for m in matches}, {"same", "unsure"})

    def test_unstated_equipment_cannot_chain_two_kinds(self):
        rows = [row("free-exercise-db", "a", "Curl"),
                row("wger", "b", "Curl", equipment=None),
                row("free-exercise-db", "c", "Curl", equipment="Machine")]
        groups, _, _ = cluster(rows)
        self.assertFalse(any({"a", "c"} <= {r.id for r in g} for g in groups))

    def test_named_equipment_counts_when_unstated(self):
        rows = [row("free-exercise-db", "a", "Biceps Curl"),
                row("wger", "b", "Biceps Curl With Cable", equipment=None)]
        groups, _, _ = cluster(rows)
        self.assertEqual(len(groups), 2)

    def test_two_workout_guide_rows_are_never_merged(self):
        rows = [row("workout-guide", "a", "Curl"), row("workout-guide", "b", "Curls")]
        groups, _, kept_apart = cluster(rows)
        self.assertEqual(len(groups), 2)
        self.assertEqual(len(kept_apart), 1)


class LibraryTests(unittest.TestCase):
    def test_conflict_keeps_both_values_and_graphicless_rows_are_held(self):
        guide = [row("workout-guide", "wg", "Hammer Curl", muscle="Biceps")]
        fedb = [row("free-exercise-db", "f", "Hammer Curls", muscle="Forearms")]
        wger = [row("wger", "w", "Zottman Curl", graphic=None)]
        records, _, held, _ = build_library(guide, fedb, wger)
        self.assertEqual(len(records), 1)
        rec = records[0]
        self.assertNotIn("insert", rec)  # the shipped workout-guide row stays the record
        self.assertEqual(len(rec["sources"]), 2)
        self.assertEqual(rec["conflicts"][0]["field"], "primaryMuscle")
        self.assertEqual({v["value"] for v in rec["conflicts"][0]["values"]}, {"Biceps", "Forearms"})
        self.assertEqual([[r.id for r in m] for m in held], [["w"]])

    def test_new_record_takes_free_exercise_db_as_base(self):
        records, _, _, _ = build_library(
            [], [row("free-exercise-db", "f", "Spider Curl")], [row("wger", "w", "Spider Curls", graphic=None)])
        self.assertEqual(records[0]["sourceId"], "free-exercise-db")
        self.assertEqual(records[0]["insert"]["graphicPath"], "free-exercise-db/f.jpg")


if __name__ == "__main__":
    unittest.main()
