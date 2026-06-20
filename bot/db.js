const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const DB_DIR = path.join(__dirname, 'data');
const DB_PATH = path.join(DB_DIR, 'ideas.db');

if (!fs.existsSync(DB_DIR)) fs.mkdirSync(DB_DIR, { recursive: true });

const db = new Database(DB_PATH);

db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

db.exec(`
  CREATE TABLE IF NOT EXISTS ideas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    text TEXT NOT NULL,
    author TEXT NOT NULL,
    author_id INTEGER NOT NULL,
    chat_id INTEGER NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    category TEXT NOT NULL DEFAULT 'other' CHECK(category IN ('feature','bug','ux','marketing','other')),
    priority INTEGER CHECK(priority BETWEEN 1 AND 10),
    score INTEGER CHECK(score BETWEEN 1 AND 10),
    status TEXT NOT NULL DEFAULT 'new' CHECK(status IN ('new','reviewed','accepted','rejected'))
  );

  CREATE TABLE IF NOT EXISTS summaries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    period TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
`);

// Ideas
const insertIdea = db.prepare(`
  INSERT INTO ideas (text, author, author_id, chat_id, category)
  VALUES (@text, @author, @author_id, @chat_id, @category)
`);

const getAllIdeas = db.prepare(`
  SELECT * FROM ideas ORDER BY category, created_at DESC
`);

const getIdeasByCategory = db.prepare(`
  SELECT * FROM ideas WHERE category = ? ORDER BY created_at DESC
`);

const getIdeaById = db.prepare(`SELECT * FROM ideas WHERE id = ?`);

const getTodayIdeas = db.prepare(`
  SELECT * FROM ideas
  WHERE date(created_at) = date('now')
  ORDER BY created_at DESC
`);

const getUnrankedIdeas = db.prepare(`
  SELECT * FROM ideas WHERE priority IS NULL ORDER BY created_at DESC
`);

const updateIdeaStatus = db.prepare(`
  UPDATE ideas SET status = ?, updated_at = datetime('now') WHERE id = ?
`);

const updateIdeaRank = db.prepare(`
  UPDATE ideas SET priority = ?, score = ?, category = ?, updated_at = datetime('now') WHERE id = ?
`);

const insertSummary = db.prepare(`
  INSERT INTO summaries (content, period) VALUES (@content, @period)
`);

const getRecentSummaries = db.prepare(`
  SELECT * FROM summaries ORDER BY created_at DESC LIMIT 5
`);

module.exports = {
  insertIdea,
  getAllIdeas,
  getIdeasByCategory,
  getIdeaById,
  getTodayIdeas,
  getUnrankedIdeas,
  updateIdeaStatus,
  updateIdeaRank,
  insertSummary,
  getRecentSummaries,
};
