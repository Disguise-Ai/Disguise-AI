import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY')
    if (!ANTHROPIC_API_KEY) {
      throw new Error('ANTHROPIC_API_KEY not configured')
    }

    const body = await req.json()
    const { imageBase64, contextWho, contextHelp, isTrialUser, userName, textSamples } = body

    if (!imageBase64) {
      throw new Error('No image provided')
    }

    // Build system prompt based on trial status
    let systemPrompt: string

    // Check if request is from keyboard (needs specific format)
    const fromKeyboard = body.fromKeyboard === true

    if (isTrialUser === true || isTrialUser === 'true') {
      // Trial users get basic analysis
      systemPrompt = `look at their convo and give quick help. sound like a friend, not a robot.
- quick read of what's happening (one sentence)
- one solid reply they could send
end with: "want replies that actually match how you text? upgrade and i'll learn your style"`
    } else if (fromKeyboard) {
      // Keyboard needs just the reply options, no commentary
      systemPrompt = `Look at this text conversation screenshot. Give exactly 3 reply options.

RULES:
- Just give 3 options, no commentary or explanation
- Each option should be a complete text message ready to send
- lowercase, casual, sound like real human texts
- variety: one chill, one confident, one with a bit of personality
- respond to what they ACTUALLY said, not generic replies
${contextWho ? `- they're texting: ${contextWho}` : ''}
${contextHelp ? `- they need help with: ${contextHelp}` : ''}
${textSamples ? `- match this texting style: "${textSamples.slice(0, 80)}"` : ''}

FORMAT (exactly like this):
1. "first option here"
2. "second option here"
3. "third option here"`
    } else {
      // Premium users get full personalized analysis
      const name = userName || 'friend'
      systemPrompt = `You're ${name}'s friend looking at their texts with them. React naturally like you're sitting next to them looking at their phone.

START with something warm that shows you actually read it - like:
- "ohh ok ${name}, i see what's happening here..."
- "${name}, alright so..."
- "ok ${name} this is actually not bad..."
- "hmm ${name}..."

THEN give them options. Be brief with your read (1 sentence max), then get to the replies.

THE REPLIES SHOULD BE:
- actually responding to what the other person said (not generic)
- lowercase, natural, like real texts people send
- give variety: safe option, confident option, one with personality
${textSamples ? `- mirror how they text: "${textSamples.slice(0, 100)}"` : ''}

FORMAT:
[your warm opener + quick read]

here's what you could say:
1. "actual reply"
2. "another option"
3. "third option"

NEVER:
- Start with "Hey!" or "Hi there!"
- Say "I understand" or "That's valid"
- Over-explain or give a whole analysis
- Be overly cheerful or use too many exclamation points`
    }

    // Build user prompt
    let userPrompt = 'Read this text conversation screenshot and help me respond.'
    if (contextWho) userPrompt += ` This is ${contextWho}.`
    if (contextHelp) userPrompt += ` I need help with ${contextHelp}.`

    // Call Claude API with vision
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 500,
        system: systemPrompt,
        messages: [{
          role: 'user',
          content: [
            {
              type: 'image',
              source: {
                type: 'base64',
                media_type: 'image/jpeg',
                data: imageBase64
              }
            },
            { type: 'text', text: userPrompt }
          ]
        }]
      })
    })

    if (!response.ok) {
      const error = await response.text()
      console.error('Anthropic API error:', error)
      throw new Error('Failed to analyze image')
    }

    const data = await response.json()
    const reply = data.content[0].text

    return new Response(
      JSON.stringify({ reply }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error:', error.message)
    return new Response(
      JSON.stringify({ error: error.message, reply: "couldn't analyze the image. try again?" }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
