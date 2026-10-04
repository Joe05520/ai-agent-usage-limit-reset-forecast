CREATE TABLE reports (
 day TEXT NOT NULL, client TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('app','download')),
 country TEXT NOT NULL, platform TEXT NOT NULL, version TEXT NOT NULL,
 agent TEXT, quota_band TEXT, activity_band TEXT, reminders INTEGER,
 PRIMARY KEY(day,client,kind)
);
CREATE INDEX reports_day ON reports(day);
CREATE TABLE github_downloads(day TEXT NOT NULL, platform TEXT NOT NULL, downloads INTEGER NOT NULL, PRIMARY KEY(day,platform));
