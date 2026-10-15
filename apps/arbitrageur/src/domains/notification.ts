/// Notification domain (ADR-0014): sends transaction and critical-fault messages to Slack via an
/// incoming webhook. Deliberately minimal -- a webhook POST needs no client library, and this is
/// the entire surface Execution/Operations calls.
export async function notifySlack(webhookUrl: string, text: string): Promise<void> {
  const res = await fetch(webhookUrl, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ text }),
  });
  if (!res.ok) {
    throw new Error(`Slack webhook returned ${res.status}: ${await res.text()}`);
  }
}

export function formatExecutionSubmitted(candidateId: string, txHash: string): string {
  return `:hourglass_flowing_sand: Submitted execution attempt for candidate \`${candidateId}\`: \`${txHash}\``;
}

export function formatExecutionFinal(candidateId: string, txHash: string, profitHeadroom: bigint, tokenIn: string): string {
  return `:white_check_mark: Execution final for candidate \`${candidateId}\`: \`${txHash}\` -- profit headroom ${profitHeadroom} of ${tokenIn}`;
}

export function formatExecutionFailed(candidateId: string, reason: string): string {
  return `:x: Execution failed for candidate \`${candidateId}\`: ${reason}`;
}

export function formatCriticalFault(context: string, reason: string): string {
  return `:rotating_light: Critical fault in ${context}: ${reason}`;
}
