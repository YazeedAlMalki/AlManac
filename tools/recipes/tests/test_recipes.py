"""Fast tests for the Wikibooks recipe reader and builder. Synthetic pages and
a synthetic ingredient table only; no lake needed.

    cd tools/recipes && python3 -m unittest discover -s tests -t .
"""

import tempfile
import textwrap
import unittest
from pathlib import Path

from almanac_recipes import build, wikitext

PAGE = textwrap.dedent("""\
    {{Recipe summary
    | Category = Pasta recipes
    | Servings = 6
    }}
    == Ingredients ==
    * 8 [[Cookbook:Egg|eggs]]
    * 10 [[Cookbook:Gram|g]] (2 [[Cookbook:Teaspoon|tsp]]) [[Cookbook:Salt|salt]]
    * 1 ½ [[Cookbook:Cup|cups]] [[Cookbook:Onion|onion]], [[Cookbook:Chopping|chopped]]
    * 2 [[Cookbook:Egg|egg]] yolks
    * 4 cloves garlic, minced
    * 1 can (400 grams) chopped tomatoes
    * [[Cookbook:Black Pepper|Pepper]], to taste
    * A pinch of nutmeg
    == Procedure ==
    # Mix.
    [[Category:Recipes using egg]]
    """)

TABLE = textwrap.dedent("""\
    aliases,food_ref,usda_fdc,volume,each,seasoning,exclude
    egg;eggs,ex:egg,1,cup (4.86 large eggs),large,,
    egg yolk;egg yolks,ex:yolk,2,,large,,
    salt,ex:salt,3,tsp,,y,
    onion;onions,ex:onion,4,"cup, chopped",medium,,
    garlic,ex:garlic,5,,clove,,
    canned tomatoes;tomatoes,ex:tomato,,,,,
    black pepper;pepper,ex:pepper,,,,y,
    nutmeg,ex:nutmeg,,,,y,
    bacon,ex:bacon,,,,,pork
    """)

PORTIONS = {
    "1": [(1.0, "large", 50.0), (1.0, "cup (4.86 large eggs)", 243.0)],
    "2": [(1.0, "large", 17.0)],
    "3": [(1.0, "tsp", 6.0), (0.5, "tsp", 3.0)],
    "4": [(1.0, "cup, chopped", 160.0), (1.0, "medium (2-1/2\" dia)", 110.0), (1.0, "large", 150.0)],
    "5": [(1.0, "clove", 3.0), (3.0, "cloves", 9.0)],
}
FOODS = {ref: ref for ref in ["ex:egg", "ex:yolk", "ex:salt", "ex:onion", "ex:garlic", "ex:tomato",
                              "ex:pepper", "ex:nutmeg", "ex:bacon"]}


def index():
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "ingredients.csv"
        path.write_text(TABLE)
        found, problems = build.load_ingredients(path, PORTIONS, FOODS)
    assert not problems, problems
    return found


class WikitextTests(unittest.TestCase):
    def test_servings_and_lines(self):
        page = wikitext.parse("Cookbook:Test", PAGE)
        self.assertEqual(page.name, "Test")
        self.assertEqual(page.servings, 6)
        self.assertEqual(len(page.lines), 8)
        eggs = page.lines[0]
        self.assertEqual((eggs.amount, eggs.unit, eggs.ingredient), (8.0, "each", "egg"))

    def test_bracketed_alternative_is_not_the_ingredient(self):
        salt = wikitext.parse("Cookbook:Test", PAGE).lines[1]
        self.assertEqual((salt.amount, salt.unit, salt.ingredient), (10.0, "g", "salt"))

    def test_mixed_fraction(self):
        onion = wikitext.parse("Cookbook:Test", PAGE).lines[2]
        self.assertEqual((onion.amount, onion.unit, onion.ingredient), (1.5, "cup", "onion"))

    def test_stated_weight_of_a_count(self):
        can = wikitext.parse_line("* 1 can (400 grams) chopped tomatoes")
        self.assertEqual((can.amount, can.unit), (400.0, "g"))

    def test_range_is_its_midpoint(self):
        line = wikitext.parse_line("* 2–3 [[Cookbook:Tablespoon|tbsp]] oil")
        self.assertEqual((line.amount, line.unit, line.is_range), (2.5, "tbsp", True))

    def test_a_range_of_servings_is_no_count(self):
        self.assertIsNone(wikitext.servings("| Servings = 4–6\n"))
        self.assertIsNone(wikitext.servings("| Servings = 1 loaf\n"))


class BuildTests(unittest.TestCase):
    def test_every_line_resolves_or_is_set_aside(self):
        out = build.build_recipe(wikitext.parse("Cookbook:Test", PAGE), index())
        self.assertEqual(out.failures, [])
        grams = {c["ref"]: c["grams"] for c in out.components}
        self.assertEqual(grams["ex:egg"], 400.0)        # 8 × large 50 g
        self.assertEqual(grams["ex:salt"], 10.0)        # the stated grams, not the teaspoons
        self.assertEqual(grams["ex:onion"], 240.0)      # 1.5 × "cup, chopped" 160 g
        self.assertEqual(grams["ex:yolk"], 34.0)        # "egg yolks" is not "egg"
        self.assertEqual(grams["ex:garlic"], 12.0)      # 4 × clove 3 g
        self.assertEqual(grams["ex:tomato"], 400.0)
        self.assertEqual(out.set_aside, ["Pepper, to taste", "A pinch of nutmeg"])

    def test_a_count_of_the_wrong_thing_is_unreadable(self):
        page = wikitext.parse("Cookbook:T", "== Ingredients ==\n* 1 head garlic\n* 2 eggs\n")
        self.assertEqual(build.build_recipe(page, index()).failures, ["1 head garlic"])

    def test_an_unmeasured_ingredient_that_is_not_a_seasoning_is_unreadable(self):
        page = wikitext.parse("Cookbook:T", "== Ingredients ==\n* Onions, chopped\n* 2 eggs\n")
        self.assertEqual(build.build_recipe(page, index()).failures, ["Onions, chopped"])

    def test_size_word_picks_the_measure(self):
        page = wikitext.parse("Cookbook:T", "== Ingredients ==\n* 2 large onions\n")
        self.assertEqual(build.build_recipe(page, index()).components[0]["grams"], 300.0)

    def test_a_recipe_with_one_unreadable_line_is_dropped_and_pork_is_left_out(self):
        pages = [
            {"pageid": 1, "title": "Cookbook:Good",
             "revisions": [{"revid": 9, "slots": {"main": {"content": PAGE}}}]},
            {"pageid": 2, "title": "Cookbook:Bad",
             "revisions": [{"revid": 9, "slots": {"main": {"content":
                 "== Ingredients ==\n* 2 eggs\n* 1 cup mystery\n"}}}]},
            {"pageid": 3, "title": "Cookbook:Bacon and eggs",
             "revisions": [{"revid": 9, "slots": {"main": {"content":
                 "== Ingredients ==\n* 2 eggs\n* 100 g bacon\n"}}}]},
        ]
        bundle, stats = build.build(pages, index(), "test")
        self.assertEqual([r["name"] for r in bundle["recipes"]], ["Good"])
        self.assertEqual(stats["unreadable"], 1)
        self.assertEqual(stats["excluded"], 1)
        recipe = bundle["recipes"][0]
        self.assertEqual(recipe["url"], "https://en.wikibooks.org/wiki/Cookbook:Good")
        self.assertEqual(recipe["servings"], 6)
        self.assertEqual(bundle["licence"], "CC BY-SA 4.0")

    def test_table_problems_fail_the_build(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "ingredients.csv"
            path.write_text("aliases,food_ref,usda_fdc,volume,each,seasoning,exclude\n"
                            "egg,ex:missing,1,cup,large,,\n")
            _, problems = build.load_ingredients(path, PORTIONS, FOODS)
        self.assertTrue(any("not in the nutrition bundle" in p for p in problems))
        self.assertTrue(any("volume portion 'cup'" in p for p in problems))


if __name__ == "__main__":
    unittest.main()
