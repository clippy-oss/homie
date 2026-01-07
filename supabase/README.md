# Supabase Edge Functions Setup

This directory contains secure Supabase Edge Functions that proxy OpenAI API requests. This architecture keeps your OpenAI API key secure on the server and prevents unauthorized usage.

## 🔒 Security Architecture

**Before (INSECURE):**
```
Client App → Get API Key → Call OpenAI Directly
           ↑ EXPOSED!    ↓ YOUR BILL!
```

**After (SECURE):**
```
Client App → Edge Function (with JWT) → OpenAI API
                        ↑               ↓
                  API Key stays here! (secure)
```

## 📁 Edge Functions

### 1. `chat-with-openai`
Proxies OpenAI chat completion requests for premium users.
- **Endpoint:** `/functions/v1/chat-with-openai`
- **Method:** POST
- **Auth:** Requires valid JWT token
- **Premium:** Yes

### 2. `transcribe-with-whisper`
Proxies OpenAI Whisper API transcription requests for premium users.
- **Endpoint:** `/functions/v1/transcribe-with-whisper`
- **Method:** POST
- **Auth:** Requires valid JWT token
- **Premium:** Yes

### 3. `get-user-status`
Returns user premium status (NO API keys returned).
- **Endpoint:** `/functions/v1/get-user-status`
- **Method:** POST
- **Auth:** Requires valid JWT token
- **Premium:** No

## 🚀 Deployment

### Prerequisites

1. **Install Supabase CLI:**
```bash
npm install -g supabase
```

2. **Login to Supabase:**
```bash
supabase login
```

3. **Link to your project:**
```bash
supabase link --project-ref YOUR_PROJECT_REF
```

You can find your project ref in your Supabase dashboard URL:
`https://app.supabase.com/project/YOUR_PROJECT_REF`

### Deploy All Functions

```bash
cd /path/to/homie
supabase functions deploy chat-with-openai
supabase functions deploy transcribe-with-whisper
supabase functions deploy get-user-status
```

### Deploy Individual Function

```bash
supabase functions deploy chat-with-openai
```

## 🔑 Environment Variables

The Edge Functions require the following environment variables to be set in your Supabase project:

### Required Variables

1. **OPENAI_API_KEY** - Your OpenAI API key
2. **SUPABASE_URL** - Automatically provided by Supabase
3. **SUPABASE_ANON_KEY** - Automatically provided by Supabase

### Set Environment Variables

**Option 1: Via Supabase Dashboard**
1. Go to your Supabase project dashboard
2. Navigate to Settings → Edge Functions
3. Add secrets:
   - Name: `OPENAI_API_KEY`
   - Value: `sk-proj-...` (your OpenAI API key)

**Option 2: Via CLI**
```bash
supabase secrets set OPENAI_API_KEY=sk-proj-your-key-here
```

**Verify secrets:**
```bash
supabase secrets list
```

## 🗄️ Database Schema

Your Supabase database should have a `users` table with the following columns:

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id),
  email TEXT NOT NULL,
  is_premium BOOLEAN DEFAULT FALSE,
  premium_expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read their own data
CREATE POLICY "Users can read own data"
ON users FOR SELECT
USING (auth.uid() = id);

-- Policy: Service role can manage all users
CREATE POLICY "Service role can manage users"
ON users FOR ALL
USING (auth.role() = 'service_role');
```

## 🧪 Testing Edge Functions

### Test chat-with-openai

```bash
curl -X POST \
  'https://YOUR_PROJECT_REF.supabase.co/functions/v1/chat-with-openai' \
  -H 'Authorization: Bearer YOUR_USER_JWT_TOKEN' \
  -H 'apikey: YOUR_SUPABASE_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [
      {"role": "user", "content": "Hello, how are you?"}
    ],
    "model": "gpt-4o-mini",
    "temperature": 0.7,
    "max_tokens": 500
  }'
```

### Test transcribe-with-whisper

```bash
curl -X POST \
  'https://YOUR_PROJECT_REF.supabase.co/functions/v1/transcribe-with-whisper' \
  -H 'Authorization: Bearer YOUR_USER_JWT_TOKEN' \
  -H 'apikey: YOUR_SUPABASE_ANON_KEY' \
  -F 'file=@/path/to/audio.wav' \
  -F 'model=whisper-1'
```

### Test get-user-status

```bash
curl -X POST \
  'https://YOUR_PROJECT_REF.supabase.co/functions/v1/get-user-status' \
  -H 'Authorization: Bearer YOUR_USER_JWT_TOKEN' \
  -H 'apikey: YOUR_SUPABASE_ANON_KEY'
```

## 📊 Monitoring & Logs

### View Function Logs

**Via Dashboard:**
1. Go to Supabase Dashboard
2. Navigate to Edge Functions
3. Select your function
4. View logs in real-time

**Via CLI:**
```bash
supabase functions logs chat-with-openai
supabase functions logs --tail  # Follow logs in real-time
```

### Monitor Usage

Track your OpenAI API usage through the OpenAI dashboard at:
https://platform.openai.com/usage

## 💰 Cost Considerations

### Supabase Edge Functions Pricing
- **Free tier:** 500,000 invocations/month
- **Pro tier:** 2,000,000 invocations/month + $2 per 1M additional

### OpenAI API Pricing (as of 2024)
- **GPT-4o-mini:** $0.150 / 1M input tokens, $0.600 / 1M output tokens
- **Whisper API:** $0.006 / minute of audio

### Typical Costs
- Chat completion: ~$0.001 - $0.01 per request
- Whisper transcription: ~$0.001 per 10-second recording

## 🔧 Troubleshooting

### "No authorization header" Error
- Ensure the client is passing the JWT token in the Authorization header
- Format: `Authorization: Bearer <token>`

### "Premium subscription required" Error
- User's `is_premium` field is `false` in the database
- Check and update the user's premium status

### "Service configuration error" Error
- `OPENAI_API_KEY` environment variable is not set
- Run: `supabase secrets set OPENAI_API_KEY=sk-proj-...`

### Function Timeout
- Edge Functions have a 60-second timeout
- For long-running tasks, consider breaking them into smaller requests

### Cold Starts
- First request after inactivity may be slower (~1-2 seconds)
- Subsequent requests are fast (<100ms)

## 🔄 Updating Functions

When you make changes to a function:

1. **Edit the function code** in `supabase/functions/<function-name>/index.ts`

2. **Test locally** (optional):
```bash
supabase functions serve chat-with-openai
```

3. **Deploy the updated function:**
```bash
supabase functions deploy chat-with-openai
```

4. **Verify deployment:**
```bash
supabase functions list
```

## 🛡️ Security Best Practices

1. ✅ **Never expose OpenAI API keys to clients**
2. ✅ **Always validate JWT tokens in Edge Functions**
3. ✅ **Check premium status before proxying requests**
4. ✅ **Rate limit requests per user (optional)**
5. ✅ **Monitor unusual usage patterns**
6. ✅ **Rotate API keys periodically**
7. ✅ **Use environment variables for secrets**

## 📚 Additional Resources

- [Supabase Edge Functions Docs](https://supabase.com/docs/guides/functions)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)
- [Deno Deploy Docs](https://deno.com/deploy/docs)

## ❓ Support

If you encounter issues:
1. Check the function logs: `supabase functions logs <function-name>`
2. Verify environment variables: `supabase secrets list`
3. Test with curl commands (see Testing section)
4. Check OpenAI API status: https://status.openai.com/

---

**Last Updated:** November 2024





