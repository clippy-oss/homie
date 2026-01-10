-- Update test data for AI summary examples
-- 1. Add messages with 1+ hour gap for Alice Johnson (one-on-one chat)
-- 2. Add messages from 6+ senders for Work Team group

-- For Alice Johnson: Add unread messages with 1+ hour gap
-- First message: 2 hours ago
-- Second message: 30 minutes ago (so 1.5 hours gap, which is > 1 hour)
INSERT INTO messages (
    id, chat_jid, sender_jid, type, text, caption, media_url, media_mime_type, 
    media_file_name, media_file_size, timestamp, is_from_me, is_read, 
    quoted_message_id, created_at, updated_at
) VALUES 
-- First unread message from Alice (2 hours ago)
(
    '3A0000000000000001',
    '1555100000@s.whatsapp.net',
    '1555100000@s.whatsapp.net',
    'text',
    'Hey, can you review the project proposal I sent? I need your feedback on the budget section.',
    NULL,
    NULL,
    NULL,
    NULL,
    0,
    datetime('now', '-2 hours'),
    0,
    0,
    NULL,
    datetime('now'),
    datetime('now')
),
-- Second unread message from Alice (30 minutes ago, so 1.5 hours after first)
(
    '3A0000000000000002',
    '1555100000@s.whatsapp.net',
    '1555100000@s.whatsapp.net',
    'text',
    'Also, are you free for a quick call tomorrow morning? I want to discuss the timeline.',
    NULL,
    NULL,
    NULL,
    NULL,
    0,
    datetime('now', '-30 minutes'),
    0,
    0,
    NULL,
    datetime('now'),
    datetime('now')
);

-- For Work Team: Add messages from 6+ different senders
-- Current senders: 3, need at least 3 more to get to 6+
-- Adding messages from senders: 1555100100, 1555100101, 1555100102, 1555100103, 1555100104, 1555100105

INSERT INTO messages (
    id, chat_jid, sender_jid, type, text, caption, media_url, media_mime_type, 
    media_file_name, media_file_size, timestamp, is_from_me, is_read, 
    quoted_message_id, created_at, updated_at
) VALUES 
-- Sender 1: 1555100100
(
    '3A0000000000000100',
    '12036310000001@g.us',
    '1555100100@s.whatsapp.net',
    'text',
    'I finished the backend API changes. Should I create a PR now?',
    NULL,
    NULL,
    NULL,
    NULL,
    0,
    datetime('now', '-35 minutes'),
    0,
    0,
    NULL,
    datetime('now'),
    datetime('now')
),
-- Sender 2: 1555100101
(
    '3A0000000000000101',
    '12036310000001@g.us',
    '1555100101@s.whatsapp.net',
    'text',
    'The design mockups are ready for review. Can everyone take a look?',
    NULL,
    NULL,
    NULL,
    NULL,
    0,
    datetime('now', '-30 minutes'),
    0,
    0,
    NULL,
    datetime('now'),
    datetime('now')
),
-- Sender 3: 1555100102
(
    '3A0000000000000102',
    '12036310000001@g.us',
    '1555100102@s.whatsapp.net',
    'text',
    'I found a bug in the authentication flow. Working on a fix.',
    NULL,
    NULL,
    NULL,
    NULL,
    0,
    datetime('now', '-25 minutes'),
    0,
    0,
    NULL,
    datetime('now'),
    datetime('now')
),
-- Sender 4: 1555100103
(
    '3A0000000000000103',
    '12036310000001@g.us',
    '1555100103@s.whatsapp.net',
    'text',
    'The QA team needs access to staging. Can someone help set that up?',
    NULL,
    NULL,
    NULL,
    NULL,
    0,
    datetime('now', '-20 minutes'),
    0,
    0,
    NULL,
    datetime('now'),
    datetime('now')
),
-- Sender 5: 1555100104
(
    '3A0000000000000104',
    '12036310000001@g.us',
    '1555100104@s.whatsapp.net',
    'text',
    'I updated the documentation with the new API endpoints.',
    NULL,
    NULL,
    NULL,
    NULL,
    0,
    datetime('now', '-15 minutes'),
    0,
    0,
    NULL,
    datetime('now'),
    datetime('now')
),
-- Sender 6: 1555100105
(
    '3A0000000000000105',
    '12036310000001@g.us',
    '1555100105@s.whatsapp.net',
    'text',
    'The deployment pipeline is ready. We can schedule the release for tomorrow.',
    NULL,
    NULL,
    NULL,
    NULL,
    0,
    datetime('now', '-10 minutes'),
    0,
    0,
    NULL,
    datetime('now'),
    datetime('now')
);

