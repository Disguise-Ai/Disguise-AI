require('dotenv').config();
const express = require('express');
const path = require('path');
const multer = require('multer');
const cors = require('cors');
const fs = require('fs');

let anthropicClient = null;
try {
  const Anthropic = require('@anthropic-ai/sdk');
  if (process.env.ANTHROPIC_API_KEY) {
    anthropicClient = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
    console.log('Anthropic client initialized successfully');
  } else {
    console.log('WARNING: ANTHROPIC_API_KEY not set - AI features will use fallbacks');
  }
} catch (e) {
  console.log('WARNING: Could not initialize Anthropic client:', e.message);
}

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));

const uploadsDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadsDir)) fs.mkdirSync(uploadsDir);

const dataDir = path.join(__dirname, 'data');
if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir);

const profilesFile = path.join(dataDir, 'profiles.json');

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadsDir),
  filename: (req, file, cb) => cb(null, Date.now() + '-' + file.originalname)
});
const upload = multer({ storage });

// Load profiles from disk or start fresh
let profiles = {};
if (fs.existsSync(profilesFile)) {
  try {
    profiles = JSON.parse(fs.readFileSync(profilesFile, 'utf-8'));
    console.log(`Loaded ${Object.keys(profiles).length} user profiles`);
  } catch (e) {
    console.error('Failed to load profiles:', e.message);
    profiles = {};
  }
}

// Save profiles to disk
function saveProfiles() {
  try {
    fs.writeFileSync(profilesFile, JSON.stringify(profiles, null, 2));
  } catch (e) {
    console.error('Failed to save profiles:', e.message);
  }
}

async function generateResponse(prompt) {
  if (!anthropicClient) return null;
  try {
    const res = await anthropicClient.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 150,
      system: `You're texting a friend who needs help with their conversations. Sound like a real person - not an AI, not a therapist, not customer service.

How to sound human:
- Use lowercase, minimal punctuation
- React naturally ("lol", "wait", "oh", "nah", "bet", "lowkey")
- Reference what they actually said, don't be generic
- Keep it short - 1-2 sentences max
- Don't explain yourself or use filler phrases like "I think" or "In my opinion"
- Never use phrases like "I understand" or "That makes sense" - just respond
- Be direct but warm, like you're texting your friend
- Match their energy - if they're stressed, acknowledge it briefly then help`,
      messages: [{ role: 'user', content: prompt }]
    });
    return res.content[0].text;
  } catch (e) {
    console.error('Anthropic error', e.message || e);
    return null;
  }
}

async function analyzeImage(imagePath, userMessage, profile, tone, context = {}) {
  if (!anthropicClient) return null;
  try {
    // Force fresh read of the image file - no caching
    const imageBuffer = fs.readFileSync(imagePath);
    const base64Image = imageBuffer.toString('base64');
    const ext = path.extname(imagePath).toLowerCase();
    const mimeType = ext === '.png' ? 'image/png' : ext === '.gif' ? 'image/gif' : ext === '.webp' ? 'image/webp' : 'image/jpeg';

    // Log image details to confirm we're reading fresh each time
    const imageHash = require('crypto').createHash('md5').update(imageBuffer).digest('hex').slice(0, 8);
    console.log(`\n📸 Analyzing NEW image: ${path.basename(imagePath)} | Hash: ${imageHash} | Size: ${imageBuffer.length} bytes`);

    const userName = profile.name || 'bro';
    const style = profile.style || {};

    const comesAcrossAs = profile.answers[0] || 'confident';
    const userPersonality = profile.personality || [];

    // Context from the 2 questions we asked
    const whoTheyreTexting = context.who || '';
    const whatTheyNeed = context.help || '';

    // Determine the vibe based on who they're texting
    let relationshipVibe = '';
    if (whoTheyreTexting.includes('crush') || whoTheyreTexting.includes('dating')) {
      relationshipVibe = 'this is someone they like so the stakes feel high. help them be smooth but not try-hard.';
    } else if (whoTheyreTexting.includes('ex')) {
      relationshipVibe = 'this is an ex so tread carefully. help them stay cool and unbothered, not desperate or bitter.';
    } else if (whoTheyreTexting.includes('friend') || whoTheyreTexting.includes('talking')) {
      relationshipVibe = 'this is casual so keep it light and natural. no pressure.';
    }

    // Build style instructions
    let styleVibe = '';
    if (style.flirt === '3') styleVibe = 'be flirty and playful. ';
    else if (style.flirt === '2') styleVibe = 'subtle flirting is ok. ';
    else styleVibe = 'keep it friendly, not too flirty. ';

    if (style.emoji === '3') styleVibe += 'emojis are cool. ';
    else if (style.emoji === '1') styleVibe += 'no emojis. ';

    if (style.length === '1') styleVibe += 'keep responses short - 1 line max.';
    else if (style.length === '3') styleVibe += 'can be a bit longer if needed.';
    else styleVibe += '1-2 sentences is perfect.';

    // Build personality context
    let personalityContext = '';
    if (profile.textSamples) {
      personalityContext = `\n\nHOW ${userName.toUpperCase()} ACTUALLY TEXTS (copy this style):\n"${profile.textSamples.slice(0, 200)}"`;
    }
    if (userPersonality.length > 0) {
      personalityContext += `\n\nTHEIR VIBE: ${userPersonality.join(', ')}`;
    }

    const systemPrompt = `You're ${userName}'s friend helping them figure out what to text back. Read the screenshot first.

HOW TO HELP:
1. Look at what the other person said (their last message in the screenshot)
2. Give a quick read on the vibe - is it going well or nah?
3. Give 2-3 reply options that actually respond to what they said

YOUR REPLY OPTIONS SHOULD:
- Actually respond to their message, not be generic
- Sound like real texts (lowercase, casual, no periods at the end)
- Give variety: one chill, one more confident, one playful
- Match how ${userName} texts if you know their style

HOW TO TALK TO ${userName.toUpperCase()}:
- Sound like their friend, not an AI or therapist
- Be direct - "ok so they said..." then get into it
- Use casual language (lol, nah, lowkey, bet, etc)
- Keep your commentary brief, focus on the options
- If the convo looks rough, be honest but helpful

${relationshipVibe}
${styleVibe}${personalityContext}`;

    // Build the user prompt based on context
    let contextIntro = '';
    if (whoTheyreTexting && whatTheyNeed) {
      contextIntro = `ok so this is ${whoTheyreTexting} and they need help with ${whatTheyNeed}. `;
    } else if (whoTheyreTexting) {
      contextIntro = `this is ${whoTheyreTexting}. `;
    }

    // Add unique request ID to prevent any caching
    const requestId = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);

    const userPrompt = `[${requestId}] ${contextIntro}

Read this screenshot carefully. I need help replying.

Tell me:
1. What did they say? (quote their last message from the image)
2. Is this going good or should I be worried?
3. Give me 2-3 replies that respond to what THEY said

Make sure your suggestions actually relate to their message, not just generic stuff.`;

    console.log(`📝 Request ${requestId}: Analyzing image...`);

    console.log(`📤 Sending image to Claude (${base64Image.length} base64 chars, type: ${mimeType})`);

    const res = await anthropicClient.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 600,
      system: systemPrompt,
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: mimeType, data: base64Image } },
          { type: 'text', text: userPrompt }
        ]
      }]
    });

    const response = res.content[0].text;
    console.log(`✅ AI Response received (${response.length} chars)`);
    console.log(`📄 Full response:\n${response}\n`);

    // Check if AI actually read the image
    if (response.toLowerCase().includes('they said') || response.toLowerCase().includes('their message')) {
      console.log(`✅ AI appears to have read the screenshot`);
    } else {
      console.log(`⚠️ AI may not have read the screenshot properly`);
    }

    return response;
  } catch (e) {
    console.error('Anthropic Vision error:', e.message || e);
    console.error('Full error:', JSON.stringify(e, null, 2));
    return null;
  }
}

function simpleHeuristicSuggestions(answers) {
  const passion = answers[0] || 'your interests';
  const connection = answers[1] || 'meaningful conversations';
  const summary = `Into ${passion}. Looking for ${connection}.`;
  const starters = [
    `so you're into ${passion}... what got you started with that?`,
    `${connection} - i respect that. what does that look like for you?`,
    `tell me more about the ${passion} thing, i'm curious`,
  ];
  return { summary, starters };
}

app.post('/api/onboard', async (req, res) => {
  const { answers = [], name, textSamples = '', style = {} } = req.body;
  const id = Date.now().toString(36);
  profiles[id] = {
    name: name || null,
    answers,
    textSamples,
    style: {
      length: style.length || '2',
      emoji: style.emoji || '2',
      flirt: style.flirt || '1'
    },
    who: [],
    struggles: [],
    personality: [],
    about: '',
    messages: [],
    createdAt: new Date().toISOString()
  };

  saveProfiles();
  res.json({ id });
});

// Get user profile
app.get('/api/profile/:userId', (req, res) => {
  const { userId } = req.params;
  const profile = profiles[userId];

  if (!profile) {
    // Return empty profile for new users (don't error)
    return res.json({
      id: userId,
      name: null,
      answers: [],
      textSamples: '',
      style: {},
      who: [],
      struggles: [],
      personality: [],
      about: '',
      hasCompletedOnboarding: false
    });
  }

  res.json({
    id: userId,
    name: profile.name,
    email: profile.email,
    answers: profile.answers || [],
    textSamples: profile.textSamples || '',
    style: profile.style || {},
    who: profile.who || [],
    struggles: profile.struggles || [],
    personality: profile.personality || [],
    about: profile.about || '',
    hasCompletedOnboarding: profile.hasCompletedOnboarding || false,
    // Deep personality settings
    responseStyle: profile.responseStyle,
    messageLength: profile.messageLength,
    emojiUsage: profile.emojiUsage,
    flirtiness: profile.flirtiness,
    noReplyThought: profile.noReplyThought,
    whenYouLikeSomeone: profile.whenYouLikeSomeone,
    whatKillsConvos: profile.whatKillsConvos,
    quietConvoResponse: profile.quietConvoResponse,
    biggestFear: profile.biggestFear,
    howThingsEnd: profile.howThingsEnd,
    confidenceLevel: profile.confidenceLevel,
    whatYouWant: profile.whatYouWant
  });
});

// Create or update user profile (from onboarding)
app.post('/api/profile', async (req, res) => {
  const { userId, email, name, about, textSamples, who, struggles, personality, style } = req.body;

  if (!userId) {
    return res.status(400).json({ error: 'userId required' });
  }

  // Create profile if it doesn't exist
  if (!profiles[userId]) {
    profiles[userId] = {
      createdAt: new Date().toISOString(),
      answers: [],
      messages: [],
      style: {}
    };
  }

  const profile = profiles[userId];

  // Update profile fields
  if (email !== undefined) profile.email = email;
  if (name !== undefined) profile.name = name;
  if (about !== undefined) profile.about = about;
  if (textSamples !== undefined) profile.textSamples = textSamples;
  if (who !== undefined) profile.who = who;
  if (struggles !== undefined) profile.struggles = struggles;
  if (personality !== undefined) {
    profile.personality = personality;
    // Also store in answers for compatibility
    if (personality.length > 0) {
      profile.answers = profile.answers || [];
      profile.answers[0] = personality.join(', ');
    }
  }
  if (style !== undefined) {
    profile.style = { ...profile.style, ...style };
  }

  profile.hasCompletedOnboarding = true;
  profile.updatedAt = new Date().toISOString();
  saveProfiles();

  console.log(`Profile saved for user ${userId}: ${profile.name || 'unnamed'}, vibes: ${profile.personality?.join(', ') || 'none'}`);

  res.json({ success: true });
});

// Update user settings (all the deep personality stuff)
app.post('/api/profile/settings', async (req, res) => {
  const { userId, ...settings } = req.body;

  if (!userId) {
    return res.status(400).json({ error: 'userId required' });
  }

  // Create profile if it doesn't exist
  if (!profiles[userId]) {
    profiles[userId] = {
      createdAt: new Date().toISOString(),
      answers: [],
      messages: [],
      style: {}
    };
  }

  const profile = profiles[userId];

  // Update all settings
  if (settings.name !== undefined) profile.name = settings.name;
  if (settings.textSamples !== undefined) profile.textSamples = settings.textSamples;
  if (settings.responseStyle !== undefined) profile.responseStyle = settings.responseStyle;
  if (settings.messageLength !== undefined) {
    profile.messageLength = settings.messageLength;
    profile.style = profile.style || {};
    profile.style.length = String(settings.messageLength);
  }
  if (settings.emojiUsage !== undefined) {
    profile.emojiUsage = settings.emojiUsage;
    profile.style = profile.style || {};
    profile.style.emoji = String(settings.emojiUsage);
  }
  if (settings.flirtiness !== undefined) {
    profile.flirtiness = settings.flirtiness;
    profile.style = profile.style || {};
    profile.style.flirt = String(settings.flirtiness);
  }
  if (settings.personality !== undefined) {
    profile.personality = settings.personality;
    if (settings.personality.length > 0) {
      profile.answers = profile.answers || [];
      profile.answers[0] = settings.personality.join(', ');
    }
  }

  // Deep personality insights - these help the AI understand how the user thinks
  if (settings.noReplyThought !== undefined) profile.noReplyThought = settings.noReplyThought;
  if (settings.whenYouLikeSomeone !== undefined) profile.whenYouLikeSomeone = settings.whenYouLikeSomeone;
  if (settings.whatKillsConvos !== undefined) profile.whatKillsConvos = settings.whatKillsConvos;
  if (settings.quietConvoResponse !== undefined) profile.quietConvoResponse = settings.quietConvoResponse;
  if (settings.biggestFear !== undefined) profile.biggestFear = settings.biggestFear;
  if (settings.howThingsEnd !== undefined) profile.howThingsEnd = settings.howThingsEnd;
  if (settings.confidenceLevel !== undefined) profile.confidenceLevel = settings.confidenceLevel;
  if (settings.whatYouWant !== undefined) profile.whatYouWant = settings.whatYouWant;

  profile.updatedAt = new Date().toISOString();
  saveProfiles();

  console.log(`Settings updated for user ${userId}`);

  res.json({ success: true });
});

// Get chat history for a user
app.get('/api/chat/:userId', async (req, res) => {
  const { userId } = req.params;

  if (!profiles[userId]) {
    return res.json({ chatHistory: [] });
  }

  const chatHistory = profiles[userId].chatHistory || [];
  res.json({ chatHistory });
});

// Save chat message
app.post('/api/chat', async (req, res) => {
  const { userId, message, isUser } = req.body;

  if (!userId || message === undefined) {
    return res.status(400).json({ error: 'userId and message required' });
  }

  if (!profiles[userId]) {
    profiles[userId] = {
      createdAt: new Date().toISOString(),
      answers: [],
      messages: [],
      chatHistory: [],
      style: {}
    };
  }

  if (!profiles[userId].chatHistory) {
    profiles[userId].chatHistory = [];
  }

  // Add message to chat history
  profiles[userId].chatHistory.push({
    id: Date.now().toString(),
    text: message,
    isUser: isUser,
    timestamp: new Date().toISOString()
  });

  // Keep only last 100 messages
  if (profiles[userId].chatHistory.length > 100) {
    profiles[userId].chatHistory = profiles[userId].chatHistory.slice(-100);
  }

  saveProfiles();

  res.json({ success: true });
});

// Clear chat history
app.delete('/api/chat/:userId', async (req, res) => {
  const { userId } = req.params;

  if (profiles[userId]) {
    profiles[userId].chatHistory = [];
    saveProfiles();
  }

  res.json({ success: true });
});

app.post('/api/message', upload.single('image'), async (req, res) => {
  const {
    message = '',
    userId = '',
    messageCount = 0,
    responseStyle = 'normal',
    contextWho = '',
    contextHelp = '',
    msgLength = '2',
    emojiUsage = '2',
    flirtiness = '1',
    userSamples = ''
  } = req.body;

  const msgNum = parseInt(messageCount) || 0;
  const profile = profiles[userId] || { answers: [], messages: [], textSamples: '', style: {} };

  // Update profile with latest style preferences
  profile.style = { length: msgLength, emoji: emojiUsage, flirt: flirtiness };
  if (userSamples && !profile.textSamples) profile.textSamples = userSamples;

  if (!profile.messages) profile.messages = [];
  if (message && message.trim()) profile.messages.push(message);

  const imageInfo = req.file ? { path: `/uploads/${path.basename(req.file.path)}`, original: req.file.originalname, fullPath: req.file.path } : null;

  // Context for images (who they're texting and what help they need)
  const imageContext = { who: contextWho, help: contextHelp };

  // Define tone based on response style
  const toneGuide = {
    'normal': 'Keep the tone friendly, warm, and casual. Like texting a good friend.',
    'bold': 'Be confident and direct. Don\'t be afraid to make bold statements or give assertive suggestions.',
    'super-bold': 'Be daring and assertive. Push the conversation forward with strong energy and direct compliments.',
    'spicy': 'Be flirty and playful. Add some charm, wit, and subtle romantic energy. Keep it fun and enticing.'
  };
  
  const tone = toneGuide[responseStyle] || toneGuide['normal'];

  // Style preferences
  const style = profile.style || {};
  const lengthGuide = { '1': 'short (1 sentence)', '2': 'medium (1-2 sentences)', '3': 'longer (2-3 sentences)' };
  const emojiGuide = { '1': 'no emojis', '2': 'occasional emoji', '3': 'use emojis freely' };
  const flirtGuide = { '1': 'friendly only', '2': 'subtly flirty', '3': 'openly flirty' };
  const styleInstructions = `LENGTH: ${lengthGuide[style.length] || lengthGuide['2']} | EMOJIS: ${emojiGuide[style.emoji] || emojiGuide['2']} | FLIRT: ${flirtGuide[style.flirt] || flirtGuide['1']}`;

  // If image was uploaded, analyze it
  if (imageInfo && imageInfo.fullPath) {
    const imageAnalysis = await analyzeImage(imageInfo.fullPath, message, profile, tone, imageContext);
    if (imageAnalysis) {
      return res.json({ reply: imageAnalysis, image: { path: imageInfo.path, original: imageInfo.original } });
    }
    // Fallback if image analysis fails
    return res.json({
      reply: "i can see you sent something but i'm having trouble reading it rn. can you tell me what's going on or try sending it again?",
      image: { path: imageInfo.path, original: imageInfo.original }
    });
  }

  let prompt;

  const userName = profile.name || null;
  const nameIntro = userName ? `${userName.toLowerCase()}, ` : '';

  const comesAcrossAs = profile.answers[0] || 'confident';

  if (!message) {
    // Message 1: Greet by name, acknowledge vibe, ask first natural question
    prompt = `${userName ? `${userName}` : 'Someone'} just joined. They want to come across as: "${comesAcrossAs}"

VIBE: ${tone}

Write a natural, friendly first message (2-3 sentences) that:
1. Greet them by name (or just "hey" if no name)
2. Acknowledge their vibe naturally - like "oh ${comesAcrossAs}? i can work with that"
3. Ask ONE casual question to get to know them better - something like who they're usually texting or what kind of situations they need help with

Frame it like a friend asking, NOT like an interview. Use "so" or "oh" to start questions - feels more natural.

Examples of natural questions:
- "so who's usually on the other end of these convos... crush? someone from an app?"
- "what kind of situations do you usually need help with - starting convos, keeping them going, what?"

Don't mention settings yet. Just get to know them first. lowercase, casual.`;
  } else if (msgNum === 1) {
    // Message 2: React naturally, ask second follow-up to learn more
    prompt = `You're talking to ${userName || 'someone'} who wants to come across as: "${comesAcrossAs}"

They just told you: "${message}"

VIBE: ${tone}

Write a natural response (2-3 sentences) that:
1. React to what they said - be genuine, not generic ("oh nice" or "okay cool" type reactions)
2. Ask ONE more follow-up question to understand them better - maybe about their texting style, what they struggle with, or what their goal usually is

Keep it conversational. You're getting to know them so you can help better. After this you'll get straight to helping.

Frame like a friend, not an interviewer. lowercase.`;
  } else if (msgNum === 2) {
    // Message 3: Acknowledge, mention settings, and get ready to help
    prompt = `You now know ${userName || 'this person'}:
- Wants to come across as: "${comesAcrossAs}"
- Context from convo: "${profile.messages.slice(-2).join(' → ')}"

VIBE: ${tone}

Write a short message (2 sentences max) that:
1. Quick acknowledgment of what they shared
2. Tell them you're ready - ask them to send a screenshot or describe what's happening
3. Mention that the more they fill out in settings, the better you can match their actual texting style

Be direct now. You know enough about them. Time to help. lowercase.`;
  } else {
    // Regular conversation - help them directly
    const recentMsgs = profile.messages.slice(-4);
    const userPersonality = profile.personality || [];
    const userStruggles = profile.struggles || [];

    // Build personality context
    let personalityContext = '';
    if (profile.noReplyThought) personalityContext += ` When no reply: "${profile.noReplyThought}".`;
    if (profile.whenYouLikeSomeone) personalityContext += ` When they like someone: "${profile.whenYouLikeSomeone}".`;
    if (profile.whatKillsConvos) personalityContext += ` What kills their convos: "${profile.whatKillsConvos}".`;
    if (profile.confidenceLevel) personalityContext += ` Confidence: "${profile.confidenceLevel}".`;
    if (profile.whatYouWant) personalityContext += ` Looking for: "${profile.whatYouWant}".`;

    prompt = `You're ${userName || 'someone'}'s friend helping them text. Talk like you're texting them back.

about them: ${comesAcrossAs} vibe${userPersonality.length > 0 ? `, ${userPersonality.join(', ')}` : ''}${profile.textSamples ? `. texts like: "${profile.textSamples.slice(0, 100)}"` : ''}${personalityContext}

they said: "${message}"

VIBE: ${tone}
STYLE: ${styleInstructions}

respond like their friend would - give your honest take on the situation and a few options they could send. tell them which one you'd go with.

rules:
- no bullet points or numbered lists, just talk naturally
- lowercase, casual punctuation
- keep it brief - you're texting, not writing an essay
- the replies you suggest should sound like ${userName || 'them'}, not you
- be real with them - if something seems off, say it
- don't say "I think" or "In my opinion" - just say it`;
  }

  let ai = await generateResponse(prompt);
  if (ai) return res.json({ reply: ai, image: imageInfo });

  // Fallbacks based on response style
  const lastMsg = message ? message.toLowerCase() : '';
  const words = lastMsg.split(' ').filter(w => w.length > 3);
  const keyword = words[Math.floor(Math.random() * words.length)] || 'that';
  const onboardingRef = profile.answers[0] ? profile.answers[0].slice(0, 30) : 'what you shared';
  const nameGreet = profile.name ? `${profile.name.toLowerCase()}, ` : '';

  const vibeAnswer = profile.answers[0] ? profile.answers[0].slice(0, 25) : 'confident';

  const fallbacksByStyle = {
    'normal': {
      msg1: [
        `hey ${nameGreet}${vibeAnswer} - i like that. so who are you usually texting... crush? someone from an app? ex?`,
        `${nameGreet}oh ${vibeAnswer} vibes? i can work with that. so what kind of situations do you usually need help with?`,
      ],
      msg2: [
        `oh okay that makes sense. and when you text are you more short and sweet or do you go in with longer messages?`,
        `got it got it. so what's usually your struggle - starting convos, keeping them going, knowing what to say?`,
      ],
      msg3: [
        `perfect i think i got a feel for you. send me a screenshot or tell me what's happening and i'll help. btw fill out settings with examples of how you text and my responses will sound even more like you`,
      ],
      help: [
        `okay so what do you want to say back?`,
        `got it. want me to give you some options?`,
        `so what's the goal here - just respond well or you trying to make something happen?`,
      ]
    },
    'bold': {
      msg1: [
        `${nameGreet}${vibeAnswer} - respect. who's usually on the other end of these texts?`,
        `hey ${nameGreet}${vibeAnswer}? okay i see you. so what kind of help you usually need?`,
      ],
      msg2: [
        `oh okay. you more of a short texter or you write paragraphs?`,
        `got it. what's your weak spot - starting convos? flirting? what?`,
      ],
      msg3: [
        `bet. send me a screenshot or tell me what's up. settings = better responses btw`,
      ],
      help: [
        `what do you want to say`,
        `want me to give you options?`,
        `what's the play`,
      ]
    },
    'super-bold': {
      msg1: [
        `${nameGreet}${vibeAnswer} - let's go. who are we texting?`,
        `hey ${nameGreet}${vibeAnswer}. what kind of situations you need help with?`,
      ],
      msg2: [
        `okay. short texter or paragraphs?`,
        `got it. what do you struggle with most?`,
      ],
      msg3: [
        `say less. send me the screenshot or tell me what's happening. fill out settings for better responses`,
      ],
      help: [
        `what do you need`,
        `want options?`,
        `what's the move`,
      ]
    },
    'spicy': {
      msg1: [
        `hey ${nameGreet}${vibeAnswer}... i like it 😏 so who's the lucky person you're usually texting?`,
        `${nameGreet}oh ${vibeAnswer}? this is gonna be fun 🌶️ what kind of help you usually need?`,
      ],
      msg2: [
        `okay okay 👀 and when you text are you playing it cool or going for it?`,
        `got it 😏 what's your weak spot - being too nice? not flirty enough?`,
      ],
      msg3: [
        `perfect. send me what you got and let's make something happen. fill out settings for even spicier responses 🌶️`,
      ],
      help: [
        `so what do you want to say 👀`,
        `want me to give you some options? 😏`,
        `what's the goal here 🌶️`,
      ]
    }
  };

  const styleFallbacks = fallbacksByStyle[responseStyle] || fallbacksByStyle['normal'];

  let reply;
  if (!message) {
    reply = styleFallbacks.msg1[Math.floor(Math.random() * styleFallbacks.msg1.length)];
  } else if (msgNum === 1) {
    reply = styleFallbacks.msg2[Math.floor(Math.random() * styleFallbacks.msg2.length)];
  } else if (msgNum === 2) {
    reply = styleFallbacks.msg3[0];
  } else {
    reply = styleFallbacks.help[msgNum % styleFallbacks.help.length];
  }
    
  res.json({ reply, image: imageInfo });
});

app.use('/uploads', express.static(uploadsDir));

app.get('/api/ping', (req, res) => res.json({ ok: true }));

// Serve keyboard extension page
app.get('/keyboard', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'keyboard.html'));
});

// ============================================
// KEYBOARD EXTENSION API ENDPOINTS
// ============================================

// Get quick suggestions based on context
app.post('/api/keyboard/suggest', async (req, res) => {
  const { context, userId, conversationType = 'dating' } = req.body;

  if (!context) {
    return res.status(400).json({ error: 'Context is required' });
  }

  const profile = profiles[userId] || { answers: [], style: {}, personality: [], struggles: [] };
  const userName = profile.name || 'someone';
  const vibes = profile.answers[0] || 'confident';
  const style = profile.style || {};
  const userPersonality = profile.personality || [];
  const userStruggles = profile.struggles || [];

  const lengthGuide = { '1': 'short (1 sentence)', '2': 'medium (1-2 sentences)', '3': 'longer (2-3 sentences)' };
  const emojiGuide = { '1': 'no emojis', '2': 'occasional emoji', '3': 'use emojis freely' };
  const flirtGuide = { '1': 'friendly only', '2': 'subtly flirty', '3': 'openly flirty' };

  // Build personality insights
  let personalityInsights = '';
  if (profile.confidenceLevel) personalityInsights += `\n- Confidence: ${profile.confidenceLevel}`;
  if (profile.whatYouWant) personalityInsights += `\n- Looking for: ${profile.whatYouWant}`;
  if (profile.whenYouLikeSomeone) personalityInsights += `\n- When they like someone: ${profile.whenYouLikeSomeone}`;

  const prompt = `You're helping ${userName} respond in a ${conversationType} conversation.

THEIR VIBE: ${vibes}
${userPersonality.length > 0 ? `PERSONALITY: ${userPersonality.join(', ')}` : ''}
${userStruggles.length > 0 ? `STRUGGLES WITH: ${userStruggles.join(', ')}` : ''}
${profile.textSamples ? `HOW THEY TEXT:\n${profile.textSamples}` : ''}
${personalityInsights ? `\nHOW THEY THINK:${personalityInsights}` : ''}

STYLE:
- Length: ${lengthGuide[style.length] || lengthGuide['2']}
- Emojis: ${emojiGuide[style.emoji] || emojiGuide['2']}
- Flirtiness: ${flirtGuide[style.flirt] || flirtGuide['1']}

CONTEXT:
${context}

Give exactly 3 different response options they could send. Each should:
- Sound like ${userName} (match their vibe, style, and how they actually text)
- Be natural and conversational
- Be the actual message to send

Format your response as JSON:
{"suggestions": ["response 1", "response 2", "response 3"]}

Just the JSON, nothing else.`;

  if (!anthropicClient) {
    // Fallback suggestions
    return res.json({
      suggestions: [
        "hey, that's actually really cool",
        "lol no way, tell me more",
        "wait i need to hear the full story"
      ]
    });
  }

  try {
    const response = await anthropicClient.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 300,
      messages: [{ role: 'user', content: prompt }]
    });

    const text = response.content[0].text;

    // Try to parse JSON
    try {
      const parsed = JSON.parse(text);
      if (parsed.suggestions && Array.isArray(parsed.suggestions)) {
        return res.json({ suggestions: parsed.suggestions.slice(0, 3) });
      }
    } catch (parseError) {
      // Try to extract suggestions from text
      const lines = text.split('\n').filter(l => l.trim().length > 0);
      const suggestions = lines.slice(0, 3).map(l => l.replace(/^\d+[\.\)]\s*/, '').replace(/^["']|["']$/g, ''));
      return res.json({ suggestions });
    }

    res.json({ suggestions: ["hey what's up", "that's interesting", "tell me more"] });
  } catch (error) {
    console.error('Keyboard suggest error:', error.message);
    res.json({
      suggestions: [
        "hey, that's cool",
        "lol nice",
        "wait really?"
      ]
    });
  }
});

// Analyze screenshot for keyboard/share extension
app.post('/api/keyboard/analyze-image', upload.single('image'), async (req, res) => {
  const { userId, goal = 'respond', contextWho = '', contextHelp = '' } = req.body;

  if (!req.file) {
    return res.status(400).json({ error: 'Image is required' });
  }

  const profile = profiles[userId] || { answers: [], style: {}, personality: [], struggles: [] };
  const style = profile.style || {};
  const userName = profile.name || 'someone';

  if (!anthropicClient) {
    return res.json({
      suggestions: [
        "hey what's good",
        "lol wait really",
        "that's actually pretty cool"
      ]
    });
  }

  try {
    // Force fresh read - no caching
    const imageBuffer = fs.readFileSync(req.file.path);
    const base64Image = imageBuffer.toString('base64');
    const ext = path.extname(req.file.path).toLowerCase();
    const mimeType = ext === '.png' ? 'image/png' : ext === '.gif' ? 'image/gif' : 'image/jpeg';

    // Log to confirm we're reading this specific image
    const imageHash = require('crypto').createHash('md5').update(imageBuffer).digest('hex').slice(0, 8);
    console.log(`\n⌨️ Keyboard analyzing NEW image: ${path.basename(req.file.path)} | Hash: ${imageHash} | Size: ${imageBuffer.length} bytes`);

    // Build style instructions
    let styleGuide = '';
    if (style.flirt === '3') styleGuide = 'can be flirty/playful. ';
    else if (style.flirt === '2') styleGuide = 'subtle flirting ok. ';
    if (style.emoji === '3') styleGuide += 'emojis welcome. ';
    else if (style.emoji === '1') styleGuide += 'no emojis. ';
    if (style.length === '1') styleGuide += 'keep it short.';
    else if (style.length === '3') styleGuide += 'can be longer.';

    // Relationship-specific instructions
    let relationshipGuide = '';
    if (contextWho.includes('crush') || contextWho.includes('dating')) {
      relationshipGuide = 'This is someone they like - be smooth, show interest, dont be desperate or try-hard.';
    } else if (contextWho.includes('ex')) {
      relationshipGuide = 'This is an ex - stay cool, unbothered, brief. No desperation or bitterness.';
    } else if (contextWho.includes('friend') || contextWho.includes('talking')) {
      relationshipGuide = 'Casual convo - keep it natural and light.';
    }

    // Text samples for style matching
    let textStyleGuide = '';
    if (profile.textSamples) {
      textStyleGuide = `\n\nMATCH THIS TEXTING STYLE:\n"${profile.textSamples.slice(0, 150)}"`;
    }

    const systemPrompt = `You analyze text message screenshots and generate replies.

IMPORTANT: You must READ the actual text in the image before responding.

Your response format MUST be:

THEIR MESSAGE: "[copy the exact text of their last message from the screenshot]"

REPLIES:
{"suggestions": ["reply 1", "reply 2", "reply 3"]}

Rules for replies:
- Each reply MUST respond to what they said in "THEIR MESSAGE"
- Be specific - reference their actual words/topic
- Sound human: lowercase, casual, 1-2 sentences
- 3 different vibes: chill, interested, playful
- NO generic responses like just "hey" or "that's cool"

${relationshipGuide}
${styleGuide}${textStyleGuide}`;

    // Unique request ID to prevent caching
    const requestId = Date.now().toString(36) + Math.random().toString(36).slice(2, 6);

    const userPrompt = `[${requestId}] Read this text conversation screenshot.

${contextWho ? `This is a ${contextWho}.` : ''} ${contextHelp ? `They want to ${contextHelp}.` : ''}

First, tell me: what is the other person's last message? (Read the actual text bubbles in the image - look for their most recent message)

Then give me 3 reply options in JSON format.

Format your response exactly like this:
THEIR MESSAGE: "[the exact text you read from their last message]"

{"suggestions": ["reply 1", "reply 2", "reply 3"]}`;

    console.log(`⌨️ Keyboard request ${requestId}: Sending to AI...`);
    console.log(`📤 Image: ${base64Image.length} base64 chars, type: ${mimeType}`);
    console.log(`📋 Context: who=${contextWho}, help=${contextHelp}`);

    const response = await anthropicClient.messages.create({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 350,
      system: systemPrompt,
      messages: [{
        role: 'user',
        content: [
          { type: 'image', source: { type: 'base64', media_type: mimeType, data: base64Image } },
          { type: 'text', text: userPrompt }
        ]
      }]
    });

    const text = response.content[0].text;
    console.log(`✅ Keyboard AI full response:\n${text}\n`);

    // Extract what the AI read from the image
    const theirMessageMatch = text.match(/THEIR MESSAGE:\s*"?([^"]+)"?/i);
    if (theirMessageMatch) {
      console.log(`📖 AI read their message as: "${theirMessageMatch[1]}"`);
    }

    // Extract JSON from response
    const jsonMatch = text.match(/\{[\s\S]*"suggestions"[\s\S]*\}/);
    if (jsonMatch) {
      try {
        const parsed = JSON.parse(jsonMatch[0]);
        if (parsed.suggestions && Array.isArray(parsed.suggestions)) {
          const validSuggestions = parsed.suggestions
            .filter(s => s && s.length > 3)
            .slice(0, 3);
          if (validSuggestions.length > 0) {
            console.log(`✅ Final suggestions: ${JSON.stringify(validSuggestions)}`);
            return res.json({ suggestions: validSuggestions });
          }
        }
      } catch (parseError) {
        console.log(`⚠️ JSON parse error: ${parseError.message}`);
      }
    }

    // Fallback: extract quoted strings that look like replies
    const quotes = text.match(/"([^"]{5,100})"/g);
    if (quotes && quotes.length >= 2) {
      const suggestions = quotes
        .map(q => q.replace(/"/g, ''))
        .filter(s =>
          s.length > 5 &&
          !s.toLowerCase().includes('their message') &&
          !s.toLowerCase().includes('suggestion') &&
          !s.toLowerCase().includes('reply ')
        )
        .slice(0, 3);
      if (suggestions.length > 0) {
        console.log(`✅ Extracted suggestions: ${JSON.stringify(suggestions)}`);
        return res.json({ suggestions });
      }
    }

    // Better fallbacks based on context
    if (contextWho.includes('crush') || contextWho.includes('dating')) {
      res.json({ suggestions: ["that's actually really cool", "wait tell me more about that", "lol you're interesting"] });
    } else if (contextWho.includes('ex')) {
      res.json({ suggestions: ["lol yeah", "that's cool", "nice"] });
    } else {
      res.json({ suggestions: ["lol wait really?", "that's actually pretty cool", "tell me more"] });
    }
  } catch (error) {
    console.error('Keyboard analyze error:', error.message);
    res.json({
      suggestions: [
        "hey what's good",
        "lol that's cool",
        "wait really?"
      ]
    });
  }
});

// ============================================
// PHONE AUTHENTICATION ENDPOINTS
// ============================================

// Store verification codes (in production, use Redis or database)
const verificationCodes = {};

// Generate 6-digit code
function generateCode() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// Send verification code
app.post('/api/auth/send-code', async (req, res) => {
  const { phone } = req.body;

  if (!phone) {
    return res.status(400).json({ error: 'phone number required' });
  }

  const code = generateCode();
  const expiresAt = Date.now() + 5 * 60 * 1000; // 5 minutes

  // Store the code
  verificationCodes[phone] = { code, expiresAt };

  // Try to send via Twilio if configured
  if (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_PHONE_NUMBER) {
    try {
      const twilio = require('twilio')(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
      await twilio.messages.create({
        body: `Your Disguise.AI code is: ${code}`,
        from: process.env.TWILIO_PHONE_NUMBER,
        to: phone
      });
      console.log(`SMS sent to ${phone}`);
      return res.json({ success: true });
    } catch (e) {
      console.error('Twilio error:', e.message);
      // Fall through to dev mode
    }
  }

  // Dev mode: log code to console
  console.log(`\n========================================`);
  console.log(`VERIFICATION CODE for ${phone}: ${code}`);
  console.log(`========================================\n`);

  res.json({ success: true, dev: true });
});

// Verify code
app.post('/api/auth/verify-code', (req, res) => {
  const { phone, code } = req.body;

  if (!phone || !code) {
    return res.status(400).json({ error: 'phone and code required' });
  }

  const stored = verificationCodes[phone];

  if (!stored) {
    return res.status(400).json({ error: 'no code sent to this number' });
  }

  if (Date.now() > stored.expiresAt) {
    delete verificationCodes[phone];
    return res.status(400).json({ error: 'code expired' });
  }

  if (stored.code !== code) {
    return res.status(400).json({ error: 'invalid code' });
  }

  // Code is valid - clean up and create/get user
  delete verificationCodes[phone];

  // Generate or retrieve user ID
  let userId = null;
  for (const [id, profile] of Object.entries(profiles)) {
    if (profile.phone === phone) {
      userId = id;
      break;
    }
  }

  if (!userId) {
    // Create new user
    userId = Date.now().toString(36) + Math.random().toString(36).substr(2, 5);
    profiles[userId] = {
      phone,
      createdAt: new Date().toISOString(),
      answers: [],
      messages: [],
      style: {}
    };
    saveProfiles();
  }

  console.log(`User verified: ${phone} -> ${userId}`);

  res.json({ success: true, userId });
});

// Get user by phone
app.get('/api/auth/user/:phone', (req, res) => {
  const { phone } = req.params;

  for (const [id, profile] of Object.entries(profiles)) {
    if (profile.phone === phone) {
      return res.json({ userId: id, profile });
    }
  }

  res.status(404).json({ error: 'user not found' });
});

app.listen(PORT, () => console.log(`Server listening on http://localhost:${PORT}`));
