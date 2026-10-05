"""Native Qt quota visuals; finite transitions only, no background animation loop."""
from PySide6.QtCore import QVariantAnimation, QEasingCurve, QRectF, Qt
from PySide6.QtGui import QPainter, QPen, QPalette, QFont
from PySide6.QtWidgets import QWidget

class QuotaVisual(QWidget):
    def __init__(self, remaining, style='ring', animate=False, previous=None, parent=None):
        super().__init__(parent)
        self.value = max(0., min(100., remaining))
        self.style = style
        self.setMinimumSize(110, 84)
        self.setAccessibleName(f'{self.value:g}% remaining')
        if animate and previous is not None and previous != self.value:
            end = self.value
            self.animation = QVariantAnimation(self)
            self.animation.setDuration(450)
            self.animation.setStartValue(max(0., min(100., previous)))
            self.animation.setEndValue(end)
            self.animation.setEasingCurve(QEasingCurve.Type.InOutCubic)
            self.animation.valueChanged.connect(self.frame)
            self.animation.start()

    def frame(self, value):
        self.value = float(value)
        self.update()

    def paintEvent(self, event):
        painter = QPainter(self); painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        palette = self.palette(); accent = palette.color(QPalette.ColorRole.Highlight)
        track = palette.color(QPalette.ColorRole.Mid)
        x = (self.width() - 72) / 2
        if self.style == 'battery':
            rect = QRectF(x, 23, 72, 38)
            painter.setPen(QPen(track, 2)); painter.drawRoundedRect(rect, 6, 6)
            painter.fillRect(QRectF(x+4, 27, 64*self.value/100, 30), accent)
            painter.fillRect(QRectF(x+73, 35, 4, 14), track)
        else:
            rect = QRectF(x, 6, 72, 72)
            painter.setPen(QPen(track, 7)); painter.drawEllipse(rect)
            painter.setPen(QPen(accent, 7, Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap))
            painter.drawArc(rect, 90*16, -round(self.value*3.6*16))
        painter.setPen(palette.color(QPalette.ColorRole.Text)); font = QFont(self.font()); font.setPointSize(14); font.setBold(True); painter.setFont(font)
        painter.drawText(QRectF(x, 6, 72, 72), Qt.AlignmentFlag.AlignCenter, f'{round(self.value)}%')
