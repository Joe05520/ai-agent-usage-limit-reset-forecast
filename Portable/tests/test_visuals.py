"""Presentation must interpolate without changing authoritative account values."""
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
import unittest
from PySide6.QtWidgets import QApplication
from PySide6.QtCore import QAbstractAnimation
from sentinel.visuals import QuotaVisual

class VisualTransitionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def test_entrance_and_stop_for_every_presentation(self):
        for style in ('ring', 'battery', 'bar', 'number'):
            with self.subTest(style=style):
                widget = QuotaVisual(72, style, animate=True)
                self.assertEqual(widget.value, 0)
                self.assertEqual(widget.accessibleName(), '72% remaining')
                widget.animation.setCurrentTime(450)
                self.assertGreater(widget.value, 0)
                self.assertLess(widget.value, 72)
                widget.animation.setCurrentTime(widget.animation.duration())
                self.assertEqual(widget.value, 72)
                self.assertEqual(widget.animation.state(), QAbstractAnimation.State.Stopped)

    def test_disabled_animation_and_zero_are_immediate(self):
        for target in (0, 3, 72, 100):
            widget = QuotaVisual(target, animate=False)
            self.assertEqual(widget.value, target)
            self.assertFalse(hasattr(widget, 'animation'))
