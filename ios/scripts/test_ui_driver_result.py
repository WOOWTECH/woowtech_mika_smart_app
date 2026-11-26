import unittest
from scripts.ui_driver_result import failure_reason


class UIDriverResultTests(unittest.TestCase):
    steps = ["launch", "waitfor chat.draft 30"]
    complete = "step 1: launch\nstep 2: waitfor chat.draft 30\nCOMPLETED: 2 steps"

    def test_complete_native_run(self):
        self.assertIsNone(failure_reason(0, self.steps, self.complete))

    def test_failed_truncated_reordered_and_empty_runs_are_rejected(self):
        for code, steps, log in [
            (65, self.steps, self.complete),
            (0, self.steps, self.complete + "\nFAILED: missing button"),
            (0, self.steps, "step 1: launch"),
            (0, self.steps, self.complete.replace("COMPLETED: 2 steps", "")),
            (0, self.steps, self.complete.replace("step 1: launch", "step 1: terminate")),
            (0, self.steps, "step 2: waitfor chat.draft 30\nstep 1: launch\nCOMPLETED: 2 steps"),
            (0, [], "COMPLETED: 0 steps"),
            (0, self.steps, ""),
        ]:
            with self.subTest(code=code, log=log):
                self.assertIsNotNone(failure_reason(code, steps, log))


if __name__ == "__main__":
    unittest.main()
