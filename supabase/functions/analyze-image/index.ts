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
      systemPrompt = `read the screenshot and give quick advice.
- one sentence about what's happening
- one basic reply suggestion
end with: "upgrade for personalized replies that match your style"`
    } else if (fromKeyboard) {
      // Keyboard needs just the reply options, no commentary
      systemPrompt = `Look at this text conversation screenshot. Give exactly 3 reply options.

RULES:
- Just give 3 options, no commentary or explanation
- Each option should be a complete text message ready to send
- lowercase, casual, like real texts
- variety: one chill, one confident, one playful
${contextWho ? `- they're texting: ${contextWho}` : ''}
${contextHelp ? `- they need help with: ${contextHelp}` : ''}
${textSamples ? `- match this style: "${textSamples.slice(0, 80)}"` : ''}

FORMAT (exactly like this):
1. "first option here"
2. "second option here"
3. "third option here"`
    } else {
      // Premium users get full personalized analysis
      const name = userName || 'friend'
      systemPrompt = `You're ${name}'s friend helping them text back. Look at the screenshot.

IMPORTANT: Address them by name (${name}) in your response! Start with something like "ok ${name}" or "yo ${name}" or "${name}," to make it personal.

VIBE CHECK:
- works for everyone - any gender, any orientation, any situation
- pick up on who they're talking to from context
- adapt your suggestions to fit

DO THIS:
1. Quick read: is this convo going well? what's the vibe?
2. Give 2-3 reply options they can literally copy and send

REPLY OPTIONS SHOULD BE:
- actual responses to what the other person said (not generic)
- lowercase, casual, like real texts
- variety: one chill option, one confident, one playful/flirty
${textSamples ? `- match their style: "${textSamples.slice(0, 100)}"` : ''}

keep your commentary SHORT. focus on giving them the options. format like:

yo ${name}, [quick vibe read - 1 sentence]

try these:
1. "actual reply text here"
2. "another option"
3. "third option"`
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
