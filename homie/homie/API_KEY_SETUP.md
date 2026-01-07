# OpenAI API Key Setup

To use the GPT functionality in Homie, you need to set up your OpenAI API key. Here are three ways to do this:

## Option 1: Environment Variable (Recommended)
1. Get your API key from [OpenAI Platform](https://platform.openai.com/api-keys)
2. Set the environment variable:
   ```bash
   export OPENAI_API_KEY="your-api-key-here"
   ```
3. Run your app from the terminal or add the environment variable to your IDE

## Option 2: Configuration File
1. Open `homie/config.plist`
2. Replace `sk-proj-YOUR_API_KEY_HERE` with your actual API key
3. Make sure NOT to commit this file to version control

## Option 3: Code (Not Recommended)
1. Open `homie/Config.swift`
2. Replace `sk-proj-YOUR_API_KEY_HERE` in the fallback return statement
3. Make sure NOT to commit this change to version control

## Important Notes:
- Never commit your API key to version control
- Your API key should start with `sk-proj-` or `sk-`
- The app will show an error message if the API key is invalid
- Check the Xcode console for detailed debugging information

## Troubleshooting:
- Make sure you've added the new files (`Config.swift` and `config.plist`) to your Xcode project
- Check that your API key is valid and has credits
- Look at the console output for specific error messages
- Ensure network permissions are enabled in the entitlements file 