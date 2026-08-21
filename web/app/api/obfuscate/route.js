import { NextResponse } from 'next/server';
import { execFile } from 'child_process';
import { writeFileSync, unlinkSync, readFileSync, existsSync, readdirSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { promisify } from 'util';

const execFileAsync = promisify(execFile);

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const LUA_DIR = join(process.cwd(), 'lua-staging');
const LUA_CLI = join(LUA_DIR, 'cli.lua');
const BUNDLED_LUA = join(process.cwd(), 'lua', 'bin', 'lua');

async function getLuaPath() {
    if (existsSync(BUNDLED_LUA)) return BUNDLED_LUA;
    try {
        await execFileAsync('lua', ['-v']);
        return 'lua';
    } catch {
        const paths = ['/usr/bin/lua', '/usr/local/bin/lua', '/opt/homebrew/bin/lua'];
        for (const p of paths) {
            if (existsSync(p)) return p;
        }
        return null;
    }
}

function findLatestHephFile() {
    const tmp = tmpdir();
    const files = readdirSync(tmp)
        .filter(f => f.startsWith('heph_') && f.endsWith('.obfuscated.lua'))
        .map(f => ({ name: f, path: join(tmp, f), time: require('fs').statSync(join(tmp, f)).mtimeMs }))
        .sort((a, b) => b.time - a.time);
    return files.length > 0 ? files[0].path : null;
}

export async function POST(request) {
    let tmpFile = null;
    try {
        const formData = await request.formData();
        const file = formData.get('file');

        if (!file) {
            return NextResponse.json({ error: 'No file provided' }, { status: 400 });
        }

        const code = await file.text();
        if (!code.trim()) {
            return NextResponse.json({ error: 'Empty file' }, { status: 400 });
        }

        const luaPath = await getLuaPath();
        if (!luaPath) {
            return NextResponse.json({ error: 'Lua is not installed' }, { status: 500 });
        }

        const timestamp = Date.now();
        const rand = Math.random().toString(36).slice(2, 10);
        tmpFile = join(tmpdir(), `heph_${timestamp}_${rand}.lua`);
        const expectedOut = tmpFile + '.obfuscated.lua';

        writeFileSync(tmpFile, code, 'utf-8');

        const { stdout, stderr } = await execFileAsync(luaPath, [LUA_CLI, tmpFile], {
            timeout: 30000,
            cwd: LUA_DIR,
            maxBuffer: 10 * 1024 * 1024,
        });

        let outFile = null;

        // Method 1: Check expected path
        if (existsSync(expectedOut)) {
            outFile = expectedOut;
        }

        // Method 2: Parse [OUT] from stdout
        if (!outFile) {
            const match = stdout.match(/\[OUT\]\s+(.+)/);
            if (match) {
                const path = match[1].trim();
                if (existsSync(path)) {
                    outFile = path;
                }
            }
        }

        // Method 3: Find latest heph_*.obfuscated.lua
        if (!outFile) {
            outFile = findLatestHephFile();
        }

        if (outFile && existsSync(outFile)) {
            const obfuscated = readFileSync(outFile, 'utf-8');

            // Cleanup temp files
            try { unlinkSync(tmpFile); } catch {}
            try { unlinkSync(outFile); } catch {}

            return NextResponse.json({
                success: true,
                output: obfuscated,
                stats: {
                    inputSize: Buffer.byteLength(code, 'utf-8'),
                    outputSize: Buffer.byteLength(obfuscated, 'utf-8'),
                },
            });
        }

        return NextResponse.json(
            { error: 'Obfuscation produced no output', details: stdout + '\n' + stderr },
            { status: 500 }
        );

    } catch (err) {
        if (tmpFile) {
            try { unlinkSync(tmpFile); } catch {}
            try { unlinkSync(tmpFile + '.obfuscated.lua'); } catch {}
        }
        return NextResponse.json(
            { error: 'Obfuscation failed', details: err.message },
            { status: 500 }
        );
    }
}
