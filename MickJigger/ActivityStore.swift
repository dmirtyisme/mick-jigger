import Foundation
import SQLite3

/// A closed work session detected by SessionDetector.
struct ActivitySession {
    var start: Date
    var end: Date
    var clicks: Int
    var scrolls: Int
    var distancePx: Double

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// SQLite persistence for activity stats — raw sqlite3, no dependencies.
///
/// Schema (per the architecture spec):
///   sessions      — one row per detected work session
///   events_daily  — one aggregate row per calendar day; hourly breakdown is
///                   kept in a CSV column so the timeline/peak-hour metrics
///                   stay within the two-table schema.
///
/// All access happens on the main thread (the tap, timers, and UI all live
/// there). Failures degrade to no-ops — activity tracking must never crash
/// the jiggler.
final class ActivityStore {

    private var db: OpaquePointer?

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        let dir = support.appendingPathComponent("MickJigger", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("activity.sqlite").path

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            sqlite3_close(db)
            db = nil
            return
        }
        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    private func createTables() {
        exec("""
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                start REAL NOT NULL,
                end REAL NOT NULL,
                duration REAL NOT NULL,
                clicks INTEGER NOT NULL DEFAULT 0,
                scrolls INTEGER NOT NULL DEFAULT 0,
                distance_px REAL NOT NULL DEFAULT 0
            );
            """)
        exec("CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start);")
        exec("""
            CREATE TABLE IF NOT EXISTS events_daily (
                day TEXT PRIMARY KEY,
                real_clicks INTEGER NOT NULL DEFAULT 0,
                real_double_clicks INTEGER NOT NULL DEFAULT 0,
                real_scrolls INTEGER NOT NULL DEFAULT 0,
                real_distance_px REAL NOT NULL DEFAULT 0,
                syn_events INTEGER NOT NULL DEFAULT 0,
                syn_clicks INTEGER NOT NULL DEFAULT 0,
                syn_scrolls INTEGER NOT NULL DEFAULT 0,
                syn_distance_px REAL NOT NULL DEFAULT 0,
                max_speed_px_s REAL NOT NULL DEFAULT 0,
                last_activity REAL,
                hour_bins TEXT NOT NULL DEFAULT ''
            );
            """)
    }

    // MARK: - Day keys

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// "yyyy-MM-dd" in the local calendar — sorts lexicographically.
    static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func date(fromDayKey key: String) -> Date? {
        dayFormatter.date(from: key)
    }

    // MARK: - Daily aggregates

    struct DailyRow {
        var day: String
        var realClicks = 0
        var realDoubleClicks = 0
        var realScrolls = 0
        var realDistancePx = 0.0
        var synEvents = 0
        var synClicks = 0
        var synScrolls = 0
        var synDistancePx = 0.0
        var maxSpeedPxPerSec = 0.0
        var lastActivity: Date?
        var hourBins = [Int](repeating: 0, count: 24)
    }

    /// Adds in-memory deltas to a day's aggregate row (read-merge-write —
    /// single-threaded access makes this race-free, and it keeps the hourly
    /// CSV merge in Swift instead of SQL).
    func addDailyDeltas(_ deltas: ActivityDeltas, day: String) {
        guard db != nil, !deltas.isEmpty else { return }

        var row = dailyRow(day: day) ?? DailyRow(day: day)
        row.realClicks += deltas.realClicks
        row.realDoubleClicks += deltas.realDoubleClicks
        row.realScrolls += deltas.realScrolls
        row.realDistancePx += deltas.realDistancePx
        row.synEvents += deltas.synEvents
        row.synClicks += deltas.synClicks
        row.synScrolls += deltas.synScrolls
        row.synDistancePx += deltas.synDistancePx
        row.maxSpeedPxPerSec = max(row.maxSpeedPxPerSec, deltas.maxSpeedPxPerSec)
        if let last = deltas.lastActivity {
            row.lastActivity = max(row.lastActivity ?? .distantPast, last)
        }
        for i in 0..<24 { row.hourBins[i] += deltas.hourBins[i] }

        let sql = """
            REPLACE INTO events_daily
            (day, real_clicks, real_double_clicks, real_scrolls, real_distance_px,
             syn_events, syn_clicks, syn_scrolls, syn_distance_px,
             max_speed_px_s, last_activity, hour_bins)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, row.day, -1, Self.transient)
        sqlite3_bind_int64(stmt, 2, Int64(row.realClicks))
        sqlite3_bind_int64(stmt, 3, Int64(row.realDoubleClicks))
        sqlite3_bind_int64(stmt, 4, Int64(row.realScrolls))
        sqlite3_bind_double(stmt, 5, row.realDistancePx)
        sqlite3_bind_int64(stmt, 6, Int64(row.synEvents))
        sqlite3_bind_int64(stmt, 7, Int64(row.synClicks))
        sqlite3_bind_int64(stmt, 8, Int64(row.synScrolls))
        sqlite3_bind_double(stmt, 9, row.synDistancePx)
        sqlite3_bind_double(stmt, 10, row.maxSpeedPxPerSec)
        if let last = row.lastActivity {
            sqlite3_bind_double(stmt, 11, last.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 11)
        }
        let bins = row.hourBins.map(String.init).joined(separator: ",")
        sqlite3_bind_text(stmt, 12, bins, -1, Self.transient)
        sqlite3_step(stmt)
    }

    func dailyRow(day: String) -> DailyRow? {
        var result: DailyRow?
        query("SELECT * FROM events_daily WHERE day = ?;",
              bind: { sqlite3_bind_text($0, 1, day, -1, Self.transient) },
              row: { result = Self.readDailyRow($0) })
        return result
    }

    /// Rows for `from`...`to` inclusive (day-key strings), ascending.
    func dailyRows(from: String, to: String) -> [DailyRow] {
        var rows: [DailyRow] = []
        query("SELECT * FROM events_daily WHERE day >= ? AND day <= ? ORDER BY day;",
              bind: {
                  sqlite3_bind_text($0, 1, from, -1, Self.transient)
                  sqlite3_bind_text($0, 2, to, -1, Self.transient)
              },
              row: { rows.append(Self.readDailyRow($0)) })
        return rows
    }

    func allDailyRows() -> [DailyRow] {
        var rows: [DailyRow] = []
        query("SELECT * FROM events_daily ORDER BY day;",
              bind: { _ in },
              row: { rows.append(Self.readDailyRow($0)) })
        return rows
    }

    private static func readDailyRow(_ stmt: OpaquePointer) -> DailyRow {
        var row = DailyRow(day: String(cString: sqlite3_column_text(stmt, 0)))
        row.realClicks = Int(sqlite3_column_int64(stmt, 1))
        row.realDoubleClicks = Int(sqlite3_column_int64(stmt, 2))
        row.realScrolls = Int(sqlite3_column_int64(stmt, 3))
        row.realDistancePx = sqlite3_column_double(stmt, 4)
        row.synEvents = Int(sqlite3_column_int64(stmt, 5))
        row.synClicks = Int(sqlite3_column_int64(stmt, 6))
        row.synScrolls = Int(sqlite3_column_int64(stmt, 7))
        row.synDistancePx = sqlite3_column_double(stmt, 8)
        row.maxSpeedPxPerSec = sqlite3_column_double(stmt, 9)
        if sqlite3_column_type(stmt, 10) != SQLITE_NULL {
            row.lastActivity = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))
        }
        if let binsText = sqlite3_column_text(stmt, 11) {
            let parts = String(cString: binsText).split(separator: ",").map { Int($0) ?? 0 }
            if parts.count == 24 { row.hourBins = parts }
        }
        return row
    }

    // MARK: - Sessions

    func record(session: ActivitySession) {
        guard db != nil, session.duration > 0 else { return }
        let sql = """
            INSERT INTO sessions (start, end, duration, clicks, scrolls, distance_px)
            VALUES (?,?,?,?,?,?);
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, session.start.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, session.end.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 3, session.duration)
        sqlite3_bind_int64(stmt, 4, Int64(session.clicks))
        sqlite3_bind_int64(stmt, 5, Int64(session.scrolls))
        sqlite3_bind_double(stmt, 6, session.distancePx)
        sqlite3_step(stmt)
    }

    /// Sessions whose range overlaps [from, to), ordered by start.
    func sessions(from: Date, to: Date) -> [ActivitySession] {
        var sessions: [ActivitySession] = []
        query("SELECT start, end, clicks, scrolls, distance_px FROM sessions WHERE end >= ? AND start < ? ORDER BY start;",
              bind: {
                  sqlite3_bind_double($0, 1, from.timeIntervalSince1970)
                  sqlite3_bind_double($0, 2, to.timeIntervalSince1970)
              },
              row: { stmt in
                  sessions.append(ActivitySession(
                      start: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                      end: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                      clicks: Int(sqlite3_column_int64(stmt, 2)),
                      scrolls: Int(sqlite3_column_int64(stmt, 3)),
                      distancePx: sqlite3_column_double(stmt, 4)))
              })
        return sessions
    }

    func longestSessionEver() -> ActivitySession? {
        var result: ActivitySession?
        query("SELECT start, end, clicks, scrolls, distance_px FROM sessions ORDER BY duration DESC LIMIT 1;",
              bind: { _ in },
              row: { stmt in
                  result = ActivitySession(
                      start: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                      end: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                      clicks: Int(sqlite3_column_int64(stmt, 2)),
                      scrolls: Int(sqlite3_column_int64(stmt, 3)),
                      distancePx: sqlite3_column_double(stmt, 4))
              })
        return result
    }

    // MARK: - Records

    func maxDistanceDay() -> (day: String, distancePx: Double)? {
        var result: (String, Double)?
        query("SELECT day, real_distance_px FROM events_daily ORDER BY real_distance_px DESC LIMIT 1;",
              bind: { _ in },
              row: { stmt in
                  let value = sqlite3_column_double(stmt, 1)
                  if value > 0 {
                      result = (String(cString: sqlite3_column_text(stmt, 0)), value)
                  }
              })
        return result
    }

    func maxClicksDay() -> (day: String, clicks: Int)? {
        var result: (String, Int)?
        query("SELECT day, real_clicks FROM events_daily ORDER BY real_clicks DESC LIMIT 1;",
              bind: { _ in },
              row: { stmt in
                  let value = Int(sqlite3_column_int64(stmt, 1))
                  if value > 0 {
                      result = (String(cString: sqlite3_column_text(stmt, 0)), value)
                  }
              })
        return result
    }

    // MARK: - SQL plumbing

    private func exec(_ sql: String) {
        guard db != nil else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func query(
        _ sql: String,
        bind: (OpaquePointer) -> Void,
        row: (OpaquePointer) -> Void
    ) {
        guard db != nil else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            row(stmt)
        }
    }
}
