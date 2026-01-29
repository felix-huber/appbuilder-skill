# Worker-Client Communication Patterns

Lessons learned from building apps with Web Workers, Service Workers, and similar async message-passing architectures.

## The Problem

When building apps with workers (Web Workers, Service Workers, etc.), a common failure mode is:

1. Worker sends status updates, broadcasts, and responses
2. Client only expects request-response pattern
3. Status updates get interpreted as responses
4. App state becomes inconsistent
5. E2E tests pass (they mock the worker) but real app fails

## Pattern: Correlation IDs for Request-Response

### The Issue

```typescript
// BROKEN: No correlation between request and response
worker.postMessage({ type: 'query', sql: 'SELECT * FROM users' });
worker.onmessage = (e) => {
  // Is this the response to MY query? Or a status update? Or another response?
  handleResponse(e.data);
};
```

### The Solution

```typescript
// CORRECT: Correlation ID links request to response
interface WorkerRequest {
  correlationId: string;
  type: 'query' | 'create' | 'delete';
  payload: unknown;
}

interface WorkerResponse {
  correlationId: string;  // Matches request
  type: 'result' | 'error';
  payload: unknown;
}

interface WorkerBroadcast {
  type: 'status' | 'progress' | 'notification';
  // No correlationId - not a response to any specific request
  payload: unknown;
}

// Client implementation
class WorkerClient {
  private worker: Worker;
  private pending = new Map<string, { resolve: Function; reject: Function }>();

  constructor(worker: Worker) {
    this.worker = worker;
    this.worker.onmessage = (e) => this.handleMessage(e);
  }

  query(sql: string): Promise<QueryResult> {
    const correlationId = crypto.randomUUID();

    return new Promise((resolve, reject) => {
      this.pending.set(correlationId, { resolve, reject });
      this.worker.postMessage({
        correlationId,
        type: 'query',
        payload: { sql }
      });
    });
  }

  private handleMessage(event: MessageEvent) {
    const message = event.data;

    // Is this a response to a pending request?
    if (message.correlationId && this.pending.has(message.correlationId)) {
      const { resolve, reject } = this.pending.get(message.correlationId)!;
      this.pending.delete(message.correlationId);

      if (message.type === 'error') {
        reject(new Error(message.payload.message));
      } else {
        resolve(message.payload);
      }
      return;
    }

    // Otherwise it's a broadcast
    this.handleBroadcast(message);
  }

  private handleBroadcast(message: WorkerBroadcast) {
    // Handle status updates, progress, etc.
    console.log('Broadcast received:', message);
  }
}
```

## Pattern: Explicit Message Types

### The Issue

```typescript
// BROKEN: Ambiguous message types
worker.postMessage({ action: 'update', data: {...} });
// Is 'update' a command or a notification? Is 'data' the payload or metadata?
```

### The Solution

```typescript
// CORRECT: Explicit message discrimination
type WorkerMessage =
  | { kind: 'request'; correlationId: string; command: Command }
  | { kind: 'response'; correlationId: string; result: Result }
  | { kind: 'broadcast'; channel: string; payload: unknown }
  | { kind: 'error'; correlationId?: string; error: ErrorInfo };

function handleMessage(msg: WorkerMessage) {
  switch (msg.kind) {
    case 'request':
      // Handle as command
      break;
    case 'response':
      // Match to pending request
      break;
    case 'broadcast':
      // Update UI state
      break;
    case 'error':
      // Error might be response or broadcast
      if (msg.correlationId) {
        // Response to specific request
      } else {
        // General error notification
      }
      break;
  }
}
```

## Pattern: Progress and Status Messages

### The Issue

Progress updates get mixed with responses, causing state corruption.

```typescript
// Worker sends:
postMessage({ type: 'progress', percent: 50 });  // Broadcast
postMessage({ type: 'result', data: [...] });    // Response

// Client receives both but can't distinguish:
worker.onmessage = (e) => {
  setResult(e.data);  // Oops, set progress as result
};
```

### The Solution

```typescript
// Use separate channels or clear discrimination
interface ProgressBroadcast {
  kind: 'broadcast';
  channel: 'progress';
  payload: {
    taskId: string;
    percent: number;
    message?: string;
  };
}

interface QueryResponse {
  kind: 'response';
  correlationId: string;
  result: QueryResult;
}

// Client handles separately
class WorkerClient {
  onProgress?: (progress: ProgressInfo) => void;

  private handleMessage(event: MessageEvent) {
    const msg = event.data;

    if (msg.kind === 'broadcast' && msg.channel === 'progress') {
      this.onProgress?.(msg.payload);
      return;
    }

    if (msg.kind === 'response') {
      this.resolvePending(msg.correlationId, msg.result);
      return;
    }
  }
}
```

## Pattern: Worker Initialization Handshake

### The Issue

Client sends requests before worker is ready.

```typescript
// BROKEN: Race condition
const worker = new Worker('worker.js');
worker.postMessage({ type: 'query', sql: '...' });  // Worker might not be ready!
```

### The Solution

```typescript
// CORRECT: Wait for ready signal
class WorkerClient {
  private worker: Worker;
  private ready: Promise<void>;
  private readyResolve!: () => void;

  constructor() {
    this.ready = new Promise((resolve) => {
      this.readyResolve = resolve;
    });

    this.worker = new Worker('worker.js');
    this.worker.onmessage = (e) => this.handleMessage(e);
  }

  private handleMessage(event: MessageEvent) {
    const msg = event.data;

    if (msg.kind === 'broadcast' && msg.channel === 'ready') {
      this.readyResolve();
      return;
    }

    // ... handle other messages
  }

  async query(sql: string): Promise<QueryResult> {
    await this.ready;  // Wait for worker to be ready
    // ... send query
  }
}

// Worker side
self.postMessage({ kind: 'broadcast', channel: 'ready', payload: null });
```

## Testing Worker-Client Communication

### TDD Approach (Write Tests First!)

For worker-client code, follow TDD strictly:

1. **Write the test first** - Define expected behavior before implementing
2. **Verify failure** - The test should fail because the code doesn't exist yet
3. **Implement minimum** - Write just enough code to pass
4. **Refactor** - Clean up while keeping tests green

**Why TDD is critical for async code:**
- Race conditions and timing bugs are hard to catch after the fact
- Tests define the contract (correlation IDs, message types) upfront
- Mocking decisions are explicit, not afterthoughts

### Unit Tests: Mock the Worker

```typescript
describe('WorkerClient', () => {
  let client: WorkerClient;
  let mockWorker: MockWorker;

  beforeEach(() => {
    mockWorker = new MockWorker();
    client = new WorkerClient(mockWorker);
  });

  it('correlates responses to requests', async () => {
    const queryPromise = client.query('SELECT 1');

    // Verify request was sent with correlationId
    const request = mockWorker.lastMessage;
    expect(request.correlationId).toBeDefined();

    // Simulate response
    mockWorker.simulateMessage({
      kind: 'response',
      correlationId: request.correlationId,
      result: { rows: [{ value: 1 }] }
    });

    const result = await queryPromise;
    expect(result.rows[0].value).toBe(1);
  });

  it('handles broadcasts separately from responses', async () => {
    const progressUpdates: ProgressInfo[] = [];
    client.onProgress = (p) => progressUpdates.push(p);

    const queryPromise = client.query('SELECT 1');
    const request = mockWorker.lastMessage;

    // Simulate progress broadcast (no correlationId)
    mockWorker.simulateMessage({
      kind: 'broadcast',
      channel: 'progress',
      payload: { taskId: 'x', percent: 50 }
    });

    // Simulate actual response
    mockWorker.simulateMessage({
      kind: 'response',
      correlationId: request.correlationId,
      result: { rows: [] }
    });

    await queryPromise;

    // Progress was handled separately
    expect(progressUpdates).toHaveLength(1);
    expect(progressUpdates[0].percent).toBe(50);
  });

  it('times out if no response received', async () => {
    client.setTimeout(100);

    await expect(client.query('SELECT 1'))
      .rejects
      .toThrow(/timeout/i);
  });
});
```

### Integration Tests: Real Worker

```typescript
describe('Worker Integration', () => {
  let worker: Worker;
  let client: WorkerClient;

  beforeEach(async () => {
    worker = new Worker(new URL('./worker.ts', import.meta.url));
    client = new WorkerClient(worker);
    await client.waitForReady();
  });

  afterEach(() => {
    worker.terminate();
  });

  it('executes queries end-to-end', async () => {
    await client.execute('CREATE TABLE test (id INTEGER)');
    await client.execute('INSERT INTO test VALUES (1)');

    const result = await client.query('SELECT * FROM test');
    expect(result.rows).toEqual([{ id: 1 }]);
  });
});
```

### E2E Tests: Full App

```typescript
describe('Database UI', () => {
  it('shows query results after execution', async ({ page }) => {
    await page.goto('/');

    // Wait for worker to initialize
    await expect(page.getByTestId('status')).toHaveText('Ready');

    // Execute query
    await page.getByTestId('sql-input').fill('SELECT 1 as value');
    await page.getByTestId('run-button').click();

    // Wait for results (not just any response)
    await expect(page.getByTestId('result-table')).toBeVisible();
    await expect(page.getByText('value')).toBeVisible();
    await expect(page.getByText('1')).toBeVisible();
  });

  it('shows progress during long operations', async ({ page }) => {
    await page.goto('/');
    await expect(page.getByTestId('status')).toHaveText('Ready');

    // Start import
    await page.getByTestId('import-button').click();
    await page.setInputFiles('[data-testid="file-input"]', 'large-db.sqlite');

    // Progress should appear
    await expect(page.getByTestId('progress-bar')).toBeVisible();

    // Wait for completion
    await expect(page.getByTestId('progress-bar')).toBeHidden({ timeout: 30000 });
    await expect(page.getByTestId('status')).toHaveText('Ready');
  });
});
```

## Checklist for Worker-Based Apps

### Architecture

- [ ] All request-response messages use correlation IDs
- [ ] Broadcasts are clearly distinguished from responses
- [ ] Worker initialization includes ready handshake
- [ ] Timeout handling for unresponsive workers
- [ ] Error messages include correlation ID when applicable

### Testing

- [ ] Unit tests mock the worker to test client logic
- [ ] Integration tests use real worker in isolation
- [ ] E2E tests verify full app behavior with real worker
- [ ] Tests cover: normal flow, errors, timeouts, progress updates
- [ ] Tests verify broadcasts don't interfere with responses

### Common Failure Modes

- [ ] Check: Client doesn't await worker ready before sending
- [ ] Check: Progress updates aren't misinterpreted as responses
- [ ] Check: Multiple concurrent requests are correctly correlated
- [ ] Check: Worker errors propagate to correct pending request
- [ ] Check: Client handles worker termination/restart

## TypeScript Interface Template

```typescript
// messages.ts - Shared between worker and client

// Request-Response with correlation
export interface WorkerRequest<T = unknown> {
  kind: 'request';
  correlationId: string;
  command: string;
  payload: T;
}

export interface WorkerResponse<T = unknown> {
  kind: 'response';
  correlationId: string;
  success: true;
  result: T;
}

export interface WorkerError {
  kind: 'error';
  correlationId?: string;  // Present if response to request, absent if broadcast
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

// Broadcasts (no correlation, push from worker)
export interface WorkerBroadcast<T = unknown> {
  kind: 'broadcast';
  channel: 'ready' | 'progress' | 'notification' | 'state-change';
  payload: T;
}

export type WorkerMessage =
  | WorkerRequest
  | WorkerResponse
  | WorkerError
  | WorkerBroadcast;

// Type guards
export function isResponse(msg: WorkerMessage): msg is WorkerResponse {
  return msg.kind === 'response';
}

export function isBroadcast(msg: WorkerMessage): msg is WorkerBroadcast {
  return msg.kind === 'broadcast';
}

export function isError(msg: WorkerMessage): msg is WorkerError {
  return msg.kind === 'error';
}
```
