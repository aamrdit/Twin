import { BedrockRuntimeClient, ConverseStreamCommand } from "@aws-sdk/client-bedrock-runtime";

const region = process.env.AWS_REGION || "eu-central-1";
const modelId = process.env.BEDROCK_MODEL_ID || "amazon.nova-lite-v1:0";

const client = new BedrockRuntimeClient({ region });

export const handler = async (event, responseStream) => {
  const headers = {
    "content-type": "text/event-stream; charset=utf-8",
    "cache-control": "no-cache",
    "connection": "keep-alive",
    "access-control-allow-origin": "*"
  };

  // API Gateway streaming protocol
  responseStream.write(JSON.stringify({ statusCode: 200, headers }));
  responseStream.write("\x00".repeat(8));

  let body = {};
  try {
    body = event.body ? JSON.parse(event.body) : {};
  } catch {}

  const message = body.message || "hello";

  const cmd = new ConverseStreamCommand({
    modelId,
    messages: [
      { role: "user", content: [{ text: message }] }
    ],
    inferenceConfig: { maxTokens: 1000 }
  });

  const resp = await client.send(cmd);

  for await (const ev of resp.stream) {
    if (ev?.contentBlockDelta?.delta?.text) {
      responseStream.write(`data: ${ev.contentBlockDelta.delta.text}\n\n`);
    }
  }

  responseStream.write("data: [DONE]\n\n");
  responseStream.end();
};
