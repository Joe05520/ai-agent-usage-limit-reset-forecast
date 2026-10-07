import json
from pathlib import Path
import sys
import time
from datetime import datetime
from PySide6.QtCore import Qt, QTimer, QObject, QRunnable, QThreadPool, Signal, QUrl
from PySide6.QtGui import QIcon, QDesktopServices, QColor, QPainter, QPixmap, QFont
from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QTabWidget, QSystemTrayIcon, QMenu, QProgressBar, QScrollArea, QComboBox, QCheckBox, QSpinBox, QLineEdit, QFileDialog, QMessageBox, QTextBrowser, QFormLayout)
from . import __version__, core, autostart, extensions
from .i18n import Translator, LANGUAGES
from .storage import Database, data_dir
from .visuals import QuotaVisual
from .providers import codex_usage, export_usage
from .sources import CATALOG, fetch

DEFAULT = dict(analytics=False, share_quota=False, update_checks=True, preview_updates=True, agent="Codex", cli="", exports={}, stages=[20,5], reminders_enabled=True, language="en", interval=300, news_interval=300, confidence=.25, notify_personal=True, notify_signals=True, sources=["OpenAI Status","OpenAI News","Codex Releases","GitHub","Reddit","Codex Resets · 75%","Tibo radar · 85%"], style="Standard", signal_count=False, excluded=[], snooze=0)
TYPE_NAMES = dict(scheduled="Normal reset", banked="Banked reset", purchased="Purchased reset", automaticGlobal="Automatic / global reset", suspectedGlobal="Possible global reset", accountUnexpected="Unexpected account reset", complimentary="Complimentary reset offer", forecast="Reset forecast / teaser", poll="Reset-related poll", unknown="Unclassified quota increase")
LEVEL_NAMES = ["Rumor", "Early Signal", "Likely", "Confirmed"]


class Result(QObject):
    ready = Signal(str, object, object)


class Work(QRunnable):
    def __init__(self, name, function, callback):
        super().__init__(); self.name, self.function = name, function
        self.result = Result(); self.result.ready.connect(callback)
    def run(self):
        try: self.result.ready.emit(self.name, self.function(), None)
        except Exception as error: self.result.ready.emit(self.name, None, str(error))


def icon(percent=None):
    image = QPixmap(64,64); image.fill(Qt.GlobalColor.transparent)
    painter = QPainter(image); painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setBrush(QColor("#27766d")); painter.setPen(Qt.PenStyle.NoPen); painter.drawEllipse(4,4,56,56)
    painter.setPen(QColor("white")); painter.setFont(QFont("Sans", 20, QFont.Weight.Bold)); painter.drawText(image.rect(), Qt.AlignmentFlag.AlignCenter, str(round(percent)) if percent is not None else "S")
    painter.end(); return QIcon(image)


def clear(layout):
    while layout.count():
        item = layout.takeAt(0)
        if item.widget(): item.widget().deleteLater()
        elif item.layout(): clear(item.layout())


class SentinelWindow(QMainWindow):
    def __init__(self, mock=False):
        super().__init__(); self.mock = mock
        self.db = Database(data_dir()/("portable-mock.sqlite" if mock else "portable.sqlite"))
        self.settings = DEFAULT | self.db.load("settings", {})
        if not self.settings.get("reset_watch_schema"):
            self.settings["sources"] = list(dict.fromkeys(self.settings["sources"]+["Codex Resets · 75%","Tibo radar · 85%"]))
            self.settings["reset_watch_schema"] = 1
        self.settings.setdefault("panel_mode", "professional"); self.settings.setdefault("visual_style", "ring"); self.settings.setdefault("animations", False)
        self.visual_values = {}
        self.t = Translator(self.settings["language"])
        self.engine = core.ReminderEngine(self.db.load("cycles", {}))
        self.events = self.db.load("events", [])
        self.analytics_state = self.db.load("analytics", {}); self.last_update = 0; self.manifest = None; self.extension_status = ""
        self.state = None; self.available = False; self.busy = set(); self.work = {}; self.last_usage = self.last_news = 0; self.diagnostics = {}; self.selected_event = None
        self.setWindowTitle("AI Usage Sentinel"+(" · MOCK" if mock else "")); self.setWindowIcon(icon()); self.resize(520,700)
        self.tabs = QTabWidget(); self.setCentralWidget(self.tabs)
        self.usage_page, self.events_page, self.settings_page, self.debug_page = (QWidget() for _ in range(4))
        self.usage_layout = QVBoxLayout(self.usage_page); self.event_layout = QVBoxLayout(self.events_page); self.settings_layout = QVBoxLayout(self.settings_page); self.debug_layout = QVBoxLayout(self.debug_page)
        for page, name in zip((self.usage_page,self.events_page,self.settings_page,self.debug_page), ("Usage","Event History","Settings","Diagnostics")): self.tabs.addTab(page,self.t(name))
        self.tray = QSystemTrayIcon(icon(), self); self.tray.setToolTip("AI Usage Sentinel · Usage ?")
        self.tray.activated.connect(self.activated); self.tray.messageClicked.connect(self.notification_clicked)
        self.tray.show(); self.rebuild_settings(); self.render(); self.build_debug()
        self.timer = QTimer(self); self.timer.setInterval(30000); self.timer.timeout.connect(self.tick); self.timer.start()
        QTimer.singleShot(100, self.refresh_all)
        if not QSystemTrayIcon.isSystemTrayAvailable():
            self.show(); self.statusBar().showMessage("System tray unavailable. Keep this window open; a tray extension may be needed on GNOME.")

    def closeEvent(self, event):
        if QSystemTrayIcon.isSystemTrayAvailable(): event.ignore(); self.hide()
        else: event.accept(); QApplication.quit()

    def activated(self, reason):
        if reason in (QSystemTrayIcon.ActivationReason.Trigger, QSystemTrayIcon.ActivationReason.DoubleClick):
            self.show(); self.raise_(); self.activateWindow(); self.refresh_usage()

    def notification_clicked(self):
        self.show(); self.tabs.setCurrentWidget(self.events_page if self.selected_event else self.usage_page); self.raise_()

    def save(self): self.db.save("settings", self.settings)

    def run(self, name, function):
        if name in self.busy: return
        self.busy.add(name); work = Work(name, function, self.completed); self.work[name] = work; QThreadPool.globalInstance().start(work)

    def refresh_usage(self):
        if "Usage" in self.busy: return
        self.last_usage = time.time()
        agent = self.settings["agent"]
        if self.mock:
            self.run("Usage", lambda: core.parse_export(dict(schemaVersion=1,timestamp=datetime.now().astimezone().isoformat(),origin="MOCK",buckets=[dict(id="weekly",name="Weekly",remainingPercent=61,resetAt=time.time()+3*86400,windowDurationMins=10080)]), agent))
        elif agent == "Codex":
            path = self.settings["cli"]; self.run("Usage",lambda: codex_usage(path))
        else:
            path = self.settings["exports"].get(agent, ""); self.run("Usage",lambda: export_usage(path,agent))

    def refresh_news(self):
        if self.mock: return
        self.last_news = time.time()
        for name in self.settings["sources"]:
            cache = self.db.load("cache:"+name, {}); self.run(name, lambda n=name,c=cache: fetch(n,c))

    def refresh_all(self): self.refresh_usage(); self.refresh_news()

    def check_updates(self):
        if self.mock: return
        self.last_update=time.time(); preview=self.settings['preview_updates']; self.run('Updates',lambda:extensions.check_update(preview))

    def analytics_tick(self):
        if self.mock or not self.settings['analytics'] or not extensions.CONFIG.get('analyticsEndpoint'): return
        state=self.analytics_state
        if not state.get('closed') or state.get('sent')==state['closed']['day'] or time.time()-state.get('attempt',0)<3600: return
        state['attempt']=time.time(); self.db.save('analytics',state); settings=self.settings.copy(); summary=state.copy()
        self.run('Analytics',lambda:extensions.send_analytics(settings,summary))

    def tick(self):
        if not self.mock and self.settings['update_checks'] and time.time()-self.last_update>=86400: self.check_updates()
        self.analytics_tick()
        if time.time()-self.last_usage >= self.settings["interval"]: self.refresh_usage()
        if time.time()-self.last_news >= self.settings["news_interval"]: self.refresh_news()
        self.render()

    def completed(self, name, result, error):
        self.busy.discard(name); self.work.pop(name,None)
        now = time.time(); self.diagnostics[name] = dict(status=error or "OK", checked=now)
        if name in ('Updates','Update Download','Analytics','Delete Analytics'):
            if error: self.extension_status=error
            elif name=='Updates':
                self.manifest=result; self.extension_status=self.t('No release in this channel') if not result else (self.t('Update available')+': '+result['version'] if extensions.version(result['version'])>extensions.version(__version__) else self.t('You are up to date'))
                if not result or extensions.version(result['version'])<=extensions.version(__version__): self.manifest=None
            elif name=='Update Download': self.extension_status=self.t('Verified download ready · quit the app, replace it and reopen')+' · '+result
            elif name=='Analytics':
                if result: self.analytics_state['sent']=result['day']; self.db.save('analytics',self.analytics_state)
                self.extension_status=self.t('Anonymous daily summary sent')
            else: self.analytics_state={}; self.db.save('analytics',{}); self.extension_status=self.t('Shared reports deleted; analytics disabled')
            self.rebuild_settings(); self.build_debug(); return
        if name == "Usage":
            if error: self.available = False
            else:
                prior = self.db.latest(result["source"])
                if not prior or prior["timestamp"] != result["timestamp"]:
                    resets = core.personal_resets(prior,result,self.db.load("intent"))
                    self.db.append(result); self.engine.observe(result); self.db.save("cycles",self.engine.cycles)
                    self.events = core.merge(self.events,[],resets,now)
                if self.settings['analytics'] and not self.mock and -60 <= now-result['timestamp'] <= 600:
                    day=time.strftime('%Y-%m-%d',time.gmtime())
                    if self.analytics_state.get('day')!=day: self.analytics_state={'day':day,'observations':0,'agent':self.settings['agent'].lower(),'closed':{k:v for k,v in self.analytics_state.items() if k not in ('closed','sent','attempt')} if self.analytics_state.get('day') else None}
                    if self.analytics_state.get('timestamp')!=result['timestamp']:
                        self.analytics_state['timestamp']=result['timestamp']
                        if self.analytics_state.get('agent')!=self.settings['agent'].lower(): self.analytics_state['agent']='custom'
                        decreased=prior and 0<result['timestamp']-prior['timestamp']<=900 and prior.get('account')==result.get('account') and prior.get('plan')==result.get('plan') and any(a['id']==b['id'] and a.get('reset')==b.get('reset') and a['remaining']>b['remaining'] for a in prior['buckets'] for b in result['buckets'])
                        if decreased: self.analytics_state['observations']=min(21,self.analytics_state['observations']+1)
                        remaining=min((b['remaining'] for b in result['buckets']),default=None)
                        new_band='unknown' if remaining is None or now-result['timestamp']>600 else '0-4' if remaining<5 else '5-19' if remaining<20 else '20-49' if remaining<50 else '50-100'
                        order=['0-4','5-19','20-49','50-100','unknown']
                        if not self.settings['share_quota']: new_band='unknown'
                        if order.index(new_band)<order.index(self.analytics_state.get('quotaBand','unknown')): self.analytics_state['quotaBand']=new_band
                        self.db.save('analytics',self.analytics_state)
                self.state = result; self.available = -60 <= now-result["timestamp"] <= 600
                if not self.available: self.diagnostics[name]["status"] = "Export is stale · refresh at source"
        elif result:
            cache, signals, status = result; self.db.save("cache:"+name,cache); self.diagnostics[name].update(status=status,latency=cache.get("latency"),last_success=cache.get("last_success"),retry=cache.get("retry"))
            self.events = core.merge(self.events,signals,[],now)
        self.notify(); self.db.save("events",self.events); self.render(); self.build_debug()

    def send(self, title, body, event=None):
        # Qt reports capability, not guaranteed OS delivery. Focus/DND may hide banners.
        if not QSystemTrayIcon.supportsMessages() or not QSystemTrayIcon.isSystemTrayAvailable():
            self.diagnostics["Notifications"] = dict(status="Desktop notification support unavailable",checked=time.time()); return False
        self.selected_event = event
        self.tray.showMessage(("[MOCK] " if self.mock else "")+title,body,QSystemTrayIcon.MessageIcon.Information,10000)
        return True

    def notify(self):
        now = time.time()
        for event in self.events:
            if core.should_notify(event,self.settings,now):
                title = self.t("⚡ Reset signal strengthened") if event["own"] and len(event["sources"])>1 else self.t("⚡ Unexpected usage reset detected") if event["own"] else "⚡ "+self.t(TYPE_NAMES[event["type"]])
                body = f"{event['product']} · {event['confidence']:.0%} · {self.t(LEVEL_NAMES[core.level(event['confidence'])])}\n"+"\n".join(s["url"] for s in event["sources"][:2])
                if self.send(title,body,event["id"]): event["notified"] = core.level(event["confidence"]); event["notified_own"] |= event["own"]
        if self.available and self.state:
            for alert in self.engine.pending(self.state,self.settings,now):
                row = alert["row"]; title = self.t("Low quota · critical reminder" if alert["critical"] else "Low quota reminder")
                body = f"{row['product']} · {self.t(row['name'])}: {row['remaining']:g}%\n≤{alert['threshold']}% · {row['source']}"
                if self.send(title,body): self.engine.delivered(alert); self.db.save("cycles",self.engine.cycles)

    def render(self):
        clear(self.usage_layout); clear(self.event_layout)
        header = QLabel("AI Usage Sentinel"+(" · MOCK" if self.mock else "")); header.setStyleSheet("font-size:20px;font-weight:600"); self.usage_layout.addWidget(header)
        menu = QMenu(self); menu.addAction("AI Usage Sentinel",self.show)
        if self.state:
            for row in self.state["buckets"]:
                label = QLabel(f"{row['product']} · {self.t(row['name'])}"); self.usage_layout.addWidget(label)
                if self.settings["panel_mode"] == "intuitive":
                    previous = None
                    self.usage_layout.addWidget(QuotaVisual(row["remaining"], self.settings["visual_style"], self.settings["animations"], previous))
                    status = "Almost empty" if row["remaining"] < 5 else "Running low" if row["remaining"] < 20 else "Keep an eye on usage" if row["remaining"] <= 50 else "Plenty remaining"
                    self.usage_layout.addWidget(QLabel(self.t(status)))
                    self.visual_values[row["id"]] = row["remaining"]
                elif self.settings["panel_mode"] == "professional":
                    self.usage_layout.addWidget(QuotaVisual(row["remaining"], "bar", self.settings["animations"]))
                else:
                    self.usage_layout.addWidget(QuotaVisual(row["remaining"], "number", self.settings["animations"]))
                reset = datetime.fromtimestamp(row["reset"]).astimezone().strftime("%b %d, %H:%M") if row["reset"] else self.t("unknown")
                self.usage_layout.addWidget(QLabel(self.t("Next regular reset")+": "+reset))
                if self.settings["panel_mode"] == "professional": self.usage_layout.addWidget(QLabel(row["source"]))
                menu.addAction(f"{row['product']} {self.t(row['name'])} {row['remaining']:g}%"+(" · stale" if not self.available else ""),self.show)
            stamp = datetime.fromtimestamp(self.state["timestamp"]).astimezone().strftime("%H:%M:%S")
            self.usage_layout.addWidget(QLabel(self.t("Last updated")+": "+stamp+(" · "+self.t("Last successful snapshot · stale") if not self.available else "")))
        else: self.usage_layout.addWidget(QLabel(self.t("Usage unavailable")))
        active = [e for e in self.events if time.time()-e["updated"]<86400 and e["type"] not in ("scheduled","banked","purchased")]
        self.usage_layout.addWidget(QLabel(self.t("Reset Signals")+f" · {len(active)}"))
        if not active: self.usage_layout.addWidget(QLabel(self.t("No current irregular reset signals")))
        watch_button = QPushButton(self.t("Reset Watch & Forecast")); watch_button.clicked.connect(self.show_reset_watch); self.event_layout.addWidget(watch_button)
        for event in sorted(self.events,key=lambda e:e["updated"],reverse=True)[:100]:
            button = QPushButton(f"{event['product']} · {self.t(TYPE_NAMES[event['type']])}\n{event['confidence']:.0%} · {self.t(LEVEL_NAMES[core.level(event['confidence'])])} · {datetime.fromtimestamp(event['at']).strftime('%m/%d %H:%M')}")
            button.clicked.connect(lambda checked=False,e=event:self.show_event(e)); self.event_layout.addWidget(button)
        self.event_layout.addStretch(); self.usage_layout.addStretch()
        button = QPushButton(self.t("Refresh All")); button.clicked.connect(self.refresh_all); self.usage_layout.addWidget(button)
        for key, callback in (("Refresh All",self.refresh_all),("Settings",lambda:self.open_tab(self.settings_page)),("Event History",lambda:self.open_tab(self.events_page)),("Quit",QApplication.quit)): menu.addAction(self.t(key),callback)
        self.tray.setContextMenu(menu)
        rows = self.state["buckets"] if self.available and self.state else []
        tooltip = " · ".join(f"{r['product']} {r['name']} {r['remaining']:g}%" for r in rows) or "Usage ?"
        if self.settings["signal_count"] and active: tooltip += f" · ⚡{len(active)}"
        self.tray.setToolTip("AI Usage Sentinel · "+tooltip)
        self.tray.setIcon(icon(rows[0]["remaining"] if rows and self.settings["style"] == "Percentage" else None))

    def open_tab(self,page): self.show(); self.tabs.setCurrentWidget(page); self.raise_()

    def show_reset_watch(self):
        import html
        from .reset_watch import weight
        escaped = html.escape
        dialog = QMainWindow(self); dialog.setWindowTitle(self.t("Reset Watch & Forecast")); dialog.resize(760,650)
        browser = QTextBrowser(); browser.setOpenExternalLinks(False); browser.anchorClicked.connect(lambda url: QDesktopServices.openUrl(url) if extensions.safe_url(url.toString()) else None)
        signals = []
        for name in ("Codex Resets · 75%","Tibo radar · 85%"):
            if name in self.settings["sources"]: signals += self.db.load("cache:"+name,{}).get("signals",[])
        sources = {sig["source"]["url"]: sig for sig in sorted(signals,key=lambda sig: weight(sig["source"]) or 0)}
        signals = sorted(sources.values(),key=lambda sig: sig["source"].get("publishedAt") or 0,reverse=True)
        latest = max((sig["source"]["publishedAt"] for sig in signals if sig["type"] == "suspectedGlobal"),default=0)
        fresh = [sig for sig in signals if sig["type"] in ("forecast","poll") and sig["source"].get("expiresAt",0)>time.time() and sig["source"].get("publishedAt",0)>latest]
        heading = self.t("Possible reset · watch active" if fresh else "Irregular reset: no known schedule")
        pieces = [f"<h2>{escaped(heading)}</h2>",f"<p>{escaped(self.t('Polls and teasers are early evidence, not completed resets. Source weights are not probabilities of a future reset.'))}</p>","<p>Tibo @thsottiaux · 85% / @codex_resets · 75%</p>"]
        for sig in signals[:20]:
            source = sig["source"]; stamp = datetime.fromtimestamp(source["publishedAt"]).astimezone().isoformat()
            pieces.append(f"<hr><b>{escaped(self.t(TYPE_NAMES[sig['type']]))}</b> · {escaped(stamp)}<p>{escaped(source['snippet'])}</p><a href='{escaped(source['url'],quote=True)}'>Original X post ↗</a> · <a href='{escaped(source.get('viaURL',''),quote=True)}'>Data attribution ↗</a>")
        pieces.append(f"<p>{escaped(self.t('Secondary public feeds may omit posts, poll options or vote counts. Open the original poll on X for live results. No automated votes are cast.'))}</p>")
        browser.setHtml(''.join(pieces)); dialog.setCentralWidget(browser); dialog.show(); self.reset_dialog = dialog

    def show_event(self,event):
        dialog = QMainWindow(self); dialog.setWindowTitle(self.t(TYPE_NAMES[event["type"]])); dialog.resize(600,550)
        browser = QTextBrowser(); browser.setOpenExternalLinks(False); browser.anchorClicked.connect(lambda url: QDesktopServices.openUrl(url) if extensions.safe_url(url.toString()) else None)
        import html
        escaped = html.escape
        pieces = [f"<h2>{escaped(event['product'])} · {escaped(self.t(TYPE_NAMES[event['type']]))}</h2>",f"<p>{event['confidence']:.0%} · {escaped(self.t(LEVEL_NAMES[core.level(event['confidence'])]))}</p>",f"<p>{escaped(event['explanation'])}</p>"]
        for s in event["sources"]:
            if s.get("viaURL"):
                pieces.append(f"<p>Data from <a href='{escaped(s["viaURL"],quote=True)}'>{escaped(s["viaURL"])}</a> · source weight is not a reset probability.</p>")
            stamp = datetime.fromtimestamp(s["publishedAt"]).astimezone().isoformat() if s.get("publishedAt") else "unknown"
            pieces.append(f"<hr><p><b>{escaped(s['platform'])}</b> · {escaped(stamp)}<br><a href='{escaped(s['url'],quote=True)}'>{escaped(s['title'])}</a></p><p>{escaped(s['snippet'])}</p><p>Fetched: {datetime.fromtimestamp(s['fetchedAt']).astimezone().isoformat()} · {escaped(s.get('author') or '')}</p>")
        browser.setHtml("".join(pieces))
        content = QWidget(); layout = QVBoxLayout(content)
        meter = QProgressBar(); meter.setRange(0,100); meter.setValue(round(event["confidence"]*100)); meter.setFormat("%p%"); layout.addWidget(meter); layout.addWidget(browser)
        dialog.setCentralWidget(content); dialog.show(); self.event_dialog = dialog

    def change_visual(self, key, value):
        self.option(key, value); self.render()
        QTimer.singleShot(0, self.rebuild_settings)

    def option(self,key,value): self.settings[key] = value; self.save()

    def rebuild_settings(self):
        selected = getattr(self, "settings_category", 0)
        clear(self.settings_layout)
        categories = QTabWidget(); categories.setUsesScrollButtons(True)
        self.settings_layout.addWidget(categories)
        forms = {}
        for name in ("General", "Panel visualization", "Menu Bar Appearance", "Refresh", "Remaining quota reminders", "Notifications", "Sources", "Usage provider", "Updates", "Optional anonymous analytics", "Privacy & Diagnostics", "Testing"):
            scroll = QScrollArea(); scroll.setWidgetResizable(True)
            body = QWidget(); layout = QFormLayout(body); layout.setVerticalSpacing(16)
            scroll.setWidget(body); categories.addTab(scroll, self.t(name)); forms[name] = layout
        categories.setCurrentIndex(selected)
        categories.currentChanged.connect(lambda index: setattr(self, "settings_category", index))
        form = forms["Panel visualization"]
        mode = QComboBox()
        for key in ("professional", "intuitive", "compact"): mode.addItem(self.t(key.capitalize()), key)
        mode.setCurrentIndex(("professional", "intuitive", "compact").index(self.settings["panel_mode"]))
        mode.currentIndexChanged.connect(lambda i: self.change_visual("panel_mode", mode.itemData(i))); form.addRow(self.t("Panel mode"), mode)
        visual = QComboBox()
        for key, title in (("ring", "Quota ring"), ("battery", "Quota battery")): visual.addItem(self.t(title), key)
        visual.setCurrentIndex(0 if self.settings["visual_style"] == "ring" else 1); visual.setEnabled(self.settings["panel_mode"] == "intuitive")
        visual.currentIndexChanged.connect(lambda i: self.change_visual("visual_style", visual.itemData(i))); form.addRow(self.t("Visualization"), visual)
        animated = QCheckBox(self.t("Animate quota changes")); animated.setChecked(self.settings["animations"])
        animated.toggled.connect(lambda v: self.change_visual("animations", v)); form.addRow(animated)
        form.addRow(QLabel(self.t("Illustrative visualization preview")), QuotaVisual(72, self.settings["visual_style"], self.settings["animations"]))
        form = forms["General"]
        language = QComboBox(); [language.addItem(name,code) for code,name in LANGUAGES.items()]; language.setCurrentIndex(list(LANGUAGES).index(self.settings["language"]))
        def change_language(index):
            self.option("language",language.itemData(index)); self.t.language = self.settings["language"]
            for i,key in enumerate(("Usage","Event History","Settings","Diagnostics")): self.tabs.setTabText(i,self.t(key))
            QTimer.singleShot(0, self.rebuild_settings); self.render(); self.build_debug()
        language.currentIndexChanged.connect(change_language); form.addRow(self.t("Language"),language)
        form = forms["Usage provider"]
        agent = QComboBox(); agent.addItems(["Codex","Claude","Gemini","Grok","Custom"]); agent.setCurrentText(self.settings["agent"])
        def change_agent(value): self.option("agent",value); self.available=False; self.state=None; QTimer.singleShot(0,self.rebuild_settings); self.refresh_usage(); self.render()
        agent.currentTextChanged.connect(change_agent); form.addRow(self.t("AI agent"),agent)
        cli = QLineEdit(self.settings["cli"]); cli.editingFinished.connect(lambda:self.option("cli",cli.text())); form.addRow(self.t("Codex executable (optional)"),cli)
        path = QLineEdit(self.settings["exports"].get(self.settings["agent"],""))
        def save_path(): self.settings["exports"][self.settings["agent"]] = path.text(); self.save()
        path.editingFinished.connect(save_path); form.addRow(self.t("Local usage JSON path"),path)
        choose = QPushButton(self.t("Choose JSON Export…"))
        def choose_file():
            file,_ = QFileDialog.getOpenFileName(self,self.t("Choose JSON Export…"),"","JSON (*.json)")
            if file: path.setText(file); save_path(); self.refresh_usage()
        choose.clicked.connect(choose_file); form.addRow(choose)
        guide = QPushButton(self.t("Agent setup guide")); guide.clicked.connect(lambda:QDesktopServices.openUrl(QUrl("https://github.com/Joe05520/ai-agent-usage-limit-reset-forecast/blob/main/docs/AGENTS.md"))); form.addRow(guide)
        form = forms["Updates"]
        self.checkbox(form,'Check for updates daily','update_checks')
        self.checkbox(form,'Include preview releases','preview_updates')
        check=QPushButton(self.t('Check for Updates')); check.clicked.connect(self.check_updates); check.setEnabled(not self.mock); form.addRow(check)
        if self.manifest:
            download=QPushButton(self.t('Download Verified Update')); download.clicked.connect(lambda:self.run('Update Download',lambda:extensions.download_update(self.manifest))); form.addRow(download)
        summary=QLabel(self.extension_status); summary.setWordWrap(True); form.addRow(summary)
        form = forms["Optional anonymous analytics"]
        privacy=QLabel(self.t('Off by default. Sends country, platform, agent, reminder-stage count and a daily activity band. Quota bands require separate consent. No account ID, exact usage, reset time, prompts, tokens or cookies. Cloudflare processes your IP to determine country but this app does not store it in analytics.')); privacy.setWordWrap(True); form.addRow(privacy)
        consent=QCheckBox(self.t('Share anonymous daily usage habits')); consent.setChecked(self.settings['analytics']); consent.setEnabled(not self.mock and bool(extensions.CONFIG.get('analyticsEndpoint')))
        def consent_changed(value):
            if value:
                try: extensions.identity()
                except Exception as error: consent.setChecked(False); self.extension_status=str(error); QMessageBox.warning(self,'AI Usage Sentinel',str(error)); return
            self.option('analytics',value)
        consent.toggled.connect(consent_changed); form.addRow(consent)
        self.checkbox(form,'Also share coarse remaining-quota bands','share_quota')
        remove=QPushButton(self.t('Delete shared reports and turn off'))
        def delete_reports():
            self.option('analytics',False); self.option('share_quota',False); self.run('Delete Analytics',extensions.delete_analytics)
        remove.clicked.connect(delete_reports); remove.setEnabled(not self.mock); form.addRow(remove)
        form = forms["Remaining quota reminders"]
        self.checkbox(form,"Remind me when quota runs low","reminders_enabled")
        values = core.thresholds(self.settings["stages"])
        for index,value in enumerate(values):
            row = QWidget(); layout = QHBoxLayout(row); layout.setContentsMargins(0,0,0,0)
            spin = QSpinBox(); spin.setRange(values[index+1]+1 if index+1<len(values) else 0,values[index-1]-1 if index else 99); spin.setValue(value); spin.setSuffix("%")
            def change(v,i=index):
                stages = self.settings["stages"][:]; stages[i] = v; self.option("stages",core.thresholds(stages))
                QTimer.singleShot(0,self.rebuild_settings)
            spin.valueChanged.connect(change); layout.addWidget(spin)
            remove = QPushButton("−"); remove.setAccessibleName(self.t("Remove stage %d",index+1)); remove.clicked.connect(lambda checked=False,i=index:self.remove_stage(i)); layout.addWidget(remove)
            form.addRow(self.t("Stage %d: ≤%d%% remaining",index+1,value),row)
        add = QPushButton(self.t("Add reminder (%d/5)",len(values))); add.setEnabled(len(values)<5); add.clicked.connect(self.add_stage); form.addRow(add)
        caption = QLabel(self.t("Add up to five distinct thresholds from 0–99%. Stages run from highest to lowest; the final stage is critical when more than one is set.")); caption.setWordWrap(True); form.addRow(caption)
        pause = QPushButton(self.t("Pause Quota Reminders for 1 Hour")); pause.clicked.connect(lambda:self.option("snooze",time.time()+3600)); form.addRow(pause)
        resume = QPushButton(self.t("Resume Quota Reminders")); resume.clicked.connect(lambda:self.option("snooze",0)); form.addRow(resume)
        form = forms["Refresh"]
        for key in ("interval","news_interval"):
            combo = QComboBox(); [combo.addItem(self.t("%d min",v),v*60) for v in [2,5,10,15,30]]; combo.setCurrentIndex(combo.findData(self.settings[key])); combo.currentIndexChanged.connect(lambda i,c=combo,k=key:self.option(k,c.itemData(i)))
            form.addRow(self.t("Usage" if key=="interval" else "Signals"),combo)
        form = forms["Notifications"]
        confidence = QComboBox(); [confidence.addItem(self.t(label),v) for label,v in [("Very Early ≥15%",.15),("Early ≥25%",.25),("Likely ≥60%",.6),("Official Only ≥90%",.9)]]; confidence.setCurrentIndex(confidence.findData(self.settings["confidence"])); confidence.currentIndexChanged.connect(lambda i:self.option("confidence",confidence.itemData(i))); form.addRow(self.t("Notify confidence"),confidence)
        self.checkbox(form,"Unexpected personal reset","notify_personal"); self.checkbox(form,"Reset early signals","notify_signals")
        form = forms["Menu Bar Appearance"]
        self.checkbox(form,"Show reset signal count in menu bar","signal_count")
        form = forms["Menu Bar Appearance"]
        style = QComboBox(); style.addItems(["Standard","Percentage"]); style.setCurrentText(self.settings["style"]); style.currentTextChanged.connect(lambda v:(self.option("style",v),self.render())); form.addRow(self.t("Display style"),style)
        form = forms["Sources"]
        for name in CATALOG:
            checkbox = QCheckBox(name); checkbox.setChecked(name in self.settings["sources"])
            def enabled(value,n=name):
                values=set(self.settings["sources"]); values.add(n) if value else values.discard(n); self.option("sources",sorted(values))
            checkbox.toggled.connect(enabled); form.addRow(checkbox)
        form = forms["General"]
        login = QCheckBox(self.t("Launch at Login")); login.setChecked(autostart.enabled())
        def toggle_login(value):
            try: autostart.set_enabled(value)
            except OSError as error: QMessageBox.warning(self,"AI Usage Sentinel",str(error)); login.blockSignals(True); login.setChecked(autostart.enabled()); login.blockSignals(False)
            except RuntimeError as error: QMessageBox.information(self,"AI Usage Sentinel",str(error))
        login.toggled.connect(toggle_login); form.addRow(login)
        form = forms["Testing"]
        test = QPushButton(self.t("Send Test")); test.clicked.connect(lambda:self.send("AI Usage Sentinel · "+self.t("Notification test"),self.t("All account data stays on this Mac. Public-source requests contain no account history or credentials. Official Codex handles its own authentication.").replace("Mac","device"))); form.addRow(test)
        form = forms["Privacy & Diagnostics"]
        privacy = QLabel("All account data stays on this device. Public requests contain no usage history or credentials. Tibo polls and reset hints use public secondary feeds (codex-reset.com / codex-resets.com). Weights are not reset probabilities. Full X coverage and live poll counts are unavailable."); privacy.setWordWrap(True); form.addRow(privacy)
        form = forms["Testing"]
        if self.mock:
            mock = QPushButton("[MOCK] Run reset + five-stage scenarios"); mock.clicked.connect(self.mock_test); form.addRow(mock)

    def checkbox(self,form,label,key):
        checkbox=QCheckBox(self.t(label)); checkbox.setChecked(self.settings[key]); checkbox.toggled.connect(lambda v:self.option(key,v)); form.addRow(checkbox)

    def add_stage(self):
        stages = self.settings["stages"]
        if len(stages)<5:
            next_value=next(v for v in [50,30,20,10,5]+list(range(99,-1,-1)) if v not in stages)
            self.option("stages",core.thresholds(stages+[next_value])); self.rebuild_settings()

    def remove_stage(self,index):
        values=self.settings["stages"][:]; values.pop(index); self.option("stages",values); self.rebuild_settings()

    def build_debug(self):
        clear(self.debug_layout)
        report = json.dumps(dict(version=__version__,mock=self.mock,agent=self.settings["agent"],usage_available=self.available,notifications_capable=QSystemTrayIcon.supportsMessages(),tray_available=QSystemTrayIcon.isSystemTrayAvailable(),sources=self.diagnostics),indent=2)
        browser=QTextBrowser(); browser.setPlainText(report); self.debug_layout.addWidget(browser)
        copy=QPushButton(self.t("Copy Diagnostics")); copy.clicked.connect(lambda:QApplication.clipboard().setText(report)); self.debug_layout.addWidget(copy)

    def mock_test(self):
        if not self.mock: return
        self.option("stages",[50,30,20,10,5]); self.engine=core.ReminderEngine()
        now=time.time(); before=core.parse_export(dict(schemaVersion=1,timestamp=now-60,buckets=[dict(id="weekly",name="Weekly",remainingPercent=23,resetAt=now+3*86400,windowDurationMins=10080)],origin="MOCK"),"Codex",now)
        after=json.loads(json.dumps(before)); after["timestamp"]=now; after["buckets"][0]["remaining"]=100
        events=core.personal_resets(before,after); self.events=core.merge(self.events,[],events,now)
        low=json.loads(json.dumps(after)); low["timestamp"]=now+1; low["buckets"][0]["remaining"]=3
        self.state=low; self.available=True; self.engine.observe(low); self.notify(); self.db.save("events",self.events); self.render(); self.rebuild_settings()
