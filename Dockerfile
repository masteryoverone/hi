FROM node:20-slim AS base
WORKDIR /app

# Install Lua 5.1 and build tools
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    lua5.1 gcc make libreadline-dev && \
    ln -sf /usr/bin/lua5.1 /usr/bin/lua && \
    rm -rf /var/lib/apt/lists/*

# Install web dependencies first (cache layer)
COPY web/package.json web/package-lock.json* web/
RUN cd web && npm install

# Copy Lua obfuscator source
COPY cli.lua .
COPY src/ src/
COPY modules/ modules/

# Stage lua-staging for the API route
COPY web/scripts/stage-lua.js web/scripts/
RUN cd web && node scripts/stage-lua.js

# Copy the rest of the web app
COPY web/ web/

# Build Next.js at image build time (skips setup-lua since Lua is via apt)
RUN cd web && node scripts/stage-lua.js && npx next build

EXPOSE 3000

WORKDIR /app/web
CMD ["npm", "start"]
