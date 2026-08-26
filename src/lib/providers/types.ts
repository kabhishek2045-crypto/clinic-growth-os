/**
 * MASTER_PROMPT §46 — provider abstractions.
 *
 * Business logic depends on these interfaces, never on Neon, R2, Better Auth,
 * Razorpay, Meta, or Vercel directly (§4.4, §46). Every one ships with a mock in
 * mocks.ts, so no milestone is ever blocked waiting on an external account.
 *
 * AnimatedAnatomyProvider (§32.4) is declared here and mocked, but has no real
 * implementation in Phase 1 — §49 excludes the Visual Health Advisor by name.
 * It exists so consultation and portal code can be written against a stable
 * seam now rather than being retrofitted in Phase 2.
 */

export interface SendResult {
  providerMessageId: string;
  status: 'queued' | 'sent' | 'failed';
  error?: string;
}

export interface WhatsAppProvider {
  readonly name: string;
  sendTemplate(input: {
    to: string;
    templateName: string;
    languageCode: string;
    variables: Record<string, string>;
  }): Promise<SendResult>;
}

export interface SMSProvider {
  readonly name: string;
  send(input: { to: string; body: string }): Promise<SendResult>;
}

export interface EmailProvider {
  readonly name: string;
  send(input: { to: string; subject: string; html: string; from?: string }): Promise<SendResult>;
}

export interface PaymentProvider {
  readonly name: string;
  createOrder(input: { amountMinor: number; currency: 'INR'; receipt: string }): Promise<{
    orderId: string;
  }>;
  /** §22, §53 — payment status is verified server-side, never trusted from the browser. */
  verifyWebhook(input: { rawBody: string; signature: string }): Promise<{
    valid: boolean;
    event?: { type: string; orderId: string; paymentId: string; amountMinor: number };
  }>;
}

export interface DomainProvider {
  readonly name: string;
  addDomain(
    domain: string,
  ): Promise<{ verificationRecords: { type: string; name: string; value: string }[] }>;
  checkStatus(domain: string): Promise<{ verified: boolean; sslActive: boolean }>;
  removeDomain(domain: string): Promise<void>;
}

export interface StorageProvider {
  readonly name: string;
  /** §37 — tenant-scoped key: clinic_id/patient_id/document_id/file.ext */
  put(input: { key: string; body: Uint8Array; contentType: string }): Promise<{ key: string }>;
  /** §21, §37, §53 — expiring signed URL. Private medical files never get a permanent URL. */
  signedUrl(input: { key: string; expiresInSeconds: number }): Promise<string>;
  delete(key: string): Promise<void>;
}

export interface AIProvider {
  readonly name: string;
  /** §30 — assistive only. Never diagnoses, never prescribes. */
  complete(input: {
    system: string;
    prompt: string;
    maxTokens?: number;
  }): Promise<{ text: string }>;
}

export interface AnimatedAnatomyProvider {
  readonly name: string;
  /** Phase 2 (§32.4). Mock-only in Phase 1. */
  getVariantForCondition(input: {
    conditionCode: string;
    doctorId: string;
  }): Promise<{ variantId: string; assetRef: string; licenseSource: string } | null>;
}

export interface Providers {
  whatsapp: WhatsAppProvider;
  sms: SMSProvider;
  email: EmailProvider;
  payment: PaymentProvider;
  domain: DomainProvider;
  storage: StorageProvider;
  ai: AIProvider;
  anatomy: AnimatedAnatomyProvider;
}
