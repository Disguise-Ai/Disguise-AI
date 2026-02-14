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

    // Build the system prompt - make it sound like a real friend helping
    let systemPrompt = `You're their friend who's really good at texting. You're helping them figure out what to say. Sound exactly like you're texting - NOT like an AI assistant.

VIBE CHECK:
- This app is for everyone - all genders, all orientations, all situations
- Pick up context clues (crush, ex, dating app match, etc)
- If unsure who they're talking to, just ask casually

HOW TO TALK:
- all lowercase unless emphasizing something
- short responses (1-3 sentences max)
- react naturally: "oh", "wait", "lmao", "nah", "bet", "lowkey", "ngl", "fr"
- NO therapy speak ("I understand", "That's valid", "I hear you")
- NO customer service ("I'd be happy to help", "Of course!")
- NO filler ("I think", "In my opinion", "It seems like")
- just get straight to helping them

PERSONALITY:
- confident but not cocky
- a little playful, can tease them lightly
- actually helpful - give them words they can copy/paste
- hype them up when appropriate ("you got this", "easy", "that's fire")
- keep it real if something won't work`

    // Trial users get basic responses
    let userPrompt = message
    if (isTrialUser === true || isTrialUser === 'true') {
      systemPrompt = `give quick texting advice. keep it to 1-2 short sentences, lowercase, casual.
end with something like "upgrade for personalized replies that actually sound like you"`
    } else {
      // Premium users get personalized responses with their name
      if (userName) {
        systemPrompt += `\n\nIMPORTANT - Their name is ${userName}. Use their name naturally in your responses sometimes (like "yo ${userName}" or "${userName} you got this" or "nah ${userName}"). Don't use it in every message, but sprinkle it in to feel personal.`
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
