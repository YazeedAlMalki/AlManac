import unittest

from almanac_nutrition.values import (NegativeAmount, Qualified, UnrecognisedValue, convert,
                                      parse_decimal, qualify, select)
from tests.support import DICTIONARY

COFID = DICTIONARY.tokens_for("cofid")
CIQUAL = DICTIONARY.tokens_for("ciqual")


class TokensAreNeverZero(unittest.TestCase):
    """The bug the qualifier model exists to prevent (Processing Design v0.1 §2)."""

    def test_cofid_trace_has_no_amount(self):
        self.assertEqual(qualify("Tr", tokens=COFID), Qualified(None, "trace"))

    def test_cofid_n_has_no_amount(self):
        self.assertEqual(qualify("N", tokens=COFID), Qualified(None, "not_analysed"))

    def test_tokens_are_matched_after_trimming(self):
        self.assertEqual(qualify(" Tr ", tokens=COFID).amount, None)

    def test_ciqual_tokens(self):
        self.assertEqual(qualify("traces", tokens=CIQUAL), Qualified(None, "trace"))
        self.assertEqual(qualify("-", tokens=CIQUAL), Qualified(None, "not_analysed"))

    def test_a_token_from_another_source_is_not_recognised(self):
        with self.assertRaises(UnrecognisedValue):
            qualify("Tr", tokens=CIQUAL, decimal_comma=True, bound_prefix="<")

    def test_unknown_cells_fail_rather_than_guess(self):
        for cell in ("x", "(0.07)", "nan", "NaN", "inf", "1e999", "1,2,3", "12 g", "n/a"):
            with self.subTest(cell=cell), self.assertRaises(UnrecognisedValue):
                qualify(cell, tokens=COFID)

    def test_blank_cells_never_reach_qualify(self):
        with self.assertRaises(UnrecognisedValue):
            qualify("   ", tokens=COFID)

    def test_negative_amounts_fail_and_are_never_clamped(self):
        with self.assertRaises(NegativeAmount):
            qualify("-1.5", tokens=COFID)
        self.assertTrue(issubclass(NegativeAmount, UnrecognisedValue))


class Numbers(unittest.TestCase):
    def test_explicit_zero_is_zero_reported(self):
        for cell in ("0", "0.0", "0.00", "-0"):
            with self.subTest(cell=cell):
                self.assertEqual(qualify(cell, tokens=COFID), Qualified(0.0, "zero_reported"))

    def test_decimal_comma(self):
        self.assertEqual(qualify("59,7", tokens=CIQUAL, decimal_comma=True), Qualified(59.7, "measured"))
        self.assertEqual(qualify("0,0", tokens=CIQUAL, decimal_comma=True).qualifier, "zero_reported")

    def test_bound_is_below_loq_with_the_bound_as_amount(self):
        self.assertEqual(qualify("< 0,5", tokens=CIQUAL, decimal_comma=True, bound_prefix="<"),
                         Qualified(0.5, "below_loq"))
        with self.assertRaises(UnrecognisedValue):
            qualify("< 0", tokens=CIQUAL, decimal_comma=True, bound_prefix="<")

    def test_override_beats_derivation_but_not_zero(self):
        self.assertEqual(qualify("384", tokens={}, numeric_override="calculated_factor",
                                 derivation_qualifier="measured"),
                         Qualified(384.0, "calculated_factor"))
        self.assertEqual(qualify("0", tokens={}, numeric_override="calculated_factor").qualifier,
                         "zero_reported")

    def test_derivation_qualifier_applies_to_numbers(self):
        self.assertEqual(qualify("13.2", tokens={}, derivation_qualifier="borrowed"),
                         Qualified(13.2, "borrowed"))
        self.assertEqual(qualify("13.2", tokens={}), Qualified(13.2, "measured"))

    def test_parse_decimal_is_strict(self):
        self.assertEqual(parse_decimal("1e-05"), 1e-05)
        self.assertIsNone(parse_decimal("Tr"))
        self.assertIsNone(parse_decimal("59,7"))
        self.assertEqual(parse_decimal("59,7", decimal_comma=True), 59.7)


class ConversionAndPriority(unittest.TestCase):
    def test_kj_to_kcal(self):
        self.assertAlmostEqual(convert(418.4, "kj_to_kcal"), 100.0)
        self.assertIsNone(convert(None, "kj_to_kcal"))
        self.assertEqual(convert(5.0, ""), 5.0)
        with self.assertRaises(ValueError):
            convert(1.0, "furlongs")

    def test_first_priority_with_a_quantity_wins(self):
        chosen = select([(2, Qualified(10.0, "measured"), "b"), (1, Qualified(None, "not_analysed"), "a")])
        self.assertEqual(chosen[2], "b")
        chosen = select([(2, Qualified(10.0, "measured"), "b"), (1, Qualified(9.0, "measured"), "a")])
        self.assertEqual(chosen[2], "a")

    def test_a_marker_is_kept_when_nothing_has_a_quantity(self):
        chosen = select([(2, Qualified(None, "not_analysed"), "b"), (1, Qualified(None, "not_analysed"), "a")])
        self.assertEqual(chosen[2], "a")
        self.assertIsNone(select([]))


if __name__ == "__main__":
    unittest.main()
