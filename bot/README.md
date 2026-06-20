# Mick Jigger — Telegram Idea Bot

Telegram group bot for managing product ideas with Claude-powered analysis.

## Setup

### 1. Install dependencies

```bash
cd ~/mick-jigger/bot
npm install
```

### 2. Configure environment

```bash
cp .env.example .env
nano .env  # fill in real tokens
```

Required values in `.env`:
- `TELEGRAM_TOKEN` — from [@BotFather](https://t.me/BotFather)
- `ANTHROPIC_API_KEY` — from console.anthropic.com
- `ALLOWED_CHAT_ID` — Telegram group ID (bot only responds in this chat)

To get your group's chat ID: add `@userinfobot` to the group and it will show the ID.

### 3. Start with PM2

```bash
cd ~/mick-jigger
pm2 start ecosystem.config.js
pm2 save
pm2 startup  # follow the printed command to enable auto-start on reboot
```

### 4. Verify

```bash
pm2 logs mick-jigger-bot
```

Send `/help` in the Telegram group — bot should respond.

## Commands

| Command | Description |
|---|---|
| `/idea [text]` | Save an idea |
| `💡 [text]` | Auto-save (message starting with idea emoji) |
| `/ideas` | All ideas grouped by category |
| `/filter [category]` | Filter by: feature, bug, ux, marketing, other |
| `/rank` | Claude ranks all unranked ideas (1–10) |
| `/summary` | Claude summarizes today's ideas, saves to DB |
| `/analyze [id]` | Deep analysis of one idea vs product vision |
| `/status [id] [status]` | Mark idea: accepted, rejected, reviewed, new |
| `/export` | All ideas as formatted text |
| `/help` | Show commands |

## Idea emoji triggers

Any message starting with one of these emojis is auto-saved as an idea:
`💡 🔥 🚀 💭 ✨ 🎯 📝`

Example: `💡 Add a hotkey to toggle jiggler from anywhere`

## Database

SQLite at `bot/data/ideas.db`. Two tables:

- `ideas` — all submitted ideas with category, priority, score, status
- `summaries` — AI-generated daily summaries

## Knowledge base

Claude reads all `.md` files from `../knowledge/` to build context about the product. Add or update files there to change what Claude knows.

## PM2 management

```bash
pm2 status                     # check running processes
pm2 logs mick-jigger-bot       # tail logs
pm2 restart mick-jigger-bot --update-env  # restart + reload env vars
pm2 stop mick-jigger-bot       # stop
pm2 delete mick-jigger-bot     # remove from PM2
```

## Deployment (after code changes)

```bash
ssh sqwerty@10.0.1.158
cd ~/mick-jigger
git pull
cd bot && npm install
pm2 restart mick-jigger-bot --update-env
pm2 logs mick-jigger-bot
```
