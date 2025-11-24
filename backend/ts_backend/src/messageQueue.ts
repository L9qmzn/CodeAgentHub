import type { SDKUserMessage } from "@anthropic-ai/claude-agent-sdk";

/**
 * Creates an async generator for streaming user messages to Claude SDK.
 * This allows dynamic message injection during the conversation.
 *
 * Usage:
 *   const controller = createMessageStream();
 *   query({ prompt: controller.stream(), options });
 *
 *   // Later, inject a new message:
 *   controller.push(userMessage);
 *
 *   // When done:
 *   controller.end();
 */
export class MessageStreamController {
  private pendingMessages: SDKUserMessage[] = [];
  private waitingResolver: ((value: IteratorResult<SDKUserMessage>) => void) | null = null;
  private ended = false;
  private error: Error | null = null;

  /**
   * Push a new message into the stream.
   * If the generator is waiting, it will immediately yield this message.
   */
  push(message: SDKUserMessage): void {
    if (this.ended) {
      throw new Error("Cannot push to an ended MessageStreamController");
    }

    if (this.waitingResolver) {
      // Generator is waiting, resolve immediately
      const resolve = this.waitingResolver;
      this.waitingResolver = null;
      resolve({ value: message, done: false });
    } else {
      // Queue the message
      this.pendingMessages.push(message);
    }
  }

  /**
   * End the stream. The generator will finish after yielding all pending messages.
   */
  end(): void {
    this.ended = true;
    if (this.waitingResolver) {
      this.waitingResolver({ value: undefined as any, done: true });
      this.waitingResolver = null;
    }
  }

  /**
   * End the stream with an error.
   */
  endWithError(error: Error): void {
    this.error = error;
    this.end();
  }

  /**
   * Check if the stream has ended
   */
  isEnded(): boolean {
    return this.ended;
  }

  /**
   * Get the number of pending messages
   */
  get pendingCount(): number {
    return this.pendingMessages.length;
  }

  /**
   * Create the async iterable stream.
   * This should be called once and passed to query({ prompt: stream() }).
   */
  async *stream(): AsyncGenerator<SDKUserMessage, void, undefined> {
    while (true) {
      // Throw if there was an error
      if (this.error) {
        throw this.error;
      }

      // Yield any pending messages first
      if (this.pendingMessages.length > 0) {
        yield this.pendingMessages.shift()!;
        continue;
      }

      // If ended and no more messages, finish
      if (this.ended) {
        return;
      }

      // Wait for next message
      const result = await new Promise<IteratorResult<SDKUserMessage>>((resolve) => {
        this.waitingResolver = resolve;
      });

      if (result.done) {
        return;
      }

      yield result.value;
    }
  }
}

/**
 * Legacy MessageQueue class for backward compatibility.
 * Prefer using MessageStreamController for new code.
 */
export class MessageQueue implements AsyncIterable<SDKUserMessage> {
  private queue: SDKUserMessage[] = [];
  private resolvers: Array<(value: IteratorResult<SDKUserMessage>) => void> = [];
  private closed = false;
  private error: Error | null = null;

  push(message: SDKUserMessage): void {
    if (this.closed) {
      throw new Error("Cannot push to a closed MessageQueue");
    }

    if (this.resolvers.length > 0) {
      const resolve = this.resolvers.shift()!;
      resolve({ value: message, done: false });
    } else {
      this.queue.push(message);
    }
  }

  close(): void {
    this.closed = true;
    while (this.resolvers.length > 0) {
      const resolve = this.resolvers.shift()!;
      resolve({ value: undefined as any, done: true });
    }
  }

  closeWithError(error: Error): void {
    this.error = error;
    this.closed = true;
    while (this.resolvers.length > 0) {
      const resolve = this.resolvers.shift()!;
      resolve({ value: undefined as any, done: true });
    }
  }

  isClosed(): boolean {
    return this.closed;
  }

  get length(): number {
    return this.queue.length;
  }

  async *[Symbol.asyncIterator](): AsyncIterator<SDKUserMessage> {
    while (true) {
      if (this.error) {
        throw this.error;
      }

      if (this.queue.length > 0) {
        yield this.queue.shift()!;
        continue;
      }

      if (this.closed) {
        return;
      }

      const result = await new Promise<IteratorResult<SDKUserMessage>>((resolve) => {
        this.resolvers.push(resolve);
      });

      if (result.done) {
        return;
      }

      yield result.value;
    }
  }
}
