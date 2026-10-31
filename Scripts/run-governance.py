#!/usr/bin/env python3
"""Run governance tests, optionally excluding a module/class by test id."""
import os
import sys
import unittest


def filtered(suite, excludes):
    selected = unittest.TestSuite()
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            selected.addTest(filtered(test, excludes))
        elif not any(token in test.id() for token in excludes):
            selected.addTest(test)
    return selected


def main():
    excludes = [item for item in os.environ.get('MALL_GOVERNANCE_EXCLUDE', '').split(',') if item]
    suite = unittest.defaultTestLoader.discover('Tests/Governance', pattern='test_*.py')
    result = unittest.TextTestRunner(verbosity=2).run(filtered(suite, excludes))
    return 0 if result.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main())
