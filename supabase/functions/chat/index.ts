import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY')
    if (!ANTHROPIC_API_KEY) {
      throw new Error('ANTHROPIC_API_KEY not configured')
    }

    const { message, userId, responseStyle, isTrialUser, userName, personality, textSamples } = await req.json()

    // Build the system prompt
    let systemPrompt = `You're texting a friend who needs help with their conversations. Sound like a real person - not an AI, not a therapist, not customer service.

IMPORTANT - Be inclusive:
- This app is for everyone - all genders, all orientations
- Pick up on context clues to understand who they're texting (guy, girl, etc.)
- Don't assume - if unclear, use neutral language or ask naturally
- Adapt your advice based on who they're talking to and their situation

How to sound human:
- Use lowercase, minimal punctuation
- React naturally ("lol", "wait", "oh", "nah", "bet", "lowkey")
- Reference what they actually said, don't be generic
- Keep it short - 1-2 sentences max
- Don't explain yourself or use filler phrases like "I think" or "In my opinion"
- Never use phrases like "I understand" or "That makes sense" - just respond
- Be direct but warm, like you're texting your friend
- Match their energy - if they're stressed, acknowledge it briefly then help`

    // Trial users get basic responses
    let userPrompt = message
    if (isTrialUser === true || isTrialUser === 'true') {
      systemPrompt = `Give brief, generic texting advice. Keep it short (1-2 sentences). End with a subtle hint about upgrading for personalized suggestions.`
    } else {
      // Premium users get personalized responses
      if (userName) {
        systemPrompt += `\n\nUser's name: ${userName}`
      }
      if (personality && personality.length > 0) {
        systemPrompt += `\nTheir vibe: ${Array.isArray(personality) ? personality.join(', ') : personality}`
      }
      if (textSamples) {
        systemPrompt += `\nHow they text: "${textSamples.slice(0, 150)}"`
      }
    }

    // Call Claude API
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 300,
        system: systemPrompt,
        messages: [{ role: 'user', content: userPrompt }]
      })
    })

    if (!response.ok) {
      const error = await response.text()
      console.error('Anthropic API error:', error)
      throw new Error('Failed to get AI response')
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
      JSON.stringify({ error: error.message, reply: "couldn't connect rn. try again?" }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
