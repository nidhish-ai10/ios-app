# Configuration Setup

## OpenAI API Key Setup

For security reasons, the OpenAI API key is not hardcoded in the source code. You need to set it up using one of these methods:

### Method 1: Environment Variable (Recommended)

1. In Xcode, go to **Product → Scheme → Edit Scheme**
2. Select **Run** from the left sidebar
3. Go to the **Arguments** tab
4. Under **Environment Variables**, add:
   - **Name**: `OPENAI_API_KEY`
   - **Value**: `your-actual-openai-api-key-here`

### Method 2: Local Development (Temporary)

1. Open `SayItDone/Services/OpenAIService.swift`
2. Find the line: `return "YOUR_OPENAI_API_KEY_HERE"`
3. Replace `YOUR_OPENAI_API_KEY_HERE` with your actual API key
4. **IMPORTANT**: Never commit this change to version control!

### Getting Your OpenAI API Key

1. Go to [OpenAI Platform](https://platform.openai.com/)
2. Sign in to your account
3. Navigate to **API Keys** section
4. Create a new API key
5. Copy the key (starts with `sk-`)

### Security Notes

- Never commit API keys to version control
- Use environment variables for production
- Consider using iOS Keychain for production apps
- Rotate your API keys regularly

## Testing

After setting up your API key, test the integration by:

1. Running the app
2. Speaking a question like "What's the weather?"
3. The app should process with GPT-4 and speak the response 