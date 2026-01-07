# Surreality Chat - Messaging Intelligence

A modern, interactive web application for messaging intelligence with a multi-step user onboarding process. The website features an animated landing page, user registration flow, and integration with Supabase for data management.

## 🌐 Live Website

The website is deployed and accessible at: **surreality.chat**

## 🚀 Features

### Landing Page (`index.html`)
- **Animated Title Display**: Rotating title images that change every 250ms
- **Interactive Music Player**: "Surreal Vibes" playlist with Spotify integration
- **Responsive Design**: Optimized for desktop, tablet, and mobile devices
- **Call-to-Action**: Direct phone dial functionality
- **Modern UI**: Clean, minimalist design with smooth animations

### User Onboarding Flow
1. **Phone Number Collection** (`login.html`)
   - Country code selection with flag dropdown
   - Phone number validation
   - Support for 40+ countries
   - User existence checking

2. **Name Collection** (`name.html`)
   - First and last name input
   - Form validation
   - Data persistence across steps

3. **Email Collection** (`gmail.html`)
   - Gmail address validation
   - Email format verification
   - Account completion

### Technical Features
- **Supabase Integration**: Real-time database operations
- **Local Storage**: Session persistence during onboarding
- **Responsive Design**: Mobile-first approach
- **Form Validation**: Client-side validation with real-time feedback
- **Error Handling**: Comprehensive error management

## 🛠️ Technology Stack

- **Frontend**: HTML5, CSS3, JavaScript (ES6+)
- **Backend**: Supabase (PostgreSQL)
- **Styling**: Custom CSS with modern design patterns
- **Icons**: SVG-based icons and waveforms
- **Music**: Spotify Web API integration

## 📁 Project Structure

```
surreality-website/
├── index.html              # Landing page with animated title
├── login.html              # Phone number collection
├── name.html               # Name collection form
├── gmail.html              # Email collection form
├── supabase-config.js      # Database configuration and API functions
├── surreality-website-deploy/  # Deployment files
│   ├── index.html
│   ├── Title 1-8.png       # Animated title images
│   └── waveform.mid.svg    # Waveform icon
├── Title 1-8.png           # Source title images
├── waveform.mid.svg        # Source waveform icon
└── README.md               # This file
```

## 🎨 Design Elements

### Visual Assets
- **Title Images**: 8 different animated title variations
- **Waveform Icon**: Custom SVG for the call-to-action button
- **Color Scheme**: Monochromatic with #1a1a1a primary color
- **Typography**: System fonts (-apple-system, BlinkMacSystemFont, Segoe UI)

### Interactive Elements
- **Hover Effects**: Smooth transitions and micro-interactions
- **Form Validation**: Real-time input validation
- **Loading States**: Disabled buttons until valid input
- **Responsive Breakpoints**: 768px and 480px

## 🗄️ Database Schema

The application uses Supabase with a `users` table containing:
- `id`: Primary key
- `session_id`: Unique identifier (phone_countrycode+number)
- `phone_number`: Full international phone number
- `first_name`: User's first name
- `last_name`: User's last name
- `email`: User's email address
- `started_onboarding`: Boolean flag
- `last_login`: Timestamp of last activity

## 🚀 Deployment

The website is deployed to **surreality.chat** via Namecheap hosting. The deployment process involves:

1. Uploading files to the web hosting directory
2. Ensuring all assets (images, CSS, JS) are properly linked
3. Configuring domain settings in Namecheap

## 🎵 Music Integration

The "Surreal Vibes" playlist includes curated tracks from:
- Floating Points
- Montee
- Kangding Ray
- Fred again..
- Rachel Portman
- Swedish House Mafia

Tracks are integrated via Spotify Web API with embedded players.

## 📱 Mobile Optimization

- **Responsive Breakpoints**: 768px and 480px
- **Touch-Friendly**: Large tap targets and smooth scrolling
- **Performance**: Optimized images and minimal JavaScript
- **Cross-Browser**: Compatible with modern mobile browsers

## 🔧 Development

### Local Development
1. Clone the repository
2. Open `index.html` in a web browser
3. Ensure all file paths are correct for local serving

### Supabase Setup
1. Create a Supabase project
2. Update `supabase-config.js` with your project credentials
3. Create the `users` table with the required schema

## 📄 License

This project is proprietary and confidential. All rights reserved.

## 🤝 Contributing

This is a private project. For any modifications or updates, please contact the development team.

---

**Surreality Chat** - Where messaging meets intelligence.
