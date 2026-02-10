// Always start fresh on page load - clear stored user data
localStorage.clear();

const questions = [];
let selectedVibes = [];

const qsEl = document.getElementById('questions');
const startBtn = document.getElementById('start');
const nameEl = document.getElementById('name');
const onboardSection = document.getElementById('onboard');
const composer = document.getElementById('composer');
const imageInput = document.getElementById('image');
const messageEl = document.getElementById('message');
const sendBtn = document.getElementById('send');
const messagesEl = document.getElementById('messages');
const previewEl = document.getElementById('preview');
const settingsBtn = document.getElementById('settings-btn');
const settingsModal = document.getElementById('settings-modal');
const closeSettingsBtn = document.getElementById('close-settings');
const saveSettingsBtn = document.getElementById('save-settings');
const settingsNameInput = document.getElementById('settings-name');
const settingsAboutInput = document.getElementById('settings-about');
const settingsSamplesInput = document.getElementById('settings-samples');
const soundToggle = document.getElementById('sound-toggle');
const hapticToggle = document.getElementById('haptic-toggle');
const clearHistoryBtn = document.getElementById('clear-history');
const resetProfileBtn = document.getElementById('reset-profile');
const contextModal = document.getElementById('context-modal');
const skipContextBtn = document.getElementById('skip-context');
const sendWithContextBtn = document.getElementById('send-with-context');
const msgLengthSlider = document.getElementById('msg-length');
const emojiSlider = document.getElementById('emoji-usage');
const flirtSlider = document.getElementById('flirtiness');

let userId = localStorage.getItem('visageUserId') || null;
let selectedImage = null;
let userMessageCount = parseInt(localStorage.getItem('messageCount')) || 0;
let responseStyle = localStorage.getItem('responseStyle') || 'normal';
let userName = localStorage.getItem('userName') || '';
let userAbout = localStorage.getItem('userAbout') || '';
let userSamples = localStorage.getItem('userSamples') || '';
let msgLength = localStorage.getItem('msgLength') || '2';
let emojiUsage = localStorage.getItem('emojiUsage') || '2';
let flirtiness = localStorage.getItem('flirtiness') || '1';
let soundEnabled = localStorage.getItem('soundEnabled') === 'true';
let hapticEnabled = localStorage.getItem('hapticEnabled') !== 'false';
let imageContext = { who: '', goal: '' };
let userWho = JSON.parse(localStorage.getItem('userWho') || '[]');
let userStruggles = JSON.parse(localStorage.getItem('userStruggles') || '[]');
let userPersonality = JSON.parse(localStorage.getItem('userPersonality') || '[]');

// Check if returning user and load profile
async function checkReturningUser() {
  if (!userId) return false;

  try {
    const res = await fetch(`/api/profile/${userId}`);
    if (!res.ok) {
      // Profile not found on server, clear local userId
      localStorage.removeItem('visageUserId');
      userId = null;
      return false;
    }

    const profile = await res.json();

    // Restore profile data
    userName = profile.name || '';
    userAbout = profile.about || '';
    userSamples = profile.textSamples || '';
    userWho = profile.who || [];
    userStruggles = profile.struggles || [];
    userPersonality = profile.personality || [];

    if (profile.style) {
      msgLength = profile.style.length || '2';
      emojiUsage = profile.style.emoji || '2';
      flirtiness = profile.style.flirt || '1';
    }

    // Update localStorage with server data
    localStorage.setItem('userName', userName);
    localStorage.setItem('userAbout', userAbout);
    localStorage.setItem('userSamples', userSamples);
    localStorage.setItem('msgLength', msgLength);
    localStorage.setItem('emojiUsage', emojiUsage);
    localStorage.setItem('flirtiness', flirtiness);
    localStorage.setItem('userWho', JSON.stringify(userWho));
    localStorage.setItem('userStruggles', JSON.stringify(userStruggles));
    localStorage.setItem('userPersonality', JSON.stringify(userPersonality));

    return true;
  } catch (e) {
    console.error('Failed to load profile:', e);
    return false;
  }
}

// Initialize app - check for returning user
(async function init() {
  // Check for reset parameter in URL
  if (window.location.search.includes('reset=true')) {
    localStorage.clear();
    window.location.href = window.location.pathname;
    return;
  }

  const isReturningUser = await checkReturningUser();

  if (isReturningUser) {
    // Skip onboarding, go straight to chat
    onboardSection.classList.add('hidden');
    composer.classList.remove('hidden');

    // Update settings inputs with loaded data
    settingsNameInput.value = userName;
    settingsAboutInput.value = userAbout;
    if (settingsSamplesInput) settingsSamplesInput.value = userSamples;
    if (msgLengthSlider) msgLengthSlider.value = msgLength;
    if (emojiSlider) emojiSlider.value = emojiUsage;
    if (flirtSlider) flirtSlider.value = flirtiness;
    updateSliderLabels();

    // Update chip selections
    setupChips('who-chips', 'userWho', userWho);
    setupChips('struggle-chips', 'userStruggles', userStruggles);
    setupChips('personality-chips', 'userPersonality', userPersonality);

    // Show welcome back message
    addMessage('ai', `hey ${userName || 'you'} 👋 welcome back. send me a screenshot or tell me what's going on`);
  }
})();

// Load saved settings
document.querySelector(`input[name="temperature"][value="${responseStyle}"]`).checked = true;
settingsNameInput.value = userName;
settingsAboutInput.value = userAbout;
if (settingsSamplesInput) settingsSamplesInput.value = userSamples;
soundToggle.checked = soundEnabled;
hapticToggle.checked = hapticEnabled;
if (msgLengthSlider) msgLengthSlider.value = msgLength;
if (emojiSlider) emojiSlider.value = emojiUsage;
if (flirtSlider) flirtSlider.value = flirtiness;

// Slider value displays
const lengthLabels = ['Short', 'Medium', 'Long'];
const emojiLabels = ['Never', 'Sometimes', 'Lots'];
const flirtLabels = ['None', 'Subtle', 'Very'];

function updateSliderLabels() {
  const lengthVal = document.getElementById('length-value');
  const emojiVal = document.getElementById('emoji-value');
  const flirtVal = document.getElementById('flirt-value');
  if (lengthVal) lengthVal.textContent = lengthLabels[msgLengthSlider.value - 1];
  if (emojiVal) emojiVal.textContent = emojiLabels[emojiSlider.value - 1];
  if (flirtVal) flirtVal.textContent = flirtLabels[flirtSlider.value - 1];
}
updateSliderLabels();

if (msgLengthSlider) msgLengthSlider.oninput = updateSliderLabels;
if (emojiSlider) emojiSlider.oninput = updateSliderLabels;
if (flirtSlider) flirtSlider.oninput = updateSliderLabels;

// Settings chips handlers
function setupChips(containerId, storageKey, initialValues) {
  const container = document.getElementById(containerId);
  if (!container) return;

  container.querySelectorAll('button').forEach(btn => {
    // Set initial state
    if (initialValues.includes(btn.dataset.value)) {
      btn.classList.add('selected');
    }

    btn.onclick = () => {
      btn.classList.toggle('selected');
    };
  });
}

setupChips('who-chips', 'userWho', userWho);
setupChips('struggle-chips', 'userStruggles', userStruggles);
setupChips('personality-chips', 'userPersonality', userPersonality);

function getChipValues(containerId) {
  const container = document.getElementById(containerId);
  if (!container) return [];
  return Array.from(container.querySelectorAll('button.selected')).map(b => b.dataset.value);
}

// Settings handlers
settingsBtn.onclick = () => {
  settingsModal.classList.remove('hidden');
};

closeSettingsBtn.onclick = () => {
  settingsModal.classList.add('hidden');
};

saveSettingsBtn.onclick = async () => {
  const selected = document.querySelector('input[name="temperature"]:checked');
  responseStyle = selected.value;
  userName = settingsNameInput.value.trim();
  userAbout = settingsAboutInput.value.trim();
  userSamples = settingsSamplesInput ? settingsSamplesInput.value.trim() : '';
  msgLength = msgLengthSlider ? msgLengthSlider.value : '2';
  emojiUsage = emojiSlider ? emojiSlider.value : '2';
  flirtiness = flirtSlider ? flirtSlider.value : '1';
  soundEnabled = soundToggle.checked;
  hapticEnabled = hapticToggle.checked;

  // Get chip selections
  userWho = getChipValues('who-chips');
  userStruggles = getChipValues('struggle-chips');
  userPersonality = getChipValues('personality-chips');

  localStorage.setItem('responseStyle', responseStyle);
  localStorage.setItem('userName', userName);
  localStorage.setItem('userAbout', userAbout);
  localStorage.setItem('userSamples', userSamples);
  localStorage.setItem('msgLength', msgLength);
  localStorage.setItem('emojiUsage', emojiUsage);
  localStorage.setItem('flirtiness', flirtiness);
  localStorage.setItem('soundEnabled', soundEnabled);
  localStorage.setItem('hapticEnabled', hapticEnabled);
  localStorage.setItem('userWho', JSON.stringify(userWho));
  localStorage.setItem('userStruggles', JSON.stringify(userStruggles));
  localStorage.setItem('userPersonality', JSON.stringify(userPersonality));

  // Update server profile if we have a userId
  if (userId) {
    try {
      await fetch('/api/profile', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          userId,
          name: userName,
          about: userAbout,
          textSamples: userSamples,
          who: userWho,
          struggles: userStruggles,
          personality: userPersonality,
          style: { length: msgLength, emoji: emojiUsage, flirt: flirtiness }
        })
      });
    } catch (e) {
      console.error('Failed to update profile', e);
    }
  }

  settingsModal.classList.add('hidden');
};

clearHistoryBtn.onclick = () => {
  if (confirm('Are you sure you want to clear your conversation history?')) {
    messagesEl.innerHTML = '';
    userMessageCount = 0;
  }
};

resetProfileBtn.onclick = () => {
  if (confirm('Are you sure you want to reset your profile? This will clear all your data.')) {
    userId = null;
    localStorage.clear();
    location.reload();
  }
};

// Vibe option click handlers
document.querySelectorAll('#vibe-options button').forEach(btn => {
  btn.onclick = () => {
    btn.classList.toggle('selected');
    const vibe = btn.dataset.vibe;
    if (btn.classList.contains('selected')) {
      if (!selectedVibes.includes(vibe)) selectedVibes.push(vibe);
    } else {
      selectedVibes = selectedVibes.filter(v => v !== vibe);
    }
  };
});

startBtn.onclick = async () => {
  const name = nameEl.value.trim();
  const vibeString = selectedVibes.join(', ');

  if (selectedVibes.length === 0) {
    alert('Please select at least one vibe');
    return;
  }

  // Save to localStorage
  if (name) {
    userName = name;
    localStorage.setItem('userName', name);
  }

  try {
    const res = await fetch('/api/onboard', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({
        answers: [vibeString],
        name,
        textSamples: userSamples,
        style: {
          length: msgLength,
          emoji: emojiUsage,
          flirt: flirtiness
        }
      })
    });
    const data = await res.json();
    userId = data.id;
    localStorage.setItem('visageUserId', userId);

    onboardSection.classList.add('hidden');
    composer.classList.remove('hidden');
    messagesEl.innerHTML = '';

    addTypingBubble();

    const initialRes = await fetch('/api/message', {
      method: 'POST',
      headers: {'Content-Type':'application/json'},
      body: JSON.stringify({ message: '', userId: userId, messageCount: 0, responseStyle })
    });
    const initialData = await initialRes.json();

    removeTypingBubble();

    if (initialData.reply) {
      addMessage('ai', initialData.reply);
    }
  } catch (err) {
    console.error('Onboarding error:', err);
    alert('Something went wrong. Please try again.');
  }
};

imageInput.onchange = () => {
  const f = imageInput.files[0];
  previewEl.innerHTML = '';
  selectedImage = null;
  imageContext = { who: '', goal: '' };
  if (!f) return;
  selectedImage = f;
  const img = document.createElement('img');
  img.src = URL.createObjectURL(f);
  previewEl.appendChild(img);
  previewEl.classList.remove('hidden');
  // Show context modal
  contextModal.classList.remove('hidden');
};

// Context modal handlers
document.querySelectorAll('#who-options button').forEach(btn => {
  btn.onclick = () => {
    document.querySelectorAll('#who-options button').forEach(b => b.classList.remove('selected'));
    btn.classList.add('selected');
    imageContext.who = btn.dataset.value;
  };
});

document.querySelectorAll('#goal-options button').forEach(btn => {
  btn.onclick = () => {
    document.querySelectorAll('#goal-options button').forEach(b => b.classList.remove('selected'));
    btn.classList.add('selected');
    imageContext.goal = btn.dataset.value;
  };
});

skipContextBtn.onclick = () => {
  contextModal.classList.add('hidden');
};

sendWithContextBtn.onclick = () => {
  contextModal.classList.add('hidden');
  sendBtn.click();
};

function addMessage(role, text, imageSrc) {
  const div = document.createElement('div');
  div.className = `message ${role}`;

  // If user sends image, show text above image (like iMessage)
  if (role === 'user' && imageSrc) {
    // Add text bubble first (above image) if there's actual text
    if (text && text !== '📷 Image') {
      const bubble = document.createElement('div');
      bubble.className = 'bubble';
      bubble.textContent = text;
      div.appendChild(bubble);
    }

    // Then add image below
    const imgWrap = document.createElement('div');
    imgWrap.className = 'image-message';
    const img = document.createElement('img');
    img.src = imageSrc;
    imgWrap.appendChild(img);
    div.appendChild(imgWrap);
  } else {
    const bubble = document.createElement('div');
    bubble.className = 'bubble';
    // Format text with proper line breaks
    bubble.innerHTML = text.replace(/\n/g, '<br>');

    if (imageSrc) {
      const img = document.createElement('img');
      img.src = imageSrc;
      bubble.appendChild(img);
    }

    div.appendChild(bubble);
  }

  messagesEl.appendChild(div);
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function addTypingBubble() {
  const div = document.createElement('div');
  div.className = 'message ai';
  div.id = 'typing-indicator';
  const bubble = document.createElement('div');
  bubble.className = 'bubble typing';
  bubble.innerHTML = '<span></span><span></span><span></span>';
  div.appendChild(bubble);
  messagesEl.appendChild(div);
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function removeTypingBubble() {
  const typing = document.getElementById('typing-indicator');
  if (typing) typing.remove();
}

sendBtn.onclick = async (e) => {
  e.preventDefault();
  const text = messageEl.value.trim();
  if (!text && !selectedImage) return;

  // Show user message with image if present
  const imagePreviewUrl = selectedImage ? URL.createObjectURL(selectedImage) : null;
  addMessage('user', text || '📷 Image', imagePreviewUrl);
  userMessageCount++;
  messageEl.value = '';

  sendBtn.disabled = true;

  // Natural delay before showing typing (1-2 seconds)
  await new Promise(resolve => setTimeout(resolve, 1000 + Math.random() * 1000));
  addTypingBubble();

  // Typing indicator shows for 2-4 seconds
  await new Promise(resolve => setTimeout(resolve, 2000 + Math.random() * 2000));

  const form = new FormData();
  if (selectedImage) form.append('image', selectedImage);
  form.append('message', text || '');
  form.append('userId', userId || '');
  form.append('messageCount', userMessageCount || '0');
  form.append('responseStyle', responseStyle);
  form.append('contextWho', imageContext.who || '');
  form.append('contextGoal', imageContext.goal || '');
  form.append('msgLength', msgLength);
  form.append('emojiUsage', emojiUsage);
  form.append('flirtiness', flirtiness);
  form.append('userSamples', userSamples);

  // Clear image selection immediately after adding to form
  const imageToSend = selectedImage;
  selectedImage = null;
  previewEl.innerHTML = '';
  previewEl.classList.add('hidden');
  imageInput.value = '';

  try {
    const res = await fetch('/api/message', { method: 'POST', body: form });
    const data = await res.json();

    removeTypingBubble();

    if (data.reply) {
      addMessage('ai', data.reply);
    }
  } catch (err) {
    removeTypingBubble();
    addMessage('ai', 'i had trouble with that. can you try again or tell me what\'s in it?');
  } finally {
    sendBtn.disabled = false;
  }
};

messageEl.addEventListener('keypress', (e) => {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    sendBtn.click();
  }
});
