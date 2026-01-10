package domain

type Contact struct {
	JID          JID
	Name         string
	PushName     string
	BusinessName string
	PhoneNumber  string
	AvatarURL    string
}

func (c *Contact) DisplayName() string {
	if c == nil {
		return ""
	}
	if c.Name != "" {
		return c.Name
	}
	if c.PushName != "" {
		return c.PushName
	}
	if c.BusinessName != "" {
		return c.BusinessName
	}
	return c.PhoneNumber
}
