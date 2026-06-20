const Anthropic = require('@anthropic-ai/sdk');
const fs = require('fs');
const path = require('path');

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const KNOWLEDGE_DIR = path.join(__dirname, '..', 'knowledge');

function loadKnowledgeBase() {
  if (!fs.existsSync(KNOWLEDGE_DIR)) return '';

  const files = fs.readdirSync(KNOWLEDGE_DIR).filter(f => f.endsWith('.md'));
  const sections = files.map(file => {
    const content = fs.readFileSync(path.join(KNOWLEDGE_DIR, file), 'utf8');
    return `## ${file.replace('.md', '')}\n\n${content}`;
  });

  return sections.join('\n\n---\n\n');
}

const KNOWLEDGE_BASE = loadKnowledgeBase();

const SYSTEM_PROMPT = `You are a product strategist for Mick Jigger — a native macOS menu bar utility that simulates user activity by periodically moving the cursor to prevent idle state, screen lock, and away status in communication tools.

Evaluate ideas strictly against product vision, roadmap, and identity. Be direct and critical. Do not suggest ideas outside the product scope. Focus on what actually serves the core user: a macOS power user who needs to keep their screen active without touching the machine.

Key principles to apply:
- Safety first: no unintended interactions
- Local only: no cloud, no accounts, no telemetry
- Minimal footprint: low CPU/memory
- One-click activation
- Does not fight the user

${KNOWLEDGE_BASE ? `---\n\nPRODUCT KNOWLEDGE BASE:\n\n${KNOWLEDGE_BASE}` : ''}`;

async function rankIdeas(ideas) {
  const ideasText = ideas.map(i =>
    `[${i.id}] (${i.category}) ${i.text} — by ${i.author}`
  ).join('\n');

  const response = await client.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 2048,
    system: SYSTEM_PROMPT,
    messages: [{
      role: 'user',
      content: `Rank these product ideas for Mick Jigger by importance/effort/urgency. For each idea, provide:
- priority (1-10, higher = more important)
- score (1-10, overall quality vs product vision)
- category (feature/bug/ux/marketing/other)
- brief justification (1 sentence)

Ideas to rank:
${ideasText}

Respond in this exact format for each idea (one per line):
[id] priority:X score:Y category:Z — justification`
    }]
  });

  return response.content[0].text;
}

async function summarizeIdeas(ideas, period = 'today') {
  const ideasText = ideas.map(i =>
    `[${i.id}] [${i.category}] [${i.status}] ${i.text} — by ${i.author}`
  ).join('\n');

  const response = await client.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 1024,
    system: SYSTEM_PROMPT,
    messages: [{
      role: 'user',
      content: `Summarize these product ideas submitted ${period}. Group by theme. Highlight the strongest ideas and flag anything that conflicts with product vision. Keep it concise — this is a team briefing.

Ideas:
${ideasText}`
    }]
  });

  return response.content[0].text;
}

async function analyzeIdea(idea) {
  const response = await client.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 1024,
    system: SYSTEM_PROMPT,
    messages: [{
      role: 'user',
      content: `Do a deep analysis of this product idea for Mick Jigger:

ID: ${idea.id}
Category: ${idea.category}
Status: ${idea.status}
Submitted by: ${idea.author}
Date: ${idea.created_at}

Idea: ${idea.text}

Analyze:
1. Alignment with product vision (does it fit our core purpose?)
2. Roadmap fit (V1/V2/V3 or never?)
3. Effort vs. impact estimate
4. Risks or conflicts with existing features
5. Verdict: accept / defer / reject — with one-line reason`
    }]
  });

  return response.content[0].text;
}

module.exports = { rankIdeas, summarizeIdeas, analyzeIdea };
