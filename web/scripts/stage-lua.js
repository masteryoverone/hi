const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.join(__dirname, '..', '..');
const STAGING = path.join(__dirname, '..', 'lua-staging');

const ENTRIES = [
    ['cli.lua', path.join(REPO_ROOT, 'cli.lua')],
    ['src', path.join(REPO_ROOT, 'src')],
    ['modules', path.join(REPO_ROOT, 'modules')],
];

function copyDir(src, dest) {
    if (!fs.existsSync(src)) return;
    fs.mkdirSync(dest, { recursive: true });
    for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
        const s = path.join(src, entry.name);
        const d = path.join(dest, entry.name);
        if (entry.isDirectory()) {
            copyDir(s, d);
        } else if (entry.isFile() && entry.name.endsWith('.lua')) {
            fs.copyFileSync(s, d);
        }
    }
}

function main() {
    fs.rmSync(STAGING, { recursive: true, force: true });
    fs.mkdirSync(STAGING, { recursive: true });

    for (const [rel, src] of ENTRIES) {
        const dest = path.join(STAGING, rel);
        if (fs.existsSync(src)) {
            if (fs.statSync(src).isDirectory()) {
                copyDir(src, dest);
            } else {
                fs.mkdirSync(path.dirname(dest), { recursive: true });
                fs.copyFileSync(src, dest);
            }
        }
    }

    const cli = path.join(STAGING, 'cli.lua');
    if (!fs.existsSync(cli)) {
        console.error('Staging failed: cli.lua not found at', cli);
        process.exit(1);
    }

    let count = 0;
    const walk = (dir) => {
        if (!fs.existsSync(dir)) return;
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const p = path.join(dir, entry.name);
            if (entry.isDirectory()) walk(p);
            else if (entry.name.endsWith('.lua')) count++;
        }
    };
    walk(STAGING);
    console.log(`Staged ${count} .lua files into lua-staging/`);
}

main();
