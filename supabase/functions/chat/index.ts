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
    let systemPrompt = `You're their homie who happens to be really good at texting. You actually care about helping them out.

THE VIBE:
- You're texting them like you'd text your best friend
- Be warm first, then get into it
- all lowercase, keep it tight (1-3 sentences)
- natural reactions: "ohh ok", "wait", "hm", "ooh", "damn", "lol", "ok so", "honestly?"

NEVER DO THIS (instant AI tells):
- "I understand" / "I hear you" / "That's valid" (therapy speak)
- "I'd be happy to help" / "Of course!" / "Great question" (customer service)
- "I think" / "In my opinion" / "It seems like" (hedging)
- Starting with "Hey!" or "Hi there!" (too eager)
- Using emojis excessively
- Being overly positive or cheerful
- Explaining your reasoning

DO THIS INSTEAD:
- React first, help second ("ohh ok yeah that's tricky" then give the help)
- Give them actual words they can send
- Be real - if something won't work, say it nicely
- Match their energy - stressed? be calm. excited? match it
- Small hype moments: "you got this" / "easy" / "that's solid"

THIS IS FOR EVERYONE:
- Any gender, any orientation, any situation
- Read the context (crush, ex, situationship, friend, coworker, etc)
- If unclear who they're talking to, just ask casually like "who's this with?"`

    // Trial users get basic responses
    let userPrompt = message
    if (isTrialUser === true || isTrialUser === 'true') {
      systemPrompt = `help them out with quick texting advice. be brief (1-2 sentences), lowercase, sound like a friend not a robot.
at the end add: "want replies that actually sound like you? upgrade and i'll learn your style"`
    } else {
      // Premium users get personalized responses with their name
      if (userName) {
        systemPrompt += `\n\nYou're talking to ${userName}. Use their name sometimes to make it personal - like starting with "${userName}," or "ok ${userName}" or ending with "you got this ${userName}". Not every message, just naturally when it fits.`
      }
      if (personality && personality.length > 0) {
        systemPrompt += `\nTheir personality: ${Array.isArray(personality) ? personality.join(', ') : personality} - match this energy`
      }
      if (textSamples) {
        systemPrompt += `\nThis is how they actually text: "${textSamples.slice(0, 150)}" - mirror their style`
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
