#!/usr/bin/env python3
import argparse
import os
import sys
from PySide6.QtWidgets import QApplication
from PySide6.QtCore import QTimer
from sentinel.ui import SentinelWindow


def main():
    parser=argparse.ArgumentParser(); parser.add_argument("--mock",action="store_true"); parser.add_argument("--show",action="store_true"); parser.add_argument("--smoke-test",action="store_true"); args=parser.parse_args()
    app=QApplication(sys.argv); app.setApplicationName("Usage Sentinel"); app.setOrganizationName("UsageSentinel"); app.setQuitOnLastWindowClosed(False)
    window=SentinelWindow(mock=args.mock or args.smoke_test)
    if args.show or args.smoke_test: window.show()
    if args.smoke_test:
        def verify():
            window.mock_test()
            assert window.settings["stages"] == [50,30,20,10,5]
            assert any(e["type"] == "accountUnexpected" for e in window.events)
            assert window.state["buckets"][0]["remaining"] == 3
            print("SMOKE PASS: Qt window, settings, usage, reset event and five-stage engine",flush=True); app.quit()
        QTimer.singleShot(1500,verify)
    return app.exec()

if __name__ == "__main__": sys.exit(main())
