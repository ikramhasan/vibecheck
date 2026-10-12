import { CodeView, processFile, type CodeViewDiffItem, type FileDiffMetadata } from '@pierre/diffs';
import { getOrCreateWorkerPoolSingleton } from '@pierre/diffs/worker';
import { FileTree, type GitStatus, type GitStatusEntry } from '@pierre/trees';

type DiffStyle = 'unified' | 'split';

interface FilePatch {
  patch: string;
  untracked: boolean;
}

interface Payload {
  files: FilePatch[];
}

interface Entry {
  key: string;
  item: CodeViewDiffItem;
  status: GitStatus;
  added: number;
  removed: number;
}

declare global {
  interface Window {
    vibecheck: { show(payload: Payload): void; reset(): void };
    webkit?: { messageHandlers: { vibecheck: { postMessage(message: unknown): void } } };
  }
}

const styleKey = 'diffStyle';
let diffStyle: DiffStyle = localStorage.getItem(styleKey) === 'split' ? 'split' : 'unified';
let entries = new Map<string, Entry>();
let tree: FileTree | undefined;

const workers = getOrCreateWorkerPoolSingleton({
  poolOptions: {
    workerFactory: () => new Worker(new URL('./worker.js', import.meta.url), { type: 'module' }),
    poolSize: Math.min(4, Math.max(2, navigator.hardwareConcurrency - 2)),
  },
  highlighterOptions: { theme: { light: 'pierre-light', dark: 'pierre-dark' } },
});

const options = {
  theme: { light: 'pierre-light', dark: 'pierre-dark' },
  themeType: 'system',
  stickyHeaders: true,
  overflow: 'scroll',
  hunkSeparators: 'line-info',
  layout: { paddingTop: 12, paddingBottom: 24, gap: 12 },
  unsafeCSS: ':host { --diffs-font-family: "SF Mono", ui-monospace, Menlo, monospace; --diffs-font-size: 12px; }',
} as const;

const codeView = new CodeView({ ...options, diffStyle }, workers);
let attached = false;

function hash(text: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 0x01000193);
  return (h >>> 0).toString(36) + text.length.toString(36);
}

function status(diff: FileDiffMetadata, untracked: boolean): GitStatus {
  if (untracked) return 'untracked';
  switch (diff.type) {
    case 'new': return 'added';
    case 'deleted': return 'deleted';
    case 'rename-pure':
    case 'rename-changed': return 'renamed';
    default: return 'modified';
  }
}

const parsed = new Map<string, Entry>();

function entry(file: FilePatch): Entry | undefined {
  const key = hash(file.patch) + (file.untracked ? 'u' : '');
  const cached = parsed.get(key);
  if (cached != null) return cached;
  const fileDiff = processFile(file.patch, { cacheKey: key, isGitDiff: true });
  if (fileDiff == null) return undefined;
  const previous = entries.get(fileDiff.name);
  const result: Entry = {
    key,
    item: { id: fileDiff.name, type: 'diff', fileDiff, version: (previous?.item.version ?? -1) + 1 },
    status: status(fileDiff, file.untracked),
    added: fileDiff.hunks.reduce((sum, h) => sum + h.additionLines, 0),
    removed: fileDiff.hunks.reduce((sum, h) => sum + h.deletionLines, 0),
  };
  parsed.set(key, result);
  return result;
}

function renderSummary() {
  const list = [...entries.values()];
  const added = list.reduce((sum, e) => sum + e.added, 0);
  const removed = list.reduce((sum, e) => sum + e.removed, 0);
  const files = list.length === 1 ? '1 file' : `${list.length} files`;
  const summary = document.getElementById('summary')!;
  summary.replaceChildren(
    `${files} changed since the session started  `,
    Object.assign(document.createElement('span'), { className: 'added', textContent: `+${added.toLocaleString()}` }),
    ' ',
    Object.assign(document.createElement('span'), { className: 'removed', textContent: `−${removed.toLocaleString()}` }),
  );
}

function renderTree(paths: string[], statuses: GitStatusEntry[]) {
  if (tree == null) {
    tree = new FileTree({
      paths,
      gitStatus: statuses,
      initialExpansion: 'open',
      flattenEmptyDirectories: true,
      search: true,
      density: 'compact',
      icons: 'standard',
      onSelectionChange(selected) {
        const path = selected[0];
        if (path != null && entries.has(path)) codeView.scrollTo({ type: 'item', id: path, align: 'start' });
      },
      renderRowDecoration({ item }) {
        const e = entries.get(item.path);
        if (e == null || item.kind !== 'file') return null;
        if (e.added + e.removed === 0) return null;
        return { text: `+${e.added} −${e.removed}`, title: `${e.added} added, ${e.removed} removed` };
      },
    });
    tree.render({ containerWrapper: document.getElementById('tree')! });
  } else {
    tree.resetPaths(paths);
    tree.setGitStatus(statuses);
  }
}

function show(payload: Payload) {
  const next = new Map<string, Entry>();
  for (const file of payload.files) {
    const e = entry(file);
    if (e != null) next.set(e.item.id, e);
  }
  const changed = next.size !== entries.size || [...next].some(([id, e]) => entries.get(id) !== e);
  entries = next;
  document.body.classList.remove('loading');
  for (const [key, e] of parsed) if (entries.get(e.item.id) !== e) parsed.delete(key);
  document.body.classList.toggle('empty', entries.size === 0);
  if (!changed) return;
  if (!attached) {
    codeView.setup(document.getElementById('diffs')!);
    attached = true;
  }
  const items = [...entries.values()].map((e) => e.item);
  codeView.setItems(items);
  renderTree(items.map((i) => i.id), [...entries.values()].map((e) => ({ path: e.item.id, status: e.status })));
  renderSummary();
}

function applyStyle() {
  for (const button of document.querySelectorAll<HTMLButtonElement>('[data-style]')) {
    button.setAttribute('aria-pressed', String(button.dataset.style === diffStyle));
  }
}

for (const button of document.querySelectorAll<HTMLButtonElement>('[data-style]')) {
  button.addEventListener('click', () => {
    diffStyle = button.dataset.style === 'split' ? 'split' : 'unified';
    localStorage.setItem(styleKey, diffStyle);
    applyStyle();
    codeView.setOptions({ ...options, diffStyle });
  });
}
applyStyle();

function reset() {
  entries = new Map();
  parsed.clear();
  if (attached) codeView.setItems([]);
  tree?.resetPaths([]);
  document.body.classList.add('loading');
}

window.vibecheck = { show, reset };
window.webkit?.messageHandlers.vibecheck.postMessage({ type: 'ready' });
