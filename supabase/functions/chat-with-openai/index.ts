// Supabase Edge Function to proxy OpenAI Chat API
// This keeps your OpenAI API key secure on the server
// Supports function calling (tools) for MCP integrations

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { requireFeature } from '../_shared/entitlements.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // 1. Validate user authentication
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'No authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Create Supabase client to verify user
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    )

    // 3. Get the authenticated user
    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser()

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 4. Check if user has access to OpenAI LLM feature
    const { allowed, response } = await requireFeature(
      supabaseClient,
      user.id,
      'openai_llm',
      corsHeaders
    )

    if (!allowed) {
      return response!
    }

    // 5. Parse request body
    const requestBody = await req.json()
    const { messages, model, temperature, max_tokens, tools, tool_choice } = requestBody

    if (!messages || !Array.isArray(messages)) {
      return new Response(
        JSON.stringify({ error: 'Messages array is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 6. Call OpenAI Chat API with server-side API key
    const openaiKey = Deno.env.get('OPENAI_API_KEY')
    if (!openaiKey) {
      console.error('OPENAI_API_KEY not configured')
      return new Response(
        JSON.stringify({ error: 'Service configuration error' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Build OpenAI request body
    const openaiRequestBody: Record<string, unknown> = {
      model: model || 'gpt-4o-mini',
      messages: messages,
      temperature: temperature ?? 0.7,
      max_tokens: max_tokens ?? 2000,
    }

    // Add tools if provided (for function calling / MCP)
    if (tools && Array.isArray(tools) && tools.length > 0) {
      openaiRequestBody.tools = tools
      openaiRequestBody.tool_choice = tool_choice || 'auto'
    }

    console.log(`Calling OpenAI with ${messages.length} messages, tools: ${tools?.length || 0}`)

    const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(openaiRequestBody),
    })

    if (!openaiResponse.ok) {
      const errorData = await openaiResponse.json()
      console.error('OpenAI API error:', errorData)
      return new Response(
        JSON.stringify({ error: 'OpenAI API error', details: errorData }),
        { status: openaiResponse.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const data = await openaiResponse.json()

    // Log if tool calls were made
    if (data.choices?.[0]?.message?.tool_calls) {
      console.log(`OpenAI returned ${data.choices[0].message.tool_calls.length} tool call(s)`)
    }

    // 7. Return response to client
    return new Response(
      JSON.stringify(data),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Error in chat-with-openai function:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error', message: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

