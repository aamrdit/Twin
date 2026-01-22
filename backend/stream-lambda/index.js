// backend/stream-lambda/index.js
// Lambda Response Streaming + API Gateway REST API (response_transfer_mode=STREAM)
// Streams Bedrock ConverseStream output as Server-Sent Events (SSE).

import { BedrockRuntimeClient, ConverseStreamCommand } from "@aws-sdk/client-bedrock-runtime";

// Prefer your own non-reserved env var; fall back to Lambda-provided region env vars.
const region =
  process.env.BEDROCK_REGION ||
  process.env.AWS_REGION ||
  process.env.AWS_DEFAULT_REGION ||
  "eu-central-1";

const modelId = process.env.BEDROCK_MODEL_ID || "amazon.nova-lite-v1:0";

const client = new BedrockRuntimeClient({ region });

// IMPORTANT: streamifyResponse is required for Node.js Lambda response streaming.
export const handler = awslambda.streamifyResponse(async (event, responseStream, _context) => {
  // Helper to safely end the stream
  const safeEnd = () => {
    try {
      responseStream.end();
    } catch {
      // ignore
    }
  };

  try {
    // REST API -> Lambda streaming expects:
    // 1) JSON metadata (statusCode + headers)
    // 2) 8 null bytes delimiter
    // 3) streamed payload bytes
    const headers = {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-transform",
      "connection": "keep-alive",
      "access-control-allow-origin": "*",
    };

    responseStream.write(JSON.stringify({ statusCode: 200, headers }));
    responseStream.write("\x00".repeat(8)); // delimiter

    // Parse JSON body (handles base64 if API Gateway sets isBase64Encoded)
    let body = {};
    try {
      const raw = event?.body
        ? (event.isBase64Encoded
            ? Buffer.from(event.body, "base64").toString("utf8")
            : event.body)
        : "{}";
      body = JSON.parse(raw);
    } catch {
      body = {};
    }

    const message = typeof body.message === "string" && body.message.trim() ? body.message : "hello streaming";

    // Build a minimal ConverseStream request
    const cmd = new ConverseStreamCommand({
      modelId,
      messages: [{ role: "user", content: [{ text: message }] }],
      inferenceConfig: { maxTokens: 1200, temperature: 0.7, topP: 0.9 },
    });

    const resp = await client.send(cmd);

    // Stream tokens as SSE
    for await (const ev of resp.stream) {
      const token = ev?.contentBlockDelta?.delta?.text;
      if (token) {
        responseStream.write(`data: ${token}\n\n`);
      }
    }

    responseStream.write("data: [DONE]\n\n");
    safeEnd();
  } catch (err) {
    console.error("Streaming Lambda error:", err);

    // Best-effort: if we already started streaming, emit an SSE error
    try {
      responseStream.write(`data: [ERROR] ${String(err?.message || err)}\n\n`);
    } catch {
      // ignore
    }
    safeEnd();
  }
});
