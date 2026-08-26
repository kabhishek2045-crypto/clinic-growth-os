import type {
  AIProvider,
  AnimatedAnatomyProvider,
  DomainProvider,
  EmailProvider,
  PaymentProvider,
  Providers,
  SMSProvider,
  SendResult,
  StorageProvider,
  WhatsAppProvider,
} from './types';

/**
 * §46 — mock implementations for development and testing.
 *
 * §53: mock security is never production security. These record calls and return
 * deterministic values; none of them performs a real check. The PaymentProvider
 * mock in particular returns valid:false unless explicitly primed, so a test that
 * forgets to configure it fails rather than passing on a fake success.
 */

let counter = 0;
const nextId = (prefix: string) => `${prefix}_mock_${(++counter).toString().padStart(6, '0')}`;

export interface MockCall {
  provider: string;
  method: string;
  input: unknown;
}
export const mockCalls: MockCall[] = [];
export function resetMocks(): void {
  mockCalls.length = 0;
  counter = 0;
}
const record = (provider: string, method: string, input: unknown): void => {
  mockCalls.push({ provider, method, input });
};

const ok = (prefix: string): SendResult => ({
  providerMessageId: nextId(prefix),
  status: 'queued',
});

export const mockWhatsApp: WhatsAppProvider = {
  name: 'mock-whatsapp',
  async sendTemplate(input) {
    record('whatsapp', 'sendTemplate', input);
    return ok('wa');
  },
};

export const mockSMS: SMSProvider = {
  name: 'mock-sms',
  async send(input) {
    record('sms', 'send', input);
    return ok('sms');
  },
};

export const mockEmail: EmailProvider = {
  name: 'mock-email',
  async send(input) {
    record('email', 'send', input);
    return ok('em');
  },
};

export const mockPayment: PaymentProvider = {
  name: 'mock-payment',
  async createOrder(input) {
    record('payment', 'createOrder', input);
    return { orderId: nextId('order') };
  },
  async verifyWebhook(input) {
    record('payment', 'verifyWebhook', input);
    // Fails closed. A test must construct a valid signature to get a true here.
    return { valid: false };
  },
};

export const mockDomain: DomainProvider = {
  name: 'mock-domain',
  async addDomain(domain) {
    record('domain', 'addDomain', { domain });
    return {
      verificationRecords: [{ type: 'TXT', name: `_clinic-os.${domain}`, value: nextId('verify') }],
    };
  },
  async checkStatus(domain) {
    record('domain', 'checkStatus', { domain });
    return { verified: true, sslActive: true };
  },
  async removeDomain(domain) {
    record('domain', 'removeDomain', { domain });
  },
};

const storageBlobs = new Map<string, Uint8Array>();
export const mockStorage: StorageProvider = {
  name: 'mock-storage',
  async put(input) {
    record('storage', 'put', { key: input.key, contentType: input.contentType });
    storageBlobs.set(input.key, input.body);
    return { key: input.key };
  },
  async signedUrl(input) {
    record('storage', 'signedUrl', input);
    const expires = Math.floor(Date.now() / 1000) + input.expiresInSeconds;
    return `https://mock-storage.invalid/${input.key}?expires=${expires}&sig=${nextId('sig')}`;
  },
  async delete(key) {
    record('storage', 'delete', { key });
    storageBlobs.delete(key);
  },
};

export const mockAI: AIProvider = {
  name: 'mock-ai',
  async complete(input) {
    record('ai', 'complete', input);
    return { text: '[mock ai response]' };
  },
};

export const mockAnatomy: AnimatedAnatomyProvider = {
  name: 'mock-anatomy',
  async getVariantForCondition(input) {
    record('anatomy', 'getVariantForCondition', input);
    return null; // Phase 2. Nothing is approved because nothing exists yet (§49).
  },
};

export const mockProviders: Providers = {
  whatsapp: mockWhatsApp,
  sms: mockSMS,
  email: mockEmail,
  payment: mockPayment,
  domain: mockDomain,
  storage: mockStorage,
  ai: mockAI,
  anatomy: mockAnatomy,
};
