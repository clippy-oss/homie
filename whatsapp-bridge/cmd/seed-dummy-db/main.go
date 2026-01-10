package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"os"
	"time"

	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	gormlogger "gorm.io/gorm/logger"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/repository"
)

func main() {
	// Default to a dummy database in the current directory
	dbPath := "dummy_whatsapp.db"
	if len(os.Args) > 1 {
		dbPath = os.Args[1]
	}

	fmt.Printf("Using database at: %s\n", dbPath)

	// Initialize database (don't remove it - we want to keep chats)
	db, err := initDatabase(dbPath)
	if err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Delete all messages but keep chats
	ctx := context.Background()
	if err := db.WithContext(ctx).Exec("DELETE FROM messages").Error; err != nil {
		log.Fatalf("Failed to delete messages: %v", err)
	}
	fmt.Println("Deleted all messages from database")

	// Generate dummy data
	if err := seedDummyData(db); err != nil {
		log.Fatalf("Failed to seed dummy data: %v", err)
	}

	fmt.Println("✅ Successfully regenerated messages for all chats!")
	fmt.Printf("Database location: %s\n", dbPath)
}

func initDatabase(dbPath string) (*gorm.DB, error) {
	db, err := gorm.Open(sqlite.Open(dbPath), &gorm.Config{
		Logger: gormlogger.Default.LogMode(gormlogger.Warn),
	})
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// Enable WAL mode for better concurrency
	db.Exec("PRAGMA journal_mode=WAL")

	// Auto-migrate models
	err = db.AutoMigrate(
		&repository.MessageModel{},
		&repository.ChatModel{},
	)
	if err != nil {
		return nil, fmt.Errorf("failed to migrate database: %w", err)
	}

	return db, nil
}

func seedDummyData(db *gorm.DB) error {
	rand.Seed(time.Now().UnixNano())

	// Dummy contact names
	contactNames := []string{
		"Alice Johnson",
		"Bob Smith",
		"Charlie Brown",
		"Diana Prince",
		"Eve Wilson",
		"Frank Miller",
		"Grace Lee",
		"Henry Davis",
		"Iris Chen",
		"Jack Taylor",
		"Kate Martinez",
		"Liam O'Brien",
		"Maria Garcia",
		"Noah Anderson",
		"Olivia White",
	}

	// Dummy group names
	groupNames := []string{
		"Family Group",
		"Work Team",
		"Book Club",
		"Travel Buddies",
		"Gaming Squad",
	}

	// Sample messages for variety
	sampleTexts := []string{
		"Hey! How are you doing?",
		"Just checking in 😊",
		"Can we meet tomorrow?",
		"Thanks for your help!",
		"See you later!",
		"That sounds great!",
		"Let me know when you're free",
		"Perfect! I'll be there",
		"Did you see the latest news?",
		"Have a great day!",
		"What time works for you?",
		"I'll send it over shortly",
		"Thanks for understanding",
		"Looking forward to it!",
		"Let's catch up soon",
		"Hope you're doing well",
		"Can you send me that file?",
		"See you at the meeting",
		"Thanks again!",
		"Talk to you later!",
	}

	// Create 10 chats (mix of private and group)
	chats := make([]*domain.Chat, 0, 10)
	now := time.Now()

	// 7 private chats
	for i := 0; i < 7; i++ {
		phoneNumber := fmt.Sprintf("1555%06d", 100000+i)
		chatJID := domain.MustParseJID(fmt.Sprintf("%s@s.whatsapp.net", phoneNumber))
		chat := &domain.Chat{
			JID:               chatJID,
			Type:              domain.ChatTypePrivate,
			Name:              contactNames[i],
			UnreadCount:       0, // Will be calculated from messages
			IsMuted:           rand.Float32() < 0.2, // 20% muted
			IsArchived:        rand.Float32() < 0.1,  // 10% archived
			IsPinned:          rand.Float32() < 0.3,  // 30% pinned
			LastMessageTime:   now, // Will be updated after messages are created
			LastMessageText:   "",  // Will be updated after messages are created
			LastMessageSender: "",  // Will be updated after messages are created
		}
		chats = append(chats, chat)
	}

	// 3 group chats
	for i := 0; i < 3; i++ {
		groupID := fmt.Sprintf("120363%08d@g.us", 10000000+i)
		chatJID := domain.MustParseJID(groupID)
		chat := &domain.Chat{
			JID:               chatJID,
			Type:              domain.ChatTypeGroup,
			Name:              groupNames[i],
			UnreadCount:       0, // Will be calculated from messages
			IsMuted:           rand.Float32() < 0.4, // 40% muted
			IsArchived:        false,
			IsPinned:          rand.Float32() < 0.2, // 20% pinned
			LastMessageTime:   now, // Will be updated after messages are created
			LastMessageText:   "",  // Will be updated after messages are created
			LastMessageSender: "",  // Will be updated after messages are created
		}
		chats = append(chats, chat)
	}

	// Load existing chats from database or create new ones
	chatRepo := repository.NewChatRepository(db)
	msgRepo := repository.NewMessageRepository(db)
	ctx := context.Background()

	// Try to load existing chats
	existingChats, err := chatRepo.GetAll(ctx, 100, 0)
	if err != nil {
		// If no chats exist, create them
		fmt.Println("No existing chats found, creating new chats...")
		for _, chat := range chats {
			if err := chatRepo.Upsert(ctx, chat); err != nil {
				return fmt.Errorf("failed to create chat %s: %w", chat.JID.String(), err)
			}
		}
	} else {
		// Use existing chats
		fmt.Printf("Found %d existing chats, will regenerate messages for them\n", len(existingChats))
		chats = existingChats
	}

	myJID := domain.MustParseJID("15551234567@s.whatsapp.net")

	for chatIndex, chat := range chats {
		// Generate 10-15 messages per chat
		numMessages := 10 + rand.Intn(6)
		
		var messages []*domain.Message
		var lastMessage *domain.Message

		// Generate messages in chronological order (oldest to newest)
		// Start from a point in the past and work forward with 10-60 minute intervals
		// Calculate how far back to start: (numMessages * max_interval) to ensure we don't go too far back
		// Use a reasonable starting point: 1-3 days ago
		daysAgo := 1 + rand.Intn(3)
		messageTime := now.Add(-time.Duration(daysAgo) * 24 * time.Hour)
		
		for j := 0; j < numMessages; j++ {
			// For the first message, use the calculated start time
			// For subsequent messages, add a random interval of 10-60 minutes
			if j > 0 {
				// Random interval between 10 minutes and 1 hour (60 minutes)
				intervalMinutes := 10 + rand.Intn(50) // 10 to 60 minutes
				messageTime = messageTime.Add(time.Duration(intervalMinutes) * time.Minute)
				
				// Ensure we don't go into the future - if we do, set it to a recent time
				if messageTime.After(now) {
					// Set to a random time in the last 30 minutes
					messageTime = now.Add(-time.Duration(rand.Intn(30)) * time.Minute)
				}
			}

			// Determine sender - vary the pattern
			var senderJID domain.JID
			var isFromMe bool
			
			// Special case: For Alice Johnson and Work Team, ensure more messages from others
			isAliceJohnson := chat.Type == domain.ChatTypePrivate && chat.Name == "Alice Johnson"
			isWorkTeam := chat.Type == domain.ChatTypeGroup && chat.Name == "Work Team"
			shouldHaveMultipleUnread := isAliceJohnson || isWorkTeam
			
			if shouldHaveMultipleUnread {
				// For these chats, ensure at least 60% of messages are from others
				// Especially the last few messages should be from others
				if j >= numMessages-3 {
					// Last 3 messages: 80% chance from others
					isFromMe = rand.Float32() < 0.2
				} else {
					// Other messages: 60% from others
					isFromMe = rand.Float32() < 0.4
				}
			} else {
				// For the last message, sometimes make it from the other person
				if j == numMessages-1 {
					// 60% chance last message is from other person
					isFromMe = rand.Float32() < 0.4
				} else {
					// For other messages, 40% from me
					isFromMe = rand.Float32() < 0.4
				}
			}

			if isFromMe {
				senderJID = myJID
			} else {
				if chat.Type == domain.ChatTypePrivate {
					senderJID = chat.JID
				} else {
					// Random group member
					phoneNumber := fmt.Sprintf("1555%06d", 100000+rand.Intn(100))
					senderJID = domain.MustParseJID(fmt.Sprintf("%s@s.whatsapp.net", phoneNumber))
				}
			}

			// Generate message ID
			messageID := fmt.Sprintf("3A%016X", rand.Uint64())

			// Determine message type (mostly text, some media)
			var msg *domain.Message
			messageTypeRoll := rand.Float32()

			if messageTypeRoll < 0.75 {
				// 75% text messages
				text := sampleTexts[rand.Intn(len(sampleTexts))]
				msg = domain.NewTextMessage(messageID, chat.JID, senderJID, text, messageTime, isFromMe)
			} else if messageTypeRoll < 0.85 {
				// 10% image messages
				msg = domain.NewMediaMessage(
					messageID, chat.JID, senderJID,
					domain.MessageTypeImage,
					"Check this out!",
					"https://example.com/image.jpg",
					"image/jpeg",
					"photo.jpg",
					int64(500000+rand.Intn(2000000)),
					messageTime,
					isFromMe,
				)
			} else if messageTypeRoll < 0.95 {
				// 10% video messages
				msg = domain.NewMediaMessage(
					messageID, chat.JID, senderJID,
					domain.MessageTypeVideo,
					"Here's the video",
					"https://example.com/video.mp4",
					"video/mp4",
					"video.mp4",
					int64(5000000+rand.Intn(10000000)),
					messageTime,
					isFromMe,
				)
			} else {
				// 5% document messages
				msg = domain.NewMediaMessage(
					messageID, chat.JID, senderJID,
					domain.MessageTypeDocument,
					"",
					"https://example.com/document.pdf",
					"application/pdf",
					"document.pdf",
					int64(100000+rand.Intn(5000000)),
					messageTime,
					isFromMe,
				)
			}

			// Set read status
			// Messages from me are always read
			// For messages from others: only the last message can be unread, all earlier messages are read
			// Special case: Alice Johnson (first private chat) and Work Team (second group chat) should have multiple unread messages
			// Note: isAliceJohnson, isWorkTeam, and shouldHaveMultipleUnread are already declared above
			
			if isFromMe {
				msg.IsRead = true
			} else {
				if shouldHaveMultipleUnread {
					// For Alice Johnson and Work Team: make the last 2-3 messages from others unread
					// We'll do a second pass after all messages are created to properly set this
					// For now, mark all messages from others as potentially unread
					// We'll fix this in a second pass below
					msg.IsRead = true // Will be updated in second pass
				} else {
					// Normal behavior: only the last message can be unread
					if j == numMessages-1 {
						// Last message from other: 50% chance it's unread
						msg.IsRead = rand.Float32() < 0.5
					} else {
						// All earlier messages from others are always read
						msg.IsRead = true
					}
				}
			}

			// Occasionally add a quoted message
			if rand.Float32() < 0.15 && j > 0 {
				// Quote a previous message (simplified - just use a placeholder)
				msg.QuotedMessageID = fmt.Sprintf("3A%016X", rand.Uint64())
			}

			messages = append(messages, msg)
			lastMessage = msg
		}

		// Second pass: For Alice Johnson and Work Team, ensure last 2-3 messages from others are unread
		isAliceJohnsonSecondPass := chat.Type == domain.ChatTypePrivate && chat.Name == "Alice Johnson"
		isWorkTeamSecondPass := chat.Type == domain.ChatTypeGroup && chat.Name == "Work Team"
		if isAliceJohnsonSecondPass || isWorkTeamSecondPass {
			// Count messages from others
			messagesFromOthers := make([]int, 0)
			for i, msg := range messages {
				if !msg.IsFromMe {
					messagesFromOthers = append(messagesFromOthers, i)
				}
			}
			
			// Make the last 2-3 messages from others unread
			if len(messagesFromOthers) > 0 {
				unreadCount := 2 + rand.Intn(2) // 2 or 3 unread messages
				if unreadCount > len(messagesFromOthers) {
					unreadCount = len(messagesFromOthers)
				}
				
				// Mark the last unreadCount messages from others as unread
				for i := len(messagesFromOthers) - unreadCount; i < len(messagesFromOthers); i++ {
					messages[messagesFromOthers[i]].IsRead = false
				}
			}
		}

		// Save all messages
		for _, msg := range messages {
			if err := msgRepo.Create(ctx, msg); err != nil {
				return fmt.Errorf("failed to create message: %w", err)
			}
		}

		// Calculate unread count: count unread messages from others
		unreadCount := 0
		for _, msg := range messages {
			if !msg.IsFromMe && !msg.IsRead {
				unreadCount++
			}
		}
		chat.UnreadCount = unreadCount

		// Update chat with actual last message info
		chat.LastMessageTime = lastMessage.Timestamp
		if lastMessage.Text != "" {
			chat.LastMessageText = lastMessage.Text
		} else if lastMessage.Caption != "" {
			chat.LastMessageText = lastMessage.Caption
		} else {
			chat.LastMessageText = "[" + string(lastMessage.Type) + "]"
		}
		
		if lastMessage.IsFromMe {
			chat.LastMessageSender = "me"
		} else {
			if chat.Type == domain.ChatTypePrivate {
				chat.LastMessageSender = chat.Name
			} else {
				// For groups, use sender's phone number or name
				chat.LastMessageSender = lastMessage.SenderJID.User
			}
		}

		// Save/update chat with correct last message info
		if err := chatRepo.Upsert(ctx, chat); err != nil {
			return fmt.Errorf("failed to update chat %s: %w", chat.JID.String(), err)
		}

		fmt.Printf("Created chat: %s (%s) with %d messages (last from %s, unread count: %d)\n", 
			chat.Name, chat.Type, numMessages, chat.LastMessageSender, chat.UnreadCount)
	}

	return nil
}

