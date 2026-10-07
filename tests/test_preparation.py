"""Consequential date and identifier edge cases; no duplicated analysis tests."""
import importlib.util
from datetime import datetime
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("prepare_data", Path(__file__).resolve().parents[1] / "src/prepare_data.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PreparationEdges(unittest.TestCase):
    def test_datetime_swap(self):
        value, corrected, rule, issue = module.normalize_date(datetime(2010,3,8),8)
        self.assertEqual(value.isoformat(), "2010-08-03")
        self.assertTrue(corrected)
        self.assertFalse(issue)

    def test_agreeing_and_symmetric_datetime_retained(self):
        for value in [datetime(2011,5,5),datetime(2011,5,9)]:
            result, corrected, _, issue = module.normalize_date(value,5)
            self.assertEqual(result,value.date())
            self.assertFalse(corrected)
            self.assertFalse(issue)

    def test_day_first_leap_date(self):
        value, corrected, _, issue = module.normalize_date("29-02-2012",2)
        self.assertEqual(value.isoformat(),"2012-02-29")
        self.assertFalse(corrected)
        self.assertFalse(issue)

    def test_unresolved_values_are_not_guessed(self):
        for value, month in [("29-02-2011",2),("08-03-2010",8),(datetime(2010,3,9),8),
                             ("2010-08-03",8),(datetime(2010,8,3),None),(datetime(2010,8,3),8.5),
                             (datetime(2010,8,3,1),8)]:
            result, _, rule, issue = module.normalize_date(value,month)
            self.assertIsNone(result)
            self.assertEqual(rule,"unresolved")
            self.assertTrue(issue)

    def test_identifier_zeroes_and_numeric_formats(self):
        self.assertEqual(module.identifier_text(" 00123 "),"00123")
        self.assertEqual(module.identifier_text(123,"00000"),"00123")
        self.assertEqual(module.identifier_text(123),"123")
        self.assertEqual(module.identifier_text("FGA040B"),"FGA040B")
        with self.assertRaises(ValueError):
            module.identifier_text(123.5)


if __name__ == "__main__":
    unittest.main()
