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

    const { imageBase64, contextWho, contextHelp, isTrialUser, userName, textSamples } = await req.json()

    if (!imageBase64) {
      throw new Error('No image provided')
    }

    // Build system prompt based on trial status
    let systemPrompt: string

    if (isTrialUser === true || isTrialUser === 'true') {
      // Trial users get basic analysis
      systemPrompt = `You analyze text message screenshots and give brief advice.
Give a VERY BASIC response:
1. Briefly say what's happening (1 sentence)
2. Give ONE generic reply suggestion
Keep it short. End with: "upgrade to premium for personalized replies that match your style"`
    } else {
      // Premium users get full personalized analysis
      systemPrompt = `You're ${userName || 'someone'}'s friend helping them figure out what to text back. Read the screenshot first.

IMPORTANT - Be inclusive:
- This app is for everyone - all genders, all orientations
- Pick up on context clues to understand who they're texting
- Don't assume - if unclear, use neutral language
- Adapt your advice based on who they're talking to

HOW TO HELP:
1. Look at what the other person said (their last message)
2. Give a quick read on the vibe - is it going well or nah?
3. Give 2-3 reply options that actually respond to what they said

YOUR REPLY OPTIONS SHOULD:
- Actually respond to their message, not be generic
- Sound like real texts (lowercase, casual)
- Give variety: one chill, one more confident, one playful
${textSamples ? `- Match this texting style: "${textSamples.slice(0, 100)}"` : ''}

Keep commentary brief, focus on the options.`
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
