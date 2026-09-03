// Runs `ccusage statusline` and drops the cost segments (subscription plan, so
// the $ amounts and burn rate are noise). Keeps model name + context usage.
const { execSync } = require('child_process');
const fs = require('fs');

let out;
try {
  out = execSync('npx -y ccusage statusline', {
    input: fs.readFileSync(0, 'utf8'),
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'ignore'],
  });
} catch {
  process.exit(0);
}

const plain = s => s.replace(/\x1b\[[0-9;]*m/g, '');
process.stdout.write(
  out
    .trimEnd()
    .split(' | ')
    .filter(part => !/^(\u{1F4B0}|\u{1F525})/u.test(plain(part).trim()))
    .join(' | ')
);
