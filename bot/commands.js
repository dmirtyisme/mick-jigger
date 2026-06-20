const db = require('./db');
const { rankIdeas, summarizeIdeas, analyzeIdea } = require('./claude');

const VALID_CATEGORIES = ['feature', 'bug', 'ux', 'marketing', 'other'];
const VALID_STATUSES = ['accepted', 'rejected', 'reviewed', 'new'];

// Emoji triggers that auto-save as ideas
const IDEA_EMOJI_TRIGGERS = ['💡', '🔥', '🚀', '💭', '✨', '🎯', '📝'];

function isAllowedChat(chatId) {
  const allowed = process.env.ALLOWED_CHAT_ID;
  if (!allowed) return true;
  return String(chatId) === String(allowed);
}

function guessCategory(text) {
  const lower = text.toLowerCase();
  if (/bug|crash|fix|broken|error|fail/.test(lower)) return 'bug';
  if (/ui|ux|design|layout|look|feel|icon|color|font/.test(lower)) return 'ux';
  if (/market|promot|launch|user|grow|viral|share|review/.test(lower)) return 'marketing';
  if (/feature|add|support|allow|enable|option/.test(lower)) return 'feature';
  return 'other';
}

function formatIdea(idea) {
  const statusIcon = { new: '🆕', reviewed: '👀', accepted: '✅', rejected: '❌' }[idea.status] || '•';
  const priority = idea.priority ? ` P${idea.priority}` : '';
  const score = idea.score ? ` S${idea.score}` : '';
  return `${statusIcon} [${idea.id}]${priority}${score} ${idea.text}\n   _by ${idea.author}_`;
}

function groupByCategory(ideas) {
  const groups = {};
  for (const idea of ideas) {
    if (!groups[idea.category]) groups[idea.category] = [];
    groups[idea.category].push(idea);
  }
  return groups;
}

function formatGroupedIdeas(ideas) {
  if (ideas.length === 0) return 'Ідей не знайдено.';

  const groups = groupByCategory(ideas);
  const categoryEmoji = {
    feature: '🚀 Feature',
    bug: '🐛 Bug',
    ux: '🎨 UX',
    marketing: '📣 Marketing',
    other: '💬 Other',
  };

  return Object.entries(groups)
    .map(([cat, items]) => {
      const label = categoryEmoji[cat] || cat;
      const lines = items.map(formatIdea).join('\n');
      return `*${label}* (${items.length})\n${lines}`;
    })
    .join('\n\n');
}

async function handleIdea(bot, msg, text) {
  if (!isAllowedChat(msg.chat.id)) return;

  const ideaText = text.trim();
  if (!ideaText) {
    return bot.sendMessage(msg.chat.id, 'Використання: /idea [текст] — опиши свою ідею');
  }

  const category = guessCategory(ideaText);
  const result = db.insertIdea.run({
    text: ideaText,
    author: msg.from.first_name + (msg.from.last_name ? ` ${msg.from.last_name}` : ''),
    author_id: msg.from.id,
    chat_id: msg.chat.id,
    category,
  });

  bot.sendMessage(
    msg.chat.id,
    `✅ Ідея #${result.lastInsertRowid} збережена \\[${category}\\]\n_${ideaText}_`,
    { parse_mode: 'MarkdownV2' }
  );
}

async function handleIdeas(bot, msg) {
  if (!isAllowedChat(msg.chat.id)) return;

  const ideas = db.getAllIdeas.all();
  if (ideas.length === 0) {
    return bot.sendMessage(msg.chat.id, 'Ідей ще немає. Додай першу через /idea.');
  }

  const text = `*Всі ідеї* (${ideas.length})\n\n${formatGroupedIdeas(ideas)}`;
  bot.sendMessage(msg.chat.id, text, { parse_mode: 'Markdown' });
}

async function handleRank(bot, msg) {
  if (!isAllowedChat(msg.chat.id)) return;

  const ideas = db.getUnrankedIdeas.all();
  if (ideas.length === 0) {
    return bot.sendMessage(msg.chat.id, 'Всі ідеї вже мають пріоритети.');
  }

  const thinking = await bot.sendMessage(msg.chat.id, `⏳ Claude ранжує ${ideas.length} ідей...`);

  try {
    const result = await rankIdeas(ideas);

    // Parse ranking lines: [id] priority:X score:Y category:Z — justification
    const lines = result.split('\n').filter(l => l.match(/^\[(\d+)\]/));
    let updated = 0;

    for (const line of lines) {
      const idMatch = line.match(/^\[(\d+)\]/);
      const priorityMatch = line.match(/priority:(\d+)/i);
      const scoreMatch = line.match(/score:(\d+)/i);
      const categoryMatch = line.match(/category:(\w+)/i);

      if (!idMatch) continue;
      const id = parseInt(idMatch[1]);
      const priority = priorityMatch ? parseInt(priorityMatch[1]) : null;
      const score = scoreMatch ? parseInt(scoreMatch[1]) : null;
      const category = categoryMatch && VALID_CATEGORIES.includes(categoryMatch[1].toLowerCase())
        ? categoryMatch[1].toLowerCase()
        : null;

      const idea = db.getIdeaById.get(id);
      if (idea && (priority || score)) {
        db.updateIdeaRank.run(priority, score, category || idea.category, id);
        updated++;
      }
    }

    const ranked = `*Ранжування від Claude:*\n\n${result}\n\n_Оновлено ${updated} ідей._`;
    await bot.editMessageText(ranked, {
      chat_id: msg.chat.id,
      message_id: thinking.message_id,
      parse_mode: 'Markdown',
    });
  } catch (err) {
    console.error('Rank error:', err);
    bot.editMessageText(`❌ Помилка ранжування: ${err.message}`, {
      chat_id: msg.chat.id,
      message_id: thinking.message_id,
    });
  }
}

async function handleSummary(bot, msg) {
  if (!isAllowedChat(msg.chat.id)) return;

  const ideas = db.getTodayIdeas.all();
  if (ideas.length === 0) {
    return bot.sendMessage(msg.chat.id, 'Сьогодні ідей ще не було.');
  }

  const thinking = await bot.sendMessage(msg.chat.id, `⏳ Claude готує резюме за ${ideas.length} ідеями...`);

  try {
    const summary = await summarizeIdeas(ideas, 'today');

    db.insertSummary.run({ content: summary, period: 'today' });

    await bot.editMessageText(`*Резюме за сьогодні:*\n\n${summary}`, {
      chat_id: msg.chat.id,
      message_id: thinking.message_id,
      parse_mode: 'Markdown',
    });
  } catch (err) {
    console.error('Summary error:', err);
    bot.editMessageText(`❌ Помилка резюме: ${err.message}`, {
      chat_id: msg.chat.id,
      message_id: thinking.message_id,
    });
  }
}

async function handleAnalyze(bot, msg, args) {
  if (!isAllowedChat(msg.chat.id)) return;

  const id = parseInt(args.trim());
  if (!id || isNaN(id)) {
    return bot.sendMessage(msg.chat.id, 'Використання: /analyze [id] — наприклад /analyze 5');
  }

  const idea = db.getIdeaById.get(id);
  if (!idea) {
    return bot.sendMessage(msg.chat.id, `❌ Ідею #${id} не знайдено.`);
  }

  const thinking = await bot.sendMessage(msg.chat.id, `⏳ Claude аналізує ідею #${id}...`);

  try {
    const analysis = await analyzeIdea(idea);

    await bot.editMessageText(`*Аналіз ідеї #${id}*\n\n${analysis}`, {
      chat_id: msg.chat.id,
      message_id: thinking.message_id,
      parse_mode: 'Markdown',
    });
  } catch (err) {
    console.error('Analyze error:', err);
    bot.editMessageText(`❌ Помилка аналізу: ${err.message}`, {
      chat_id: msg.chat.id,
      message_id: thinking.message_id,
    });
  }
}

async function handleFilter(bot, msg, args) {
  if (!isAllowedChat(msg.chat.id)) return;

  const category = args.trim().toLowerCase();
  if (!VALID_CATEGORIES.includes(category)) {
    return bot.sendMessage(
      msg.chat.id,
      `Використання: /filter [категорія]\nДоступні категорії: ${VALID_CATEGORIES.join(', ')}`
    );
  }

  const ideas = db.getIdeasByCategory.all(category);
  if (ideas.length === 0) {
    return bot.sendMessage(msg.chat.id, `Ідей у категорії "${category}" немає.`);
  }

  const lines = ideas.map(formatIdea).join('\n');
  bot.sendMessage(msg.chat.id, `*${category}* (${ideas.length})\n\n${lines}`, {
    parse_mode: 'Markdown',
  });
}

async function handleStatus(bot, msg, args) {
  if (!isAllowedChat(msg.chat.id)) return;

  const parts = args.trim().split(/\s+/);
  const id = parseInt(parts[0]);
  const status = parts[1]?.toLowerCase();

  if (!id || !status || !VALID_STATUSES.includes(status)) {
    return bot.sendMessage(
      msg.chat.id,
      `Використання: /status [id] [${VALID_STATUSES.join('|')}]\nПриклад: /status 3 accepted`
    );
  }

  const idea = db.getIdeaById.get(id);
  if (!idea) {
    return bot.sendMessage(msg.chat.id, `❌ Ідею #${id} не знайдено.`);
  }

  db.updateIdeaStatus.run(status, id);

  const icon = { accepted: '✅', rejected: '❌', reviewed: '👀', new: '🆕' }[status];
  bot.sendMessage(msg.chat.id, `${icon} Ідея #${id} — статус *${status}*\n_${idea.text}_`, {
    parse_mode: 'Markdown',
  });
}

async function handleExport(bot, msg) {
  if (!isAllowedChat(msg.chat.id)) return;

  const ideas = db.getAllIdeas.all();
  if (ideas.length === 0) {
    return bot.sendMessage(msg.chat.id, 'Немає ідей для експорту.');
  }

  const lines = [
    `Mick Jigger — Експорт ідей`,
    `Дата: ${new Date().toISOString()}`,
    `Всього: ${ideas.length} ідей`,
    '',
    '---',
    '',
  ];

  const groups = groupByCategory(ideas);
  for (const [cat, items] of Object.entries(groups)) {
    lines.push(`## ${cat.toUpperCase()} (${items.length})`);
    for (const i of items) {
      lines.push(`[${i.id}] [P${i.priority || '-'}] [${i.status}] ${i.text}`);
      lines.push(`   від ${i.author}, ${i.created_at.split(' ')[0]}`);
      lines.push('');
    }
  }

  const exportText = lines.join('\n');

  if (exportText.length < 4000) {
    bot.sendMessage(msg.chat.id, `\`\`\`\n${exportText}\n\`\`\``, { parse_mode: 'Markdown' });
  } else {
    // Send as file for large exports
    const buffer = Buffer.from(exportText, 'utf8');
    bot.sendDocument(msg.chat.id, buffer, {}, {
      filename: `mick-jigger-ideas-${new Date().toISOString().split('T')[0]}.txt`,
      contentType: 'text/plain',
    });
  }
}

async function handleHelp(bot, msg) {
  if (!isAllowedChat(msg.chat.id)) return;

  const help = `*Mick Jigger Idea Bot*

*Додати ідею:*
/idea [текст] — зберегти ідею
💡 [текст] — автозбереження (повідомлення з emoji-ідеї)

*Перегляд:*
/ideas — всі ідеї по категоріях
/filter [категорія] — фільтр: feature, bug, ux, marketing, other

*AI-аналіз:*
/rank — Claude ранжує ідеї за важливістю
/summary — Claude робить резюме за сьогодні
/analyze [id] — глибокий аналіз конкретної ідеї

*Управління:*
/status [id] [accepted|rejected|reviewed|new] — змінити статус
/export — всі ідеї текстом

/help — це повідомлення`;

  bot.sendMessage(msg.chat.id, help, { parse_mode: 'Markdown' });
}

async function handleMessage(bot, msg) {
  if (!isAllowedChat(msg.chat.id)) return;
  if (!msg.text) return;

  const startsWithIdeaEmoji = IDEA_EMOJI_TRIGGERS.some(e => msg.text.startsWith(e));
  if (!startsWithIdeaEmoji) return;

  // Strip the leading emoji and any whitespace
  const text = msg.text.replace(/^[\u{1F300}-\u{1FFFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]+\s*/u, '').trim();
  if (!text) return;

  await handleIdea(bot, msg, text);
}

module.exports = {
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
};
