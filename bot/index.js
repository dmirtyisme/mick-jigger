require('dotenv').config();

const TelegramBot = require('node-telegram-bot-api');
const {
  handleIdea,
  handleIdeas,
  handleRank,
  handleSummary,
  handleAnalyze,
  handleFilter,
  handleStatus,
  handleExport,
  handleHelp,
  handleMessage,
} = require('./commands');

const token = process.env.TELEGRAM_TOKEN;
if (!token) {
  console.error('TELEGRAM_TOKEN is not set');
  process.exit(1);
}

if (!process.env.ANTHROPIC_API_KEY) {
  console.error('ANTHROPIC_API_KEY is not set');
  process.exit(1);
}

const bot = new TelegramBot(token, { polling: true });

console.log('Mick Jigger bot starting...');

bot.onText(/^\/idea(?:@\w+)?(?:\s+(.+))?$/s, (msg, match) => {
  handleIdea(bot, msg, match[1] || '');
});

bot.onText(/^\/ideas(?:@\w+)?$/, (msg) => {
  handleIdeas(bot, msg);
});

bot.onText(/^\/rank(?:@\w+)?$/, (msg) => {
  handleRank(bot, msg);
});

bot.onText(/^\/summary(?:@\w+)?$/, (msg) => {
  handleSummary(bot, msg);
});

bot.onText(/^\/analyze(?:@\w+)?(?:\s+(.+))?$/, (msg, match) => {
  handleAnalyze(bot, msg, match[1] || '');
});

bot.onText(/^\/filter(?:@\w+)?(?:\s+(.+))?$/, (msg, match) => {
  handleFilter(bot, msg, match[1] || '');
});

bot.onText(/^\/status(?:@\w+)?(?:\s+(.+))?$/s, (msg, match) => {
  handleStatus(bot, msg, match[1] || '');
});

bot.onText(/^\/export(?:@\w+)?$/, (msg) => {
  handleExport(bot, msg);
});

bot.onText(/^\/help(?:@\w+)?$/, (msg) => {
  handleHelp(bot, msg);
});

bot.on('message', (msg) => {
  handleMessage(bot, msg);
});

bot.on('polling_error', (err) => {
  console.error('Polling error:', err.message);
});

bot.on('error', (err) => {
  console.error('Bot error:', err.message);
});

process.once('SIGINT', () => {
  console.log('Shutting down...');
  bot.stopPolling();
  process.exit(0);
});

process.once('SIGTERM', () => {
  console.log('Shutting down...');
  bot.stopPolling();
  process.exit(0);
});

console.log('Mick Jigger bot is running');
