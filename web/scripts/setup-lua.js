const https = require('https');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const LUA_VERSION = '5.1.5';
const LUA_URL = `https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz`;
const LUA_DIR = path.join(__dirname, '..', 'lua');
const BIN_DIR = path.join(LUA_DIR, 'bin');
const LUA_BIN = path.join(BIN_DIR, 'lua');

function download(url, dest) {
    return new Promise((resolve, reject) => {
        const protocol = url.startsWith('https') ? https : http;
        protocol.get(url, (res) => {
            if (res.statusCode === 301 || res.statusCode === 302) {
                return download(res.headers.location, dest).then(resolve).catch(reject);
            }
            if (res.statusCode !== 200) {
                return reject(new Error(`Download failed: ${res.statusCode}`));
            }
            const file = fs.createWriteStream(dest);
            res.pipe(file);
            file.on('finish', () => { file.close(); resolve(); });
        }).on('error', reject);
    });
}

async function main() {
    // Skip if already exists
    if (fs.existsSync(LUA_BIN)) {
        console.log('Lua already installed at', LUA_BIN);
        return;
    }

    console.log(`Setting up Lua ${LUA_VERSION}...`);

    // Create directories
    if (!fs.existsSync(BIN_DIR)) {
        fs.mkdirSync(BIN_DIR, { recursive: true });
    }

    const tarFile = path.join(LUA_DIR, 'lua.tar.gz');

    // Download Lua source
    console.log(`Downloading Lua ${LUA_VERSION} from ${LUA_URL}...`);
    await download(LUA_URL, tarFile);
    console.log('Download complete.');

    // Extract
    console.log('Extracting...');
    try {
        execSync(`tar -xzf "${tarFile}"`, { cwd: LUA_DIR, stdio: 'inherit' });
    } catch {
        // Try alternative extraction for Windows
        try {
            execSync(`tar -xf "${tarFile}"`, { cwd: LUA_DIR, stdio: 'inherit' });
        } catch (e) {
            console.error('Failed to extract Lua tarball:', e.message);
            process.exit(1);
        }
    }

    const srcDir = path.join(LUA_DIR, `lua-${LUA_VERSION}`, 'src');

    // Compile Lua
    console.log('Compiling Lua...');
    try {
        // Try Linux/macOS make first
        try {
            execSync(`make linux`, { cwd: path.join(LUA_DIR, `lua-${LUA_VERSION}`), stdio: 'inherit' });
        } catch {
            try {
                execSync(`make macosx`, { cwd: path.join(LUA_DIR, `lua-${LUA_VERSION}`), stdio: 'inherit' });
            } catch {
                // Fallback: compile manually
                const compileCmd = `gcc -O2 -Wall -DLUA_USE_LINUX -o "${LUA_BIN}" *.c -lm -ldl`;
                execSync(compileCmd, { cwd: srcDir, stdio: 'inherit' });
            }
        }
    } catch (e) {
        console.error('Failed to compile Lua:', e.message);
        process.exit(1);
    }

    // Copy binary if it was built in src/
    const builtLua = path.join(srcDir, 'lua');
    if (fs.existsSync(builtLua) && !fs.existsSync(LUA_BIN)) {
        fs.copyFileSync(builtLua, LUA_BIN);
    }

    // Cleanup
    try { fs.unlinkSync(tarFile); } catch {}
    try {
        const rimraf = require('child_process');
        rimraf.execSync(`rm -rf lua-${LUA_VERSION}`, { cwd: LUA_DIR });
    } catch {}

    // Verify
    if (fs.existsSync(LUA_BIN)) {
        try {
            const version = execSync(`"${LUA_BIN}" -v`).toString().trim();
            console.log('Lua compiled successfully!', version);
        } catch {
            console.log('Lua binary at:', LUA_BIN);
        }
    } else {
        console.error('Lua binary not found at', LUA_BIN);
        process.exit(1);
    }
}

main().catch(err => {
    console.error('Setup failed:', err.message);
    process.exit(1);
});
