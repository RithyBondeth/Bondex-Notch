import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const root = process.cwd();
const output = resolve(root, 'dist');

await rm(output, { recursive: true, force: true });
await mkdir(resolve(output, 'server'), { recursive: true });
await cp(resolve(root, 'out'), resolve(output, 'client'), { recursive: true });

await writeFile(
  resolve(output, 'server', 'index.js'),
  `export default {
  fetch(request, env) {
    return env.ASSETS.fetch(request);
  },
};
`,
);
