// Label Printer bridge (Cloudflare Worker).
//
// Two jobs:
//  1. A tiny MCP server (a "custom connector" for Claude) with one tool,
//     print_label, at  /mcp/<PRINTER_KEY>
//  2. A print-job queue that the Label Printer phone app checks every few
//     seconds, at  /jobs/<PRINTER_KEY>
//
// PRINTER_KEY is a password stored as a Cloudflare secret (never in this
// file), so only someone who knows it can send or collect print jobs.

const SERVER_NAME = 'label-printer-bridge';
const SERVER_VERSION = '0.1.0';
const MAX_TEXT_LENGTH = 60;
const JOB_EXPIRY_MS = 10 * 60 * 1000; // unclaimed jobs expire after 10 min
const RESULT_WAIT_MS = 25 * 1000; // how long the tool waits for the phone

const PRINT_LABEL_TOOL = {
  name: 'print_label',
  title: 'Print a label',
  description:
    "Print a label on the user's NIIMBOT D110_M label printer " +
    '(40 x 12 mm labels). Keep the text short: about 12 characters fit ' +
    'on one line at full size; longer text is shrunk to fit. Use "\\n" ' +
    'for a second line. If the user asks for the date on the label, set ' +
    "add_date to true and the phone adds today's date. The user's phone " +
    'must have the Label Printer app open with "Listen for print jobs" ' +
    'turned on.',
  inputSchema: {
    type: 'object',
    properties: {
      text: {
        type: 'string',
        description: 'The text to print.',
        maxLength: MAX_TEXT_LENGTH,
      },
      add_date: {
        type: 'boolean',
        description: "Add today's date under the text.",
        default: false,
      },
      copies: {
        type: 'integer',
        description: 'How many labels to print (1-10).',
        minimum: 1,
        maximum: 10,
        default: 1,
      },
    },
    required: ['text'],
  },
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const parts = url.pathname.split('/').filter(Boolean);

    if (parts.length === 0) {
      return text('Label printer bridge is running.');
    }

    const [area, key, ...rest] = parts;
    if (area !== 'mcp' && area !== 'jobs') {
      return text('Not found', 404);
    }
    if (!env.PRINTER_KEY) {
      return text('PRINTER_KEY is not set up yet.', 503);
    }
    if (!key || !safeEqual(key, env.PRINTER_KEY)) {
      return text('Wrong or missing printer key.', 403);
    }

    const queue = env.QUEUE.get(env.QUEUE.idFromName('main'));

    if (area === 'mcp') {
      return handleMcp(request, queue);
    }
    return handleJobs(request, queue, rest);
  },
};

// ---------------------------------------------------------------------------
// Phone app endpoints
//   POST /jobs/<key>/claim            -> { jobs: [...] }  (marks them taken)
//   POST /jobs/<key>/result  {id, ok, message}
// ---------------------------------------------------------------------------
async function handleJobs(request, queue, rest) {
  if (request.method !== 'POST') return text('Use POST', 405);
  const action = rest[0];
  if (action === 'claim') {
    return queue.fetch('https://queue/claim', { method: 'POST' });
  }
  if (action === 'result') {
    const body = await request.text();
    return queue.fetch('https://queue/result', { method: 'POST', body });
  }
  return text('Not found', 404);
}

// ---------------------------------------------------------------------------
// MCP (Streamable HTTP transport, JSON responses only)
// ---------------------------------------------------------------------------
async function handleMcp(request, queue) {
  if (request.method !== 'POST') {
    return new Response(null, { status: 405, headers: { Allow: 'POST' } });
  }

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json(rpcError(null, -32700, 'Parse error'), 400);
  }

  const messages = Array.isArray(payload) ? payload : [payload];
  const responses = [];
  for (const msg of messages) {
    const res = await handleRpc(msg, queue);
    if (res) responses.push(res);
  }

  if (responses.length === 0) {
    return new Response(null, { status: 202 });
  }
  return json(Array.isArray(payload) ? responses : responses[0]);
}

async function handleRpc(msg, queue) {
  if (!msg || msg.jsonrpc !== '2.0' || typeof msg.method !== 'string') {
    return rpcError(msg?.id ?? null, -32600, 'Invalid request');
  }
  const isNotification = msg.id === undefined || msg.id === null;
  if (isNotification) return null;

  switch (msg.method) {
    case 'initialize':
      return rpcResult(msg.id, {
        protocolVersion: msg.params?.protocolVersion || '2025-06-18',
        capabilities: { tools: {} },
        serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
        instructions:
          "Use print_label to print labels on the user's label printer.",
      });
    case 'ping':
      return rpcResult(msg.id, {});
    case 'tools/list':
      return rpcResult(msg.id, { tools: [PRINT_LABEL_TOOL] });
    case 'tools/call':
      return rpcResult(msg.id, await callTool(msg.params, queue));
    default:
      return rpcError(msg.id, -32601, `Method not found: ${msg.method}`);
  }
}

async function callTool(params, queue) {
  if (params?.name !== 'print_label') {
    return toolText(`Unknown tool: ${params?.name}`, true);
  }
  const args = params.arguments || {};
  const labelText = String(args.text ?? '').trim();
  if (!labelText) return toolText('No label text was given.', true);
  if (labelText.length > MAX_TEXT_LENGTH) {
    return toolText(
      `Label text is too long (max ${MAX_TEXT_LENGTH} characters).`,
      true,
    );
  }
  const copies = Math.min(10, Math.max(1, parseInt(args.copies ?? 1, 10) || 1));
  const addDate = args.add_date === true;

  const addRes = await queue.fetch('https://queue/add', {
    method: 'POST',
    body: JSON.stringify({ text: labelText, copies, addDate }),
  });
  const { id } = await addRes.json();

  // Wait (briefly) for the phone to print it and report back.
  const deadline = Date.now() + RESULT_WAIT_MS;
  while (Date.now() < deadline) {
    await sleep(1000);
    const res = await queue.fetch(`https://queue/status?id=${id}`);
    const job = await res.json();
    if (job?.status === 'done') {
      return toolText(`Printed: "${labelText}"${job.message ? ` (${job.message})` : ''}.`);
    }
    if (job?.status === 'failed') {
      return toolText(
        `The phone tried to print but it failed: ${job.message || 'unknown error'}.`,
        true,
      );
    }
  }
  const res = await queue.fetch(`https://queue/status?id=${id}`);
  const job = await res.json();
  if (job?.status === 'printing') {
    return toolText(
      'The phone picked up the label and is still printing it.',
    );
  }
  return toolText(
    'The label is queued, but the phone has not picked it up yet. ' +
      'Make sure the Label Printer app is open with "Listen for print ' +
      'jobs" turned on. It will print when the app checks in (jobs expire ' +
      'after 10 minutes).',
  );
}

// ---------------------------------------------------------------------------
// Durable Object: the print-job queue
// ---------------------------------------------------------------------------
export class PrintQueue {
  constructor(ctx) {
    this.storage = ctx.storage;
  }

  async fetch(request) {
    const url = new URL(request.url);
    const now = Date.now();

    if (url.pathname === '/add') {
      const { text: t, copies, addDate } = await request.json();
      const id = crypto.randomUUID();
      await this.storage.put(`job:${id}`, {
        id,
        text: t,
        copies,
        addDate,
        created: now,
        status: 'pending',
      });
      return json({ id });
    }

    if (url.pathname === '/claim') {
      const all = await this.storage.list({ prefix: 'job:' });
      const claimed = [];
      for (const [k, job] of all) {
        if (now - job.created > 60 * 60 * 1000) {
          await this.storage.delete(k); // tidy up jobs older than 1 hour
          continue;
        }
        if (job.status === 'pending' && now - job.created <= JOB_EXPIRY_MS) {
          job.status = 'printing';
          await this.storage.put(k, job);
          claimed.push({
            id: job.id,
            text: job.text,
            copies: job.copies,
            addDate: job.addDate,
            created: job.created,
          });
        }
      }
      claimed.sort((a, b) => a.created - b.created);
      return json({ jobs: claimed });
    }

    if (url.pathname === '/result') {
      const { id, ok, message } = await request.json();
      const job = await this.storage.get(`job:${id}`);
      if (!job) return json({ ok: false }, 404);
      job.status = ok ? 'done' : 'failed';
      job.message = message ? String(message).slice(0, 200) : '';
      await this.storage.put(`job:${id}`, job);
      return json({ ok: true });
    }

    if (url.pathname === '/status') {
      const job = await this.storage.get(`job:${url.searchParams.get('id')}`);
      return json(job || null);
    }

    return text('Not found', 404);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function rpcResult(id, result) {
  return { jsonrpc: '2.0', id, result };
}

function rpcError(id, code, message) {
  return { jsonrpc: '2.0', id, error: { code, message } };
}

function toolText(message, isError = false) {
  return { content: [{ type: 'text', text: message }], isError };
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function text(body, status = 200) {
  return new Response(body, {
    status,
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Compare two strings without leaking how many characters matched.
function safeEqual(a, b) {
  const enc = new TextEncoder();
  const x = enc.encode(a);
  const y = enc.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  }
  return diff === 0;
}
