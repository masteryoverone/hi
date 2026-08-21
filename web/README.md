# Hephaestus Web - Deployment Guide

A beautiful glass-morphism web interface for the Hephaestus Lua Obfuscator.

## Features

- Translucent glass UI with grid paper background
- Loading animations with blur effects
- Code editor with drag & drop file upload
- Copy to clipboard & download output
- No options - just paste and obfuscate

## Local Development

1. **Navigate to the web folder:**
   ```bash
   cd web
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Start the dev server:**
   ```bash
   npm run dev
   ```

4. **Open** http://localhost:3000

## Deploy to Vercel - Step by Step

### Step 1: Push to GitHub

```bash
cd "C:\Users\Raven\Documents\document\currently working on\Hephaestus"
git init
git add .
git commit -m "Add web interface"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/hephaestus.git
git push -u origin main
```

### Step 2: Connect to Vercel

1. Go to https://vercel.com/new
2. Import your GitHub repository
3. Vercel will auto-detect Next.js

### Step 3: Configure Build Settings

In Vercel project settings:

- **Framework Preset:** Next.js
- **Build Command:** `npm run build`
- **Output Directory:** `.next`
- **Install Command:** `npm install`

### Step 4: Set Environment Variables

No environment variables needed for basic functionality.

### Step 5: Deploy!

Click **Deploy** and Vercel will build and deploy your site.

## How It Works

The web interface calls `/api/obfuscate` which:
1. Receives the uploaded file or pasted code
2. Saves it to a temp file
3. Runs `lua cli.lua <file>` to obfuscate
4. Reads the output file
5. Returns the obfuscated code

## Project Structure

```
web/
├── app/
│   ├── layout.js          # Root layout
│   ├── page.js            # Main page component
│   ├── globals.css        # Global styles & animations
│   └── api/
│       └── obfuscate/
│           └── route.js   # API route for obfuscation
├── components/            # (if needed for future components)
├── scripts/
│   └── setup-lua.js       # Lua auto-setup script
├── public/                # Static assets
├── package.json
├── next.config.js
├── tailwind.config.js
├── postcss.config.js
├── vercel.json            # Vercel config
└── .gitignore
```

## Customization

- **Colors:** Edit `globals.css` CSS variables
- **Animations:** Edit `tailwind.config.js` keyframes
- **Layout:** Edit `app/page.js` component
